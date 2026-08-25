import Foundation

/// The Claude desktop app keeps a plain-JSON record of the plan usage it shows
/// in its own menu bar:
///
///   ~/Library/Application Support/Claude/plan-usage-history.json
///   { "version": 2, "samples": [ { "t": <ms>, "org": "<uuid>", "u": { "fh": 72, "sd": 32 } } ] }
///
/// The short keys inside `u` are the plan's limit windows. It is the only file
/// on disk that carries real plan percentages: no token, no Keychain prompt,
/// nothing decrypted — the app wrote it there itself.
///
/// What it does NOT carry: reset times and model display names. Those live only
/// in the desktop app's memory, so they have to come from somewhere else.
///
/// Freshness is the catch. The desktop app polls every 15 min (every 5 min for
/// half an hour after you touch the machine) and **skips the poll entirely
/// while the system has been idle for 10 minutes or the screen is locked**.
/// A sample can therefore be hours old, which is why every reading carries the
/// timestamp it was taken at and callers must age-check it.
enum ClaudeDesktopUsage {
    /// One limit window as written to disk.
    struct Window {
        /// The long name the API uses ("five_hour", "seven_day_opus"…).
        let field: String
        let percent: Double
    }

    struct Sample {
        let date: Date
        /// Organization UUID the reading belongs to (not a credential).
        let org: String?
        let windows: [Window]

        func percent(_ field: String) -> Double? {
            windows.first { $0.field == field }?.percent
        }
        var fiveHour: Double? { percent("five_hour") }
        var sevenDay: Double? { percent("seven_day") }
    }

    /// Short key → API field name, straight out of the desktop app's own map.
    /// Anything unknown is kept under its raw key rather than dropped, so a
    /// window Anthropic adds later still shows up instead of silently vanishing.
    static let fieldForKey: [String: String] = [
        "fh": "five_hour",
        "sd": "seven_day",
        "so": "seven_day_opus",
        "sn": "seven_day_sonnet",
        "cw": "seven_day_cowork",
        "oa": "seven_day_oauth_apps",
        "om": "seven_day_omelette",
        "op": "omelette_promotional",
        "xu": "extra_usage",
    ]

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// All samples, oldest first. Handles both the current schema and the
    /// legacy v1 shape (`{t, fh, sd}` flat on the sample).
    static func samples(url: URL = defaultURL) -> [Sample] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["samples"] as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry -> Sample? in
            guard let ms = UsageJSON.double(entry["t"]) else { return nil }
            // v2 nests the windows under "u"; v1 put fh/sd on the sample itself.
            let container = entry["u"] as? [String: Any] ?? entry
            var windows: [Window] = []
            for (key, value) in container {
                // Outside 0…100 it is not a percentage — drop it rather than
                // clamp it into a convincing-looking full bar.
                guard key != "t", key != "org",
                      let percent = UsageJSON.double(value),
                      (0...100).contains(percent) else { continue }
                windows.append(Window(field: fieldForKey[key] ?? key, percent: percent))
            }
            guard !windows.isEmpty else { return nil }
            return Sample(date: Date(timeIntervalSince1970: ms / 1000),
                          org: entry["org"] as? String,
                          windows: windows.sorted { order($0.field) < order($1.field) })
        }.sorted { $0.date < $1.date }
    }

    /// Display order: session window first, then the general weekly, then the
    /// per-model weeklies alphabetically — the same order the apps show.
    private static func order(_ field: String) -> String {
        switch field {
        case "five_hour": return "0"
        case "seven_day": return "1"
        case "extra_usage": return "9"
        default: return "5\(field)"
        }
    }

    static func latest(url: URL = defaultURL) -> Sample? {
        samples(url: url).last
    }

    /// How old a reading may be and still be shown as a percentage.
    ///
    /// The desktop app polls every 15 minutes while you are at the machine, so
    /// two missed cycles mean it stopped sampling and the number on disk is
    /// frozen. Past that point the value is not displayed at all — an old
    /// percentage that looks current is worse than no percentage, and it is
    /// exactly how the app came to show a four-hour-old "24%" against a real
    /// 32%. Weekly windows get no extra slack: a busy week moves them just as
    /// fast as a session.
    static let freshMaxAge: TimeInterval = 30 * 60

    /// Minutes each window spans, for reset math and the age rule above.
    static func windowMinutes(forField field: String) -> Int {
        field == "five_hour" ? 300 : 10080
    }
}
