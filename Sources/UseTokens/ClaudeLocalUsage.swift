import Foundation

/// Offline estimate from Claude Code transcripts (~/.claude/projects/**/*.jsonl),
/// ccusage-style: 5-hour blocks anchored to the full UTC hour of the first entry.
/// Caps are unknown locally, so this yields token counts, never percentages.
enum ClaudeLocalUsage {
    struct Estimate {
        let tokens: Int
        let blockEndsAt: Date
    }

    static func activeBlock(baseDir: URL? = nil) -> Estimate? {
        let root = baseDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-6 * 3600)

        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return nil }

        var entries: [(date: Date, tokens: Int)] = []
        var seen = Set<String>()

        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard mtime > cutoff else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"usage\""),
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let date = UsageJSON.parseISO(ts)
                else { continue }

                let dedup = "\(message["id"] as? String ?? "")|\(obj["requestId"] as? String ?? UUID().uuidString)"
                guard !seen.contains(dedup) else { continue }
                seen.insert(dedup)

                let tokens = ["input_tokens", "output_tokens",
                              "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .compactMap { UsageJSON.double(usage[$0]) }
                    .reduce(0) { $0 + Int($1) }
                if tokens > 0 { entries.append((date, tokens)) }
            }
        }
        guard !entries.isEmpty else { return nil }
        entries.sort { $0.date < $1.date }

        // Walk entries into 5h blocks; keep the last block.
        let blockLength: TimeInterval = 5 * 3600
        var blockStart = floorToUTCHour(entries[0].date)
        var blockTokens = 0
        var lastEntryDate = entries[0].date

        for entry in entries {
            let pastBlock = entry.date >= blockStart.addingTimeInterval(blockLength)
            let bigGap = entry.date.timeIntervalSince(lastEntryDate) > blockLength
            if pastBlock || bigGap {
                blockStart = floorToUTCHour(entry.date)
                blockTokens = 0
            }
            blockTokens += entry.tokens
            lastEntryDate = entry.date
        }

        let blockEnd = blockStart.addingTimeInterval(blockLength)
        guard Date() < blockEnd else { return nil } // block already over
        return Estimate(tokens: blockTokens, blockEndsAt: blockEnd)
    }

    private static func floorToUTCHour(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        return cal.date(from: comps) ?? date
    }
}
