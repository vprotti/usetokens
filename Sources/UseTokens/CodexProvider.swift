import AppKit

/// ChatGPT/Codex usage, one card per signed-in account.
///
/// Accounts are discovered from whatever credential files exist on the machine
/// (see Accounts.codexAuthFiles) — a second CODEX_HOME or a suffixed auth file
/// both show up on their own. Credentials are re-read on every refresh, so
/// signing in or out is picked up without restarting the app.
///
/// An expired credential is never refreshed here: OpenAI rotates the refresh
/// token and the Codex CLI owns auth.json, so spending it would log the user
/// out of their own CLI. Opening the ChatGPT app refreshes the file for us.
final class CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "ChatGPT · Codex"
    var glyph: NSImage { ProviderGlyphs.codex }

    private struct Auth {
        let accessToken: String
        let accountId: String?
        /// Label taken from the id_token the file already carries.
        let email: String?
        /// Distinguishes accounts; falls back to the file path.
        let key: String
    }

    func fetchAll() async -> [ProviderStatus] {
        let accounts = Self.loadAuths()

        guard !accounts.isEmpty else {
            // No credential at all: a rollout snapshot may still carry the last
            // known numbers from before the user signed out.
            if var snapshot = CodexRollouts.latestSnapshot() {
                snapshot.accountID = "rollout"
                return [snapshot]
            }
            return [.empty(id, state: .notConnected, noteKey: "state.notConnected.codex")]
        }

        var results: [ProviderStatus] = []
        for auth in accounts {
            if let live = await fetchLive(auth: auth) {
                results.append(live)
                continue
            }
            // Credentials exist but the call failed. With a single account the
            // rollout snapshot is a useful fallback; with several there is no
            // way to tell whose snapshot it is, so say nothing instead.
            let label = auth.email.map(Accounts.mask(email:))
            if accounts.count == 1, var snapshot = CodexRollouts.latestSnapshot() {
                snapshot.accountID = auth.key
                snapshot.accountLabel = label
                snapshot.noteKey = "state.expiredToken.codex"
                results.append(snapshot)
            } else {
                results.append(.empty(id, state: .notConnected,
                                      noteKey: "state.expiredToken.codex",
                                      accountID: auth.key, accountLabel: label))
            }
        }
        return results
    }

    // MARK: - Credential files

    private static func loadAuths() -> [Auth] {
        Accounts.codexAuthFiles().compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = obj["tokens"] as? [String: Any],
                  let access = tokens["access_token"] as? String, !access.isEmpty
            else { return nil }

            let email = (tokens["id_token"] as? String).flatMap(Accounts.emailFromJWT)
                ?? Accounts.findEmail(in: obj)
            let account = tokens["account_id"] as? String
            return Auth(accessToken: access, accountId: account, email: email,
                        key: account ?? url.standardizedFileURL.path)
        }
    }

    // MARK: - Live endpoint

    private func fetchLive(auth: Auth) async -> ProviderStatus? {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UseTokens/1.0", forHTTPHeaderField: "User-Agent")
        if let account = auth.accountId {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let prefix = "codex.\(auth.key)"
        var groups: [LimitGroup] = []

        // The plan's general limits.
        if let general = obj["rate_limit"] as? [String: Any] {
            let windows = Self.windows(from: general, idPrefix: "\(prefix).general")
            if !windows.isEmpty { groups.append(LimitGroup(title: nil, windows: windows)) }
        }

        // Per-model groups, e.g. "GPT-5.3-Codex-Spark".
        if let extras = obj["additional_rate_limits"] as? [[String: Any]] {
            for extra in extras {
                let name = (extra["limit_name"] as? String)
                    ?? (extra["metered_feature"] as? String)
                    ?? "—"
                guard let rl = extra["rate_limit"] as? [String: Any] else { continue }
                let windows = Self.windows(from: rl, idPrefix: "\(prefix).\(name)")
                if !windows.isEmpty { groups.append(LimitGroup(title: name, windows: windows)) }
            }
        }
        guard !groups.isEmpty else { return nil }

        // The endpoint knows the account too — prefer it over the token claim.
        let email = (obj["email"] as? String) ?? auth.email

        return ProviderStatus(providerID: id, accountID: auth.key,
                              accountLabel: email.map(Accounts.mask(email:)),
                              groups: groups, planType: obj["plan_type"] as? String,
                              source: .live, lastUpdated: Date(), state: .ok, noteKey: nil)
    }

    /// Both window slots of one rate_limit object, in display order.
    static func windows(from rateLimit: [String: Any], idPrefix: String) -> [LimitWindow] {
        var result: [LimitWindow] = []
        for key in ["primary_window", "secondary_window", "primary", "secondary"] {
            guard let dict = rateLimit[key] as? [String: Any],
                  let window = UsageJSON.window(from: dict, eventDate: Date(),
                                                idPrefix: idPrefix)
            else { continue }
            result.append(window)
        }
        // Shortest window first (5 h before weekly) — matches the ChatGPT UI.
        return result.sorted { ($0.windowMinutes ?? 0) < ($1.windowMinutes ?? 0) }
    }
}
