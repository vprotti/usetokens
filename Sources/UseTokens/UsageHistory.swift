import Foundation

/// Remembers what each limit window looked like on the previous refresh, so the
/// app can tell when a window rolled over, how full it was right before, and
/// (for sources that don't report a reset time) when the next one is due.
///
/// Stored in UserDefaults as plain numbers and dates — never tokens.
enum UsageHistory {
    struct Record: Codable {
        var lastPercent: Double?
        var lastSeen: Date
        /// The reset time the window itself reported last time (in the future).
        var lastWindowReset: Date?
        /// When this app actually observed a rollover (in the past).
        var observedResetAt: Date?
        var percentBeforeReset: Double?
        var windowMinutes: Int?
        /// Which tier produced the last value; a tier change is not a rollover.
        var lastSource: String?
    }

    struct ResetEvent {
        let windowID: String
        let providerID: String
        let labelKey: String
        let groupTitle: String?
        let at: Date
        let percentBefore: Double
    }

    /// A drop of at least this many points counts as a rollover, not noise.
    private static let resetDropPoints: Double = 8
    /// Older baselines can't date a rollover, so they only re-seed the value.
    private static let maxBaselineAge: TimeInterval = 60 * 60

    private static let key = "usageHistory"

    private static func load() -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ records: [String: Record]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: key)
    }

    /// Folds a fresh set of statuses into the history and returns the windows
    /// that demonstrably rolled over since the previous refresh.
    @discardableResult
    static func record(_ statuses: [ProviderStatus]) -> [ResetEvent] {
        var records = load()
        var events: [ResetEvent] = []
        let now = Date()

        for status in statuses {
            let source = status.source.rawValue
            for group in status.groups {
                for window in group.windows {
                    guard let percent = window.usedPercent else { continue }
                    let previous = records[window.id]

                    // Only a like-for-like comparison can prove a rollover:
                    // a different source tier reports a different number for
                    // the same window, and a stale baseline can't date one.
                    let comparable = previous.map {
                        $0.lastSource == source
                            && now.timeIntervalSince($0.lastSeen) <= maxBaselineAge
                    } ?? false

                    var didReset = false
                    if comparable, let old = previous?.lastPercent, percent <= old - resetDropPoints {
                        didReset = true
                    }
                    // The window itself moved on to a new period.
                    if comparable, let oldReset = previous?.lastWindowReset,
                       let newReset = window.resetsAt,
                       newReset > oldReset.addingTimeInterval(60) {
                        didReset = true
                    }

                    var record = previous ?? Record(
                        lastPercent: nil, lastSeen: now, lastWindowReset: nil,
                        observedResetAt: nil, percentBeforeReset: nil,
                        windowMinutes: window.windowMinutes, lastSource: source)

                    if didReset, let before = previous?.lastPercent {
                        record.observedResetAt = now
                        record.percentBeforeReset = before
                        events.append(ResetEvent(
                            windowID: window.id, providerID: status.providerID,
                            labelKey: window.labelKey, groupTitle: group.title,
                            at: now, percentBefore: before))
                    }
                    record.lastPercent = percent
                    record.lastSeen = now
                    record.lastWindowReset = window.resetsAt
                    record.lastSource = source
                    record.windowMinutes = window.windowMinutes ?? record.windowMinutes
                    records[window.id] = record
                }
            }
        }
        save(records)
        return events
    }

    /// Next reset inferred from the last observed rollover — used for sources
    /// that report percentages but no reset time (the Claude desktop history).
    static func predictedReset(for windowID: String) -> Date? {
        guard let record = load()[windowID],
              let last = record.observedResetAt,
              let minutes = record.windowMinutes, minutes > 0 else { return nil }
        let length = TimeInterval(minutes) * 60
        var next = last.addingTimeInterval(length)
        let now = Date()
        while next < now { next = next.addingTimeInterval(length) }
        return next
    }

    /// A rollover recent enough to still be worth showing in the card.
    static func recentReset(for windowID: String,
                            within: TimeInterval = 6 * 3600) -> (at: Date, percentBefore: Double)? {
        guard let record = load()[windowID],
              let at = record.observedResetAt,
              let before = record.percentBeforeReset,
              Date().timeIntervalSince(at) < within else { return nil }
        return (at, before)
    }
}
