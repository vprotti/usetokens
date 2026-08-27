import AppKit

/// Claude usage.
///
/// Where the numbers come from, in order of preference:
///
///  1. Claude Code's `statusLine` hook, which hands over the exact percentages
///     and reset times it draws its own status line with. Official, current,
///     and it never involves a credential — so it goes first. Only the terminal
///     Claude Code draws a status line, so this source is silent for someone
///     who works entirely inside the Claude desktop app.
///  2. Anthropic's usage endpoint, when Claude Code has a sign-in this app is
///     allowed to use. Adds the per-model weekly windows the hook omits.
///  3. `plan-usage-history.json`, which the Claude desktop app writes itself.
///     Real percentages, no reset times, and only while the app keeps polling.
///
/// All three describe the same account: claude.ai, Claude Code and the desktop
/// app draw from one limit.
///
/// What this app never does: read, decrypt or copy anybody's login out of an
/// encrypted store, and refresh a credential it did not create (rotating a
/// refresh token would sign the user out of Claude Code itself).
///
/// If nothing on this Mac was ever written by a signed-in Claude, no card is
/// shown at all. But "no current number" and "no Claude" are different things:
/// when a session clearly exists and none of the sources can be read right now,
/// the card stays and says so, because silently vanishing looks like a bug.
final class ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    var glyph: NSImage { ProviderGlyphs.claude }

    /// Hard minimum between live calls per account — the endpoint rate-limits.
    private static let liveGateSeconds: TimeInterval = 180
    private static var lastLiveAttempt: [String: Date] = [:]
    private static var lastLiveStatus: [String: ProviderStatus] = [:]
    /// `claude auth status` launches a 300 MB binary, so the answer is cached
    /// well past a refresh cycle and skipped whenever something local already
    /// proves the user is signed in.
    private static let cliStatusTTL: TimeInterval = 15 * 60
    /// How long a refresh waits on the macOS permission dialog before giving
    /// up on the live numbers for this cycle. Long enough for someone who is
    /// there to click, short enough that nobody notices when they are not.
    private static let keychainWait: TimeInterval = 6
    private static var cliStatus: (checked: Date, value: ClaudeCLI.Status?)?

    static func invalidateGate() {
        lastLiveAttempt.removeAll()
        lastLiveStatus.removeAll()
        cliStatus = nil
    }

    /// How far back a local reading still counts as proof that this Mac has a
    /// signed-in Claude. The desktop app keeps 30 days of samples and prunes
    /// past that, so anything still on disk is recent enough to trust.
    private static let signedInEvidenceMaxAge: TimeInterval = 30 * 24 * 3600

    /// Claude Code re-runs the status line every 60 s while a session is open,
    /// so anything older than a few cycles means no session is running and the
    /// numbers have stopped moving.
    private static let statusLineMaxAge: TimeInterval = 5 * 60

    func fetchAll() async -> [ProviderStatus] {
        // Who is signed in, straight from Claude Code's own config file. An
        // identity, not a credential — and the reason the card can name the
        // account and the plan even on a day when no source has a live number.
        let account = ClaudeAccount.current()
        let sample = ClaudeDesktopUsage.latest()
        let line = ClaudeStatusLine.latest()

        // 1. Claude Code's own status line — official, current, no credential.
        // A reading this fresh is proof of a signed-in session by itself, so
        // nothing else needs to be asked.
        if let line, Date().timeIntervalSince(line.date) <= Self.statusLineMaxAge,
           let status = statusLineStatus(line, account: account) {
            return [status]
        }

        // Is there a Claude on this Mac at all?
        //
        // `~/.claude.json` settles it outright when Claude Code has ever signed
        // in. Failing that, the evidence is a file one of the Claude apps wrote
        // itself — it exists only because a signed-in session created it.
        //
        // `claude auth status` is the last resort rather than the first: it
        // launches a 300 MB binary, and it only ever speaks for the command
        // line tool's own credential. Someone signed into the Claude desktop
        // app gets a "no" from it while being perfectly signed in, so a
        // negative answer there is a reason to keep looking, never a reason to
        // decide the user has no Claude and hide the card.
        let evidence = [sample?.date, line?.date].compactMap { $0 }.max()
        let seenSignedIn = account != nil || (evidence.map {
            Date().timeIntervalSince($0) < Self.signedInEvidenceMaxAge
        } ?? false)

        // Nothing local to go on — only now is the CLI worth a process spawn.
        let cli = seenSignedIn ? nil : await cachedCLIStatus()
        guard seenSignedIn || cli?.loggedIn == true else { return [] }

        // 2. Exact numbers, when a credential the user has explicitly allowed
        // this app to use exists. Off unless they turned it on themselves.
        if Prefs.claudeKeychainConsent {
            let org = sample?.org ?? account?.organizationUUID
            var live: [ProviderStatus] = []
            for service in ClaudeKeychain.allServiceNames() {
                switch await ClaudeKeychain.read(service: service,
                                                 waitingUpTo: Self.keychainWait) {
                case .denied:
                    Prefs.claudeKeychainConsent = false // let the user re-initiate
                case .absent:
                    continue
                case .found(let creds):
                    if let status = await liveStatus(creds: creds, org: org) {
                        live.append(status)
                    }
                }
            }
            for url in Accounts.claudeCredentialFiles() {
                guard let creds = ClaudeKeychain.readFile(at: url) else { continue }
                if let status = await liveStatus(creds: creds, org: org) {
                    live.append(status)
                }
            }
            if !live.isEmpty { return live }
        }

        // 3. Whatever either Claude app last left on disk, stamped with when.
        return [localStatus(sample: sample, line: line, account: account)]
    }

    /// The status line reports the whole account, so a single card is right —
    /// claude.ai, Claude Code and the desktop app share one limit.
    private func statusLineStatus(_ reading: ClaudeStatusLine.Reading,
                                  account: ClaudeAccount.Info?) -> ProviderStatus? {
        var windows: [LimitWindow] = []
        for window in reading.windows.sorted(by: { $0.field < $1.field }) {
            let label = Self.label(forField: window.field)
            windows.append(LimitWindow(
                id: "claude.\(window.field)", labelKey: label.key, labelArgument: label.argument,
                usedPercent: window.percent, resetsAt: window.resetsAt,
                windowMinutes: window.field == "five_hour" ? 300 : 10080,
                tokensUsed: nil,
                // Fresh by construction here, so no "read N ago" line is needed.
                readAt: nil))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { Self.sortKey($0) < Self.sortKey($1) }

        // The same account id as the stale card below, deliberately: the card
        // must keep its identity as readings come and go, or the popover would
        // tear itself down and rebuild every time a session ends.
        return ProviderStatus(
            providerID: id, accountID: "local",
            accountLabel: account?.email.map(Accounts.mask(email:)),
            groups: [LimitGroup(title: nil, windows: windows)],
            planType: reading.planType ?? account?.plan ?? ClaudeKeychain.cachedPlan,
            source: .live, lastUpdated: reading.date, state: .ok, noteKey: nil)
    }

    private func cachedCLIStatus() async -> ClaudeCLI.Status? {
        if let cached = Self.cliStatus,
           Date().timeIntervalSince(cached.checked) < Self.cliStatusTTL {
            return cached.value
        }
        let value = await ClaudeCLI.status()
        Self.cliStatus = (Date(), value)
        return value
    }

    // MARK: - 1. Live endpoint

    private func liveStatus(creds: ClaudeKeychain.Credentials, org: String?) async -> ProviderStatus? {
        let key = creds.sourceKey
        if let last = Self.lastLiveStatus[key],
           let attempt = Self.lastLiveAttempt[key],
           Date().timeIntervalSince(attempt) < Self.liveGateSeconds {
            return last
        }
        Self.lastLiveAttempt[key] = Date()

        // A stale expiresAt can coexist with a working token (Claude Code
        // refreshes on its own schedule), so always try the call once.
        let live = await fetchLive(creds: creds, org: org)
        Self.lastLiveStatus[key] = live
        return live
    }

    private func fetchLive(creds: ClaudeKeychain.Credentials, org: String?) async -> ProviderStatus? {
        // The organization endpoint is the richer one: it names each per-model
        // limit the way the Claude apps do ("Fable", "All models"). The OAuth
        // endpoint is the fallback and always carries the core windows.
        if let org, !org.isEmpty,
           let obj = await get("https://api.anthropic.com/api/organizations/\(org)/usage?skip_spend=1",
                               token: creds.accessToken),
           let status = organizationStatus(obj, creds: creds) {
            return status
        }
        guard let obj = await get("https://api.anthropic.com/api/oauth/usage",
                                  token: creds.accessToken)
        else { return nil }
        return oauthStatus(obj, creds: creds)
    }

    private func get(_ url: String, token: String) async -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Exact UA required — anything else earns persistent 429s.
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `limits: [{ kind, percent, resets_at, scope: { model: { display_name } } }]`
    private func organizationStatus(_ obj: [String: Any],
                                    creds: ClaudeKeychain.Credentials) -> ProviderStatus? {
        guard let limits = obj["limits"] as? [[String: Any]], !limits.isEmpty else { return nil }
        let prefix = "claude.\(creds.sourceKey)"
        var windows: [LimitWindow] = []

        for (index, limit) in limits.enumerated() {
            guard let percent = UsageJSON.double(limit["percent"]),
                  (0...100).contains(percent) else { continue }
            let kind = limit["kind"] as? String ?? "limit\(index)"
            let scope = limit["scope"] as? [String: Any]
            let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
            let surface = (scope?["surface"] as? [String: Any])?["display_name"] as? String

            var resets: Date?
            if let s = limit["resets_at"] as? String { resets = UsageJSON.parseISO(s) }
            else if let t = UsageJSON.double(limit["resets_at"]) {
                resets = Date(timeIntervalSince1970: t)
            }

            // A model name from the server beats anything hard-coded here —
            // it is how a limit the app has never heard of still reads right.
            // The session row is never per-model, whatever scope it carries.
            let named = kind == "session" ? nil : (model ?? surface)
            let label: ClaudeProvider.Label = named.map { ("window.weekModel", $0) }
                ?? Self.label(forKind: kind)
            windows.append(LimitWindow(
                id: "\(prefix).\(kind)\(named.map { ".\($0)" } ?? "")",
                labelKey: label.key, labelArgument: label.argument,
                usedPercent: percent, resetsAt: resets,
                windowMinutes: kind == "session" ? 300 : 10080,
                tokensUsed: nil, readAt: nil))
        }
        guard !windows.isEmpty else { return nil }
        return status(windows: windows, obj: obj, creds: creds)
    }

    /// `{ five_hour: { utilization, resets_at }, seven_day: {…}, … }` — read by
    /// key discovery, so a window Anthropic adds tomorrow appears on its own.
    private func oauthStatus(_ obj: [String: Any],
                             creds: ClaudeKeychain.Credentials) -> ProviderStatus? {
        let prefix = "claude.\(creds.sourceKey)"
        var windows: [LimitWindow] = []

        for (field, value) in obj {
            guard let w = value as? [String: Any],
                  let utilization = UsageJSON.double(w["utilization"]),
                  (0...100).contains(utilization) else { continue }
            var resets: Date?
            if let s = w["resets_at"] as? String { resets = UsageJSON.parseISO(s) }
            else if let t = UsageJSON.double(w["resets_at"]) {
                resets = Date(timeIntervalSince1970: t)
            }
            let label = Self.label(forField: field)
            windows.append(LimitWindow(
                id: "\(prefix).\(field)", labelKey: label.key, labelArgument: label.argument,
                usedPercent: utilization, resetsAt: resets,
                windowMinutes: field == "five_hour" ? 300 : 10080,
                tokensUsed: nil, readAt: nil))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { Self.sortKey($0) < Self.sortKey($1) }
        return status(windows: windows, obj: obj, creds: creds)
    }

    private func status(windows: [LimitWindow], obj: [String: Any],
                        creds: ClaudeKeychain.Credentials) -> ProviderStatus {
        let email = Accounts.findEmail(in: obj) ?? creds.email
        return ProviderStatus(providerID: id, accountID: creds.sourceKey,
                              accountLabel: email.map(Accounts.mask(email:)),
                              groups: [LimitGroup(title: nil, windows: windows)],
                              planType: creds.subscriptionType ?? ClaudeKeychain.cachedPlan,
                              source: .live, lastUpdated: Date(), state: .ok, noteKey: nil)
    }

    // MARK: - 3. The last reading either Claude app left on disk

    /// The card when no source is current.
    ///
    /// It still names the account and the plan, because those are known and a
    /// card that vanishes reads as a broken app. What it will not do is repeat
    /// an old percentage as if it were now: every row carries the moment it was
    /// read, and anything past `freshMaxAge` counts as history — shown here
    /// with its age, never drawn as a bar in the menu bar.
    private func localStatus(sample: ClaudeDesktopUsage.Sample?,
                             line: ClaudeStatusLine.Reading?,
                             account: ClaudeAccount.Info?) -> ProviderStatus {
        let plan = account?.plan ?? ClaudeKeychain.cachedPlan
        let label = account?.email.map(Accounts.mask(email:))

        typealias Row = (field: String, percent: Double, resets: Date?)
        let readings: [(date: Date, rows: [Row])] = [
            sample.map { ($0.date, $0.windows.map { Row($0.field, $0.percent, nil) }) },
            line.map { ($0.date, $0.windows.map { Row($0.field, $0.percent, $0.resetsAt) }) },
        ].compactMap { $0 }

        // Whichever of the two spoke last wins; mixing them would put two
        // different moments in one card without saying so.
        guard let reading = readings.max(by: { $0.date < $1.date }), !reading.rows.isEmpty else {
            return ProviderStatus(
                providerID: id, accountID: "local", accountLabel: label, groups: [],
                planType: plan, source: .localSnapshot, lastUpdated: Date(),
                state: .ok, noteKey: "claude.noReading")
        }

        var windows: [LimitWindow] = []
        for row in reading.rows {
            let caption = Self.label(forField: row.field)
            // The desktop app's file carries no reset time. A 5 h block can be
            // anchored from the local transcripts; a weekly one only after the
            // app has watched a rollover happen.
            let resets = row.resets
                ?? (row.field == "five_hour" ? ClaudeLocalUsage.activeBlock()?.blockEndsAt : nil)
                ?? UsageHistory.predictedReset(for: "claude.\(row.field)")
            windows.append(LimitWindow(
                id: "claude.\(row.field)", labelKey: caption.key,
                labelArgument: caption.argument, usedPercent: row.percent,
                resetsAt: resets,
                windowMinutes: ClaudeDesktopUsage.windowMinutes(forField: row.field),
                tokensUsed: nil, readAt: reading.date))
        }
        windows.sort { Self.sortKey($0) < Self.sortKey($1) }

        let stale = Date().timeIntervalSince(reading.date) > ClaudeDesktopUsage.freshMaxAge
        return ProviderStatus(
            providerID: id, accountID: "local", accountLabel: label,
            groups: [LimitGroup(title: nil, windows: windows)],
            planType: plan, source: .localSnapshot, lastUpdated: reading.date,
            state: .ok, noteKey: stale ? "claude.noReadingHint" : nil)
    }

    // MARK: - Labels

    /// A row's caption as (localization key, optional model name). The name is
    /// kept out of the key so switching language re-translates "Week (%@)"
    /// without needing another fetch.
    typealias Label = (key: String, argument: String?)

    /// Known windows get a translated caption; anything else is derived from
    /// the field name, so a limit Anthropic adds later reads sensibly instead
    /// of showing a raw key.
    static func label(forField field: String) -> Label {
        switch field {
        case "five_hour": return ("window.5h", nil)
        case "seven_day": return ("window.weekAll", nil)
        case "extra_usage": return ("window.extra", nil)
        default:
            guard field.hasPrefix("seven_day_") else { return (prettify(field), nil) }
            return ("window.weekModel", prettify(String(field.dropFirst("seven_day_".count))))
        }
    }

    private static func label(forKind kind: String) -> Label {
        switch kind {
        case "session", "five_hour": return ("window.5h", nil)
        case "weekly_all", "seven_day": return ("window.weekAll", nil)
        default: return (prettify(kind), nil)
        }
    }

    private static func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Session first, then the general weekly, then the per-model rows.
    private static func sortKey(_ window: LimitWindow) -> String {
        switch window.labelKey {
        case "window.5h": return "0"
        case "window.weekAll": return "1"
        case "window.extra": return "9"
        default: return "5\(window.labelArgument ?? window.labelKey)"
        }
    }
}
