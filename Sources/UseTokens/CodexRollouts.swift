import Foundation

/// Shared lossy-JSON helpers for the usage payloads. Field names drift between
/// the live endpoint and rollout files — always parse defensively.
enum UsageJSON {
    /// Depth-first search for the first dictionary stored under `key`.
    static func findDict(_ key: String, in obj: Any, depth: Int = 0) -> [String: Any]? {
        guard depth < 8 else { return nil }
        if let dict = obj as? [String: Any] {
            if let hit = dict[key] as? [String: Any] { return hit }
            for value in dict.values {
                if let hit = findDict(key, in: value, depth: depth + 1) { return hit }
            }
        } else if let arr = obj as? [Any] {
            for value in arr {
                if let hit = findDict(key, in: value, depth: depth + 1) { return hit }
            }
        }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func windowLabelKey(minutes: Int?) -> String {
        switch minutes {
        case .some(280...320): return "window.5h"
        case .some(10000...10160): return "window.week"
        case .some(let m) where m >= 1440: return "\(m / 1440) d"
        case .some(let m) where m >= 60: return "\(m / 60) h"
        case .some(let m): return "\(m) min"
        case nil: return "window.5h"
        }
    }

    /// Accepts both live ("used_percent"/"reset_at"/"limit_window_seconds") and
    /// rollout ("used_percent"/"resets_at"/"window_minutes"/"resets_in_seconds") shapes.
    static func window(from dict: [String: Any], eventDate: Date,
                       idPrefix: String) -> LimitWindow? {
        guard let percent = double(dict["used_percent"] ?? dict["usage_percent"]) else { return nil }

        var minutes: Int?
        if let m = double(dict["window_minutes"]) { minutes = Int(m) }
        else if let s = double(dict["limit_window_seconds"] ?? dict["window_seconds"]) { minutes = Int(s / 60) }

        var resets: Date?
        if let t = double(dict["resets_at"] ?? dict["reset_at"]) {
            resets = Date(timeIntervalSince1970: t)
        } else if let s = (dict["resets_at"] ?? dict["reset_at"]) as? String {
            resets = parseISO(s)
        } else if let rel = double(dict["resets_in_seconds"] ?? dict["reset_after_seconds"]) {
            // "reset_after_seconds" repeats the full window length once a window
            // is untouched, so it is only trustworthy as a relative fallback.
            resets = eventDate.addingTimeInterval(rel)
        }

        let label = windowLabelKey(minutes: minutes)
        return LimitWindow(
            id: "\(idPrefix).\(minutes ?? 0)",
            labelKey: label,
            usedPercent: max(0, min(100, percent)),
            resetsAt: resets,
            windowMinutes: minutes,
            tokensUsed: nil)
    }

    static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}

/// Offline fallback: the Codex CLI/app writes a rate_limits snapshot into its
/// rollout JSONLs on every turn — the newest one is the freshest local truth.
enum CodexRollouts {
    static var defaultBase: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func latestSnapshot(baseDir: URL = defaultBase) -> ProviderStatus? {
        let fm = FileManager.default
        var candidates: [(url: URL, mtime: Date)] = []

        for sub in ["sessions", "archived_sessions"] {
            let dir = baseDir.appendingPathComponent(sub)
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                         options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                candidates.append((url, mtime))
            }
        }
        candidates.sort { $0.mtime > $1.mtime }

        for candidate in candidates.prefix(20) {
            if let status = snapshot(from: candidate.url, mtime: candidate.mtime) {
                return status
            }
        }
        return nil
    }

    private static func snapshot(from url: URL, mtime: Date) -> ProviderStatus? {
        guard let tail = readTail(url, maxBytes: 256 * 1024) else { return nil }
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines.reversed() {
            guard line.contains("\"rate_limits\""),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let rl = UsageJSON.findDict("rate_limits", in: obj) else { continue }

            var windows: [LimitWindow] = []
            for key in ["primary", "secondary", "primary_window", "secondary_window"] {
                if let w = rl[key] as? [String: Any],
                   let parsed = UsageJSON.window(from: w, eventDate: mtime,
                                                 idPrefix: "codex.general") {
                    windows.append(parsed)
                }
            }
            // Stale percentages are misinformation — drop windows already reset.
            windows.removeAll { ($0.resetsAt ?? .distantFuture) < Date() }
            guard !windows.isEmpty else { return nil }
            windows.sort { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }

            let plan = (rl["plan_type"] as? String)
            return ProviderStatus(
                providerID: "codex", groups: [LimitGroup(title: nil, windows: windows)],
                planType: plan, source: .localSnapshot, lastUpdated: mtime,
                state: .ok, noteKey: nil)
        }
        return nil
    }

    /// Reads at most the final `maxBytes` of the file as UTF-8.
    private static func readTail(_ url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }
}
