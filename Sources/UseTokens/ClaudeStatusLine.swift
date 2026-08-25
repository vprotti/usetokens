import Foundation

/// The supported, credential-free way to read Claude plan usage.
///
/// Claude Code runs the command configured under `statusLine` in
/// `~/.claude/settings.json` and hands it, on stdin, the JSON it uses to draw
/// its own status line. That JSON carries the plan windows:
///
///   { "rate_limits": {
///       "five_hour": { "used_percentage": 72, "resets_at": 1787620380 },
///       "seven_day": { "used_percentage": 32, "resets_at": 1787889540 } } }
///
/// So UseTokens installs a three-line shell script as that command. The script
/// saves the payload where this app can read it and prints the status line.
/// Nothing is decrypted, no token is read, nothing leaves the Mac: Claude Code
/// hands over its own numbers because that is what the hook is for.
///
/// The numbers are the account's, not one app's — claude.ai, Claude Code and
/// the Claude desktop app all draw from the same limit.
enum ClaudeStatusLine {
    struct Window {
        let field: String
        let percent: Double
        let resetsAt: Date?
    }

    struct Reading {
        /// When Claude Code last ran the script.
        let date: Date
        let windows: [Window]
        let planType: String?
    }

    // MARK: - Paths

    /// Overridable so the self-test can exercise install/uninstall against a
    /// scratch directory instead of the user's real configuration.
    static var homeOverride: URL?
    private static var home: URL {
        homeOverride ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/UseTokens")
    }
    static var dumpURL: URL { supportDirectory.appendingPathComponent("claude-usage.json") }
    static var scriptURL: URL { supportDirectory.appendingPathComponent("claude-statusline.sh") }
    static var settingsURL: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    /// Marks the entry as ours, so install/uninstall never touch someone else's.
    private static let marker = "UseTokens"

    // MARK: - Reading

    /// A status line only exists while a Claude Code session is running, so a
    /// dump can be minutes or days old. The caller decides what is too old;
    /// this just reports honestly when it was written.
    static func latest() -> Reading? {
        guard let data = try? Data(contentsOf: dumpURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let written = (try? dumpURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast

        guard let limits = obj["rate_limits"] as? [String: Any] else { return nil }
        var windows: [Window] = []
        for (field, value) in limits {
            guard let entry = value as? [String: Any],
                  let percent = usedPercentage(entry) else { continue }
            var resets: Date?
            if let seconds = UsageJSON.double(entry["resets_at"]), seconds > 1_000_000_000 {
                resets = Date(timeIntervalSince1970: seconds)
            } else if let text = entry["resets_at"] as? String {
                resets = UsageJSON.parseISO(text)
            }
            // Past its own reset the window has rolled over and this number
            // describes a period that is over. Drop it rather than show it.
            if let resets, resets <= Date() { continue }
            windows.append(Window(field: field, percent: percent, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }

        return Reading(date: written, windows: windows,
                       planType: (obj["subscription"] as? [String: Any])?["type"] as? String)
    }

    /// Claude Code has shipped builds where `used_percentage` arrives holding a
    /// unix timestamp instead of a percentage. Anything outside 0…100 is a bug,
    /// not a reading, and is dropped rather than drawn as a full bar.
    private static func usedPercentage(_ entry: [String: Any]) -> Double? {
        guard let raw = UsageJSON.double(entry["used_percentage"]) else { return nil }
        return (0...100).contains(raw) ? raw : nil
    }

    // MARK: - Installing

    static func isInstalled() -> Bool {
        currentEntry()?["command"] as? String == scriptURL.path
    }

    private static func currentEntry() -> [String: Any]? {
        readSettings()?["statusLine"] as? [String: Any]
    }

    /// Registers the bridge, keeping whatever status line was already there by
    /// chaining to it. Returns false if the settings file could not be updated.
    @discardableResult
    static func install() -> Bool {
        // Read first, and refuse to touch a file we do not understand. Writing
        // a fresh object over settings we failed to parse would wipe every
        // preference the user has — the worst thing this feature could do.
        guard let settings0 = readSettings() else { return false }
        var settings = settings0

        // Anything the user had before keeps running and keeps drawing the line.
        let existing = settings["statusLine"] as? [String: Any]
        // Already installed: the entry we are looking at is ours, so the thing
        // worth preserving is whatever we stashed the first time.
        let original: [String: Any]? = existing.flatMap { entry in
            entry["command"] as? String == scriptURL.path
                ? entry[marker + "Original"] as? [String: Any]
                : entry
        }
        var inner = original?["command"] as? String
        // An empty command is not a command — storing it would make uninstall
        // "restore" a status line that does nothing.
        if inner?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { inner = nil }

        guard writeScript(chainingTo: inner) else { return false }

        var entry: [String: Any] = [
            "type": "command",
            "command": scriptURL.path,
            // Re-run while a session sits idle so the reading keeps up.
            "refreshInterval": 60,
        ]
        if let original, inner != nil { entry[marker + "Original"] = original }
        if let padding = original?["padding"] { entry["padding"] = padding }

        // Leave the user's file alone when it already says exactly this.
        if let existing, NSDictionary(dictionary: existing).isEqual(to: entry) { return true }
        settings["statusLine"] = entry

        return write(settings)
    }

    /// Puts back whatever was there before, or removes the key entirely.
    @discardableResult
    static func uninstall() -> Bool {
        guard var settings = readSettings() else { return false }

        guard let entry = settings["statusLine"] as? [String: Any],
              entry["command"] as? String == scriptURL.path else { return true }

        // The original entry was stashed whole, so every key it had — padding,
        // refreshInterval, hideVimModeIndicator — comes back exactly as it was.
        if let original = entry[marker + "Original"] as? [String: Any] {
            settings["statusLine"] = original
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try? FileManager.default.removeItem(at: dumpURL)
        try? FileManager.default.removeItem(at: scriptURL)
        return write(settings)
    }

    /// The settings file as a dictionary. Returns an empty one when the file
    /// simply is not there yet, and nil when it exists but cannot be read or
    /// parsed — the caller must then leave it alone.
    private static func readSettings() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func write(_ settings: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(settings),
              let data = try? JSONSerialization.data(
                withJSONObject: settings,
                // The user opens this file; "\/Users\/…" would be an eyesore.
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        // An atomic write swaps the file, which would turn a symlinked
        // settings.json into a regular one — write through the link instead.
        let target = settingsURL.resolvingSymlinksInPath()
        do { try data.write(to: target, options: .atomic) } catch { return false }
        return true
    }

    /// The bridge script. It hands the payload to this app — which saves only
    /// the usage numbers out of it — and then prints the status line: the
    /// user's own previous command when there was one, otherwise our summary.
    private static func writeScript(chainingTo inner: String?) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let binary = shellQuote(Bundle.main.executableURL?.path ?? "")
        // With a chained command, ours still saves the reading but stays quiet
        // so the line on screen is the one the user chose.
        let save = """
        if [ -x \(binary) ]; then
          printf '%s' "$payload" | \(binary) --statusline\(inner == nil ? "" : " >/dev/null")
        fi
        """
        let tail = inner.map { """
        \(save)
        printf '%s' "$payload" | { \($0); }
        """ } ?? save

        let script = """
        #!/bin/bash
        # Installed by UseTokens (nasmac.app) to read Claude Code's own usage
        # numbers. Nothing here reads a credential and nothing leaves this Mac.
        # Remove it by turning the setting off in UseTokens.
        umask 077
        payload="$(cat)"
        \(tail)

        """
        guard let data = script.data(using: .utf8) else { return false }
        do {
            try data.write(to: scriptURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch { return false }
        return true
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Rendering the line Claude Code shows

    /// `--statusline`: read Claude Code's payload on stdin, keep only the usage
    /// numbers, and print one compact line.
    ///
    /// The filtering is the point. The payload also carries the session id, the
    /// working directory and the transcript path — none of that is any of this
    /// app's business, so it never reaches disk.
    static func renderLine() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = obj["rate_limits"] as? [String: Any], !limits.isEmpty
        else { return }

        var kept: [String: Any] = ["rate_limits": limits]
        if let subscription = obj["subscription"] as? [String: Any] {
            kept["subscription"] = subscription
        }
        save(kept)

        var parts: [String] = []
        for (label, field) in [("5h", "five_hour"), ("7d", "seven_day")] {
            guard let entry = limits[field] as? [String: Any],
                  let percent = usedPercentage(entry) else { continue }
            parts.append("\(label) \(Int(percent.rounded()))%")
        }
        guard !parts.isEmpty else { return }
        print("◔ " + parts.joined(separator: " · "))
    }

    private static func save(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try? data.write(to: dumpURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dumpURL.path)
    }

}
