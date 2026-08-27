import Foundation

enum StatusSource: String, Codable {
    case live           // fetched from the provider's API just now
    case localSnapshot  // read from a file the provider's own app wrote
    case localEstimate  // computed from local transcripts (no percentages)
}

enum ConnectionState: String, Codable {
    case ok, notConnected, needsConsent, needsReconnect, rateLimited
}

struct LimitWindow: Codable {
    /// Stable identity across refreshes — the key usage history is tracked by.
    let id: String
    let labelKey: String      // "window.5h" | "window.weekModel" | a literal name
    /// Substituted into `labelKey` when it carries a %@ — the model name of a
    /// per-model window. Kept apart from the key so the row re-translates when
    /// the user switches language, instead of freezing the words of the fetch.
    var labelArgument: String?
    let usedPercent: Double?  // nil → no bar (local estimates: caps unknown)
    let resetsAt: Date?
    let windowMinutes: Int?
    let tokensUsed: Int?      // absolute count when a source provides it
    /// When this particular value was read, when that differs from "now"
    /// (a snapshot written by another app). nil means current.
    var readAt: Date?
}

extension LimitWindow {
    /// How old a reading may be and still describe the present.
    static let freshFor: TimeInterval = 30 * 60

    /// A value read long enough ago that it is history, not status.
    ///
    /// Rows still show it, with its age spelled out, because "93 % three days
    /// ago" is information. A bar in the menu bar is not: it is a claim about
    /// right now, and drawing an old number there is the one thing this app
    /// must never do.
    var isStale: Bool {
        guard let readAt else { return false }
        return Date().timeIntervalSince(readAt) > Self.freshFor
    }
}

/// One block of limits: the plan's general limits, or a per-model group
/// such as "GPT-5.3-Codex-Spark".
struct LimitGroup: Codable {
    /// nil → the plan's general limits (rendered with the localized "general" label).
    let title: String?
    var windows: [LimitWindow]
}

/// Cacheable snapshot of one provider — percentages and dates only, never tokens.
struct ProviderStatus: Codable {
    let providerID: String    // "codex" | "claude"
    /// Unique per credential, so two accounts of the same provider never share
    /// a card or a history entry.
    var accountID: String = ""
    /// Masked e-mail shown under the provider name, when it is known.
    var accountLabel: String?
    var groups: [LimitGroup]
    var planType: String?     // raw string ("pro", "max"…) — never an enum, values drift
    var source: StatusSource
    var lastUpdated: Date
    var state: ConnectionState
    /// Localization key for an extra explanatory line (reconnect hints, etc.).
    var noteKey: String?

    var allWindows: [LimitWindow] { groups.flatMap { $0.windows } }

    static func empty(_ id: String, state: ConnectionState, noteKey: String? = nil,
                      accountID: String = "", accountLabel: String? = nil) -> ProviderStatus {
        ProviderStatus(providerID: id, accountID: accountID, accountLabel: accountLabel,
                       groups: [], planType: nil, source: .localEstimate,
                       lastUpdated: Date(), state: state, noteKey: noteKey)
    }

    /// Card identity: provider plus account.
    var key: String { accountID.isEmpty ? providerID : "\(providerID)#\(accountID)" }
}
