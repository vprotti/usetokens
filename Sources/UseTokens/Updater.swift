import AppKit
import CryptoKit

/// Keeps the app up to date from nasmac.app.
///
/// Safety rules, in order of importance:
///   • the manifest and the disk image are fetched over HTTPS only;
///   • the download must match the SHA-256 published in the manifest;
///   • the new bundle must carry this app's own bundle identifier;
///   • the swap is atomic with rollback — the old bundle is only deleted once
///     the new one is in place;
///   • nothing is installed when the bundle lives somewhere unwritable
///     (running from the DMG, or an admin-owned /Applications).
enum Updater {
    static let slug = "usetokens"
    static let appName = "UseTokens"

    /// Overridable for local testing against a staging server.
    static var baseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["NASMAC_UPDATE_BASE"],
           let url = URL(string: raw) { return url }
        return URL(string: "https://nasmac.app")!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    struct Release {
        let version: String
        let file: String
        let sha256: String
        let size: Int
        let notes: [String: String]
    }

    private static var checkTimer: Timer?
    private static var busy = false

    /// Set by the app: true while an update would take something away from the
    /// user right now (Caffeine holding the screen awake, a popover open).
    /// The daily timer simply tries again later.
    static var shouldPostpone: (() -> Bool)?

    // MARK: - Scheduling

    static func start() {
        checkTimer?.invalidate()
        // A daily check is plenty for an app that ships rarely.
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { _ in
            Task { await checkAndInstall() }
        }
        timer.tolerance = 3600
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer

        // Let launch settle before touching the network.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            Task { await checkAndInstall() }
        }
    }

    // MARK: - Check

    @discardableResult
    static func checkAndInstall(userInitiated: Bool = false) async -> Bool {
        guard Prefs.autoUpdate || userInitiated, !busy else { return false }
        busy = true
        defer { busy = false }

        guard let release = await fetchLatest(),
              isNewer(release.version, than: currentVersion) else { return false }
        // Give up on a version that keeps failing instead of looping forever.
        guard Prefs.updateAttempts(for: release.version) < 3 else { return false }
        if shouldPostpone?() == true { return false }
        return await install(release)
    }

    static func fetchLatest() async -> Release? {
        let url = baseURL.appendingPathComponent("updates/\(slug).json")
        guard url.scheme == "https" || isLocalTesting else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let latest = obj["latest"] as? [String: Any],
              let version = latest["version"] as? String,
              let file = latest["file"] as? String,
              let sha = latest["sha256"] as? String
        else { return nil }

        return Release(version: version, file: file, sha256: sha.lowercased(),
                       size: (latest["size"] as? Int) ?? 0,
                       notes: (latest["notes"] as? [String: String]) ?? [:])
    }

    private static var isLocalTesting: Bool {
        ProcessInfo.processInfo.environment["NASMAC_UPDATE_BASE"] != nil
    }

    /// Numeric, component-wise: 1.10.0 is newer than 1.9.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Install

    private static func install(_ release: Release) async -> Bool {
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
        else { return false }

        guard let dmg = await download(release) else { return false }
        defer { try? FileManager.default.removeItem(at: dmg) }

        guard let staged = mountAndStage(dmg: dmg, expecting: release) else { return false }
        return swap(staged: staged, target: target, version: release.version)
    }

    private static func download(_ release: Release) async -> URL? {
        let url = baseURL.appendingPathComponent(release.file)
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        guard let (temp, response) = try? await URLSession.shared.download(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let data = try? Data(contentsOf: temp, options: .mappedIfSafe)
        else { return nil }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else {
            NSLog("Updater: checksum mismatch, discarding download")
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
        // The system deletes the download at the end of the delegate call.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)-\(release.version).dmg")
        try? FileManager.default.removeItem(at: kept)
        guard (try? FileManager.default.moveItem(at: temp, to: kept)) != nil else { return nil }
        return kept
    }

    private static func mountAndStage(dmg: URL, expecting release: Release) -> URL? {
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)-mount-\(UUID().uuidString)")
        guard run("/usr/bin/hdiutil",
                  ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) else {
            return nil
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let source = mount.appendingPathComponent("\(appName).app")
        guard FileManager.default.fileExists(atPath: source.path),
              let plist = NSDictionary(contentsOf: source.appendingPathComponent("Contents/Info.plist")),
              plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              plist["CFBundleShortVersionString"] as? String == release.version
        else { return nil }

        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)-staged-\(release.version)")
        try? FileManager.default.removeItem(at: staged)
        try? FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let stagedApp = staged.appendingPathComponent("\(appName).app")
        guard run("/usr/bin/ditto", [source.path, stagedApp.path]) else { return nil }
        return stagedApp
    }

    /// Hands the swap to a detached shell script: the running bundle cannot
    /// replace itself while its own binary is mapped.
    ///
    /// Paths travel as arguments, never interpolated into the script text — an
    /// apostrophe in the user's folder name would otherwise make the script
    /// unparseable and the app would quit without ever coming back.
    private static func swap(staged: URL, target: URL, version: String) -> Bool {
        let temp = FileManager.default.temporaryDirectory
        let script = temp.appendingPathComponent("\(appName)-update-\(UUID().uuidString).sh")
        let started = temp.appendingPathComponent("\(appName)-update-\(UUID().uuidString).started")

        let body = """
        #!/bin/sh
        TARGET="$1"
        STAGED="$2"
        PID="$3"
        STARTED="$4"

        # Tell the app the script parsed and is running; without this it would
        # quit on faith and a broken script would strand the user.
        : > "$STARTED"

        # Wait for the old copy to quit (bounded, so a hung app cannot wedge us).
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done

        BACKUP="$TARGET.old-$$"
        if ! mv "$TARGET" "$BACKUP"; then
            /usr/bin/open "$TARGET" 2>/dev/null || true
            exit 1
        fi
        if /usr/bin/ditto "$STAGED" "$TARGET"; then
            /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
            rm -rf "$BACKUP"
        else
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
        fi
        rm -rf "$(dirname "$STAGED")"
        /usr/bin/open "$TARGET"
        rm -f "$STARTED" "$0"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, target.path, staged.path,
                             String(ProcessInfo.processInfo.processIdentifier), started.path]
        guard (try? process.run()) != nil else { return false }

        // Only hand over the process once the helper has proven it is alive.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: started.path) {
                Prefs.noteUpdateAttempt(version)
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        NSLog("Updater: helper did not start, keeping the current version")
        try? FileManager.default.removeItem(at: script)
        try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
        return false
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
