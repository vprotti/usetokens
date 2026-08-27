import Foundation

/// Who is signed into Claude on this Mac.
///
/// Claude Code keeps `~/.claude.json` for itself — plain JSON, no encryption,
/// written by the tool on every launch. Its `oauthAccount` object is an
/// identity card: the e-mail, the organization, the plan tier. There is no
/// token in it and nothing in it can be used to call anything.
///
/// That distinction is the whole reason this file exists. Knowing *whether*
/// someone is signed in, and to which plan, is what lets the card appear at all
/// and label itself correctly — and it can be known without going anywhere near
/// a credential. The numbers still have to come from a source that measures
/// them; this only answers "is there a Claude here, and whose".
///
/// The alternative was launching `claude auth status`, which answers the same
/// question by starting a 300 MB binary and only ever speaks for the command
/// line tool's own sign-in. Reading a file the tool already wrote is cheaper
/// and covers the desktop app too.
enum ClaudeAccount {

    struct Info {
        let email: String?
        let organizationUUID: String?
        /// Ready to display: "Max 20x", "Pro", "Team" — never a raw key.
        let plan: String?
        /// When Claude last refreshed this profile. Old means the sign-in is
        /// old, not that it is gone.
        let fetchedAt: Date?
    }

    /// Overridable for the self-test.
    static var homeOverride: URL?
    private static var home: URL {
        homeOverride ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static var configURL: URL { home.appendingPathComponent(".claude.json") }

    /// Cached: the file is a few dozen kilobytes and is read on every refresh.
    private static var cache: (date: Date, value: Info?)?
    private static let cacheTTL: TimeInterval = 60

    static func invalidate() { cache = nil }

    static func current() -> Info? {
        if let cache, Date().timeIntervalSince(cache.date) < cacheTTL { return cache.value }
        let value = read()
        cache = (Date(), value)
        return value
    }

    private static func read() -> Info? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return nil }

        // An account object with no organization is a leftover shell from a
        // sign-out, not a sign-in.
        let org = account["organizationUuid"] as? String
        let email = account["emailAddress"] as? String
        guard org != nil || email != nil else { return nil }

        var fetched: Date?
        if let ms = UsageJSON.double(account["profileFetchedAt"]), ms > 0 {
            fetched = Date(timeIntervalSince1970: ms / 1000)
        }

        return Info(email: email, organizationUUID: org,
                    plan: planName(account), fetchedAt: fetched)
    }

    /// The plan, preferring the most specific thing the file knows.
    ///
    /// `organizationRateLimitTier` is the one that distinguishes the two Max
    /// plans — "default_claude_max_20x" — which is exactly the distinction a
    /// usage app should not get wrong. `organizationType` ("claude_max") is
    /// the coarser fallback, and both are decoded by shape rather than by a
    /// fixed list, so a tier introduced next year still reads sensibly.
    private static func planName(_ account: [String: Any]) -> String? {
        if let tier = account["organizationRateLimitTier"] as? String,
           let name = prettyTier(tier) { return name }
        if let type = account["organizationType"] as? String,
           let name = prettyTier(type) { return name }
        return nil
    }

    private static func prettyTier(_ raw: String) -> String? {
        var parts = raw.split(separator: "_").map(String.init)
        // Strip the noise words these keys are padded with.
        parts.removeAll { $0 == "default" || $0 == "claude" || $0 == "tier" }
        guard !parts.isEmpty else { return nil }
        return parts.map { part in
            // "20x" stays "20x"; "max" becomes "Max".
            part.first?.isNumber == true ? part : part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }
}
