import Foundation

/// Asks Claude Code itself whether the user is signed in.
///
/// `claude auth status --json` is the tool's own supported way to report that,
/// and it answers without this app ever touching a credential:
///
///   { "loggedIn": true, "authMethod": "oauth", "apiProvider": "firstParty" }
///
/// That is the whole point of using it. UseTokens does not read, copy, decrypt
/// or store anyone's login — it asks the official tool a yes/no question and
/// believes the answer. When the answer is no, the Claude card is simply not
/// shown.
enum ClaudeCLI {
    struct Status {
        let loggedIn: Bool
        let authMethod: String?
    }

    /// Where a `claude` executable realistically lives. A menu bar app inherits
    /// a bare PATH from launchd, so guessing is not optional — every documented
    /// install location gets checked explicitly.
    static func executableURL() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        // The copy the Claude desktop app ships and keeps updated, newest first.
        let bundled = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        if let versions = try? fm.contentsOfDirectory(atPath: bundled.path) {
            for version in versions.sorted(by: versionDescending) {
                candidates.append(bundled.appendingPathComponent(
                    "\(version)/claude.app/Contents/MacOS/claude"))
            }
        }

        candidates += [
            home.appendingPathComponent(".claude/local/claude"),
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".bun/bin/claude"),
            home.appendingPathComponent(".volta/bin/claude"),
            home.appendingPathComponent("bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]

        // nvm keeps a bin directory per Node version and none of them are on a
        // GUI app's PATH, so they have to be looked up by hand.
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvm.path) {
            for version in versions.sorted(by: versionDescending) {
                candidates.append(nvm.appendingPathComponent("\(version)/bin/claude"))
            }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(dir))
                    .appendingPathComponent("claude"))
            }
        }

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    /// "2.1.237" > "2.1.9" — plain string sort would get that backwards.
    private static func versionDescending(_ a: String, _ b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for (l, r) in zip(lhs, rhs) where l != r { return l > r }
        return lhs.count > rhs.count
    }

    /// Runs `claude auth status --json`. Returns nil when Claude Code is not
    /// installed or does not answer — which is not the same as "signed out".
    ///
    /// Hopped onto a plain background thread on purpose: waiting on a child
    /// process would otherwise park one of Swift's cooperative threads for
    /// seconds, and the whole refresh runs on that pool.
    static func status() async -> Status? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: statusSync())
            }
        }
    }

    private static func statusSync() -> Status? {
        guard let executable = executableURL() else { return nil }
        guard let data = run(executable, ["auth", "status", "--json"], timeout: 8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = obj["loggedIn"] as? Bool
        else { return nil }
        return Status(loggedIn: loggedIn, authMethod: obj["authMethod"] as? String)
    }

    /// A short-lived child process with a hard timeout, so a hung CLI can never
    /// wedge a refresh. stdin is closed and stderr discarded: this is a
    /// question, not a session.
    private static func run(_ executable: URL, _ arguments: [String],
                            timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        // Never let a stray session inherit this app's environment quirks.
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_CODE_ENTRYPOINT"] = "usetokens"
        process.environment = env

        do { try process.run() } catch { return nil }

        // Read on a background queue: a full pipe buffer would deadlock a
        // waitUntilExit() that runs before the pipe is drained.
        var data = Data()
        let lock = NSLock()
        let reader = DispatchQueue(label: "br.com.nasralla.usetokens.claudecli")
        reader.async {
            let chunk = out.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); data = chunk; lock.unlock()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        // Give the reader a moment to finish draining after exit.
        reader.sync {}
        lock.lock(); defer { lock.unlock() }
        return data.isEmpty ? nil : data
    }
}
