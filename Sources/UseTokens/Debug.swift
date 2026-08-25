import AppKit

/// Diagnostics used while developing the providers. Prints endpoint payloads
/// with every secret-looking value redacted — tokens must never reach stdout.
enum Debug {
    private static let secretKeys: Set<String> = [
        "access_token", "refresh_token", "id_token", "accessToken", "refreshToken",
        "idToken", "account_id", "accountId", "client_secret", "authorization",
    ]

    static func redact(_ value: Any, key: String = "") -> Any {
        if secretKeys.contains(key) { return "<redacted>" }
        if let dict = value as? [String: Any] {
            return dict.mapValues { $0 }.reduce(into: [String: Any]()) { acc, pair in
                acc[pair.key] = redact(pair.value, key: pair.key)
            }
        }
        if let arr = value as? [Any] { return arr.map { redact($0) } }
        if let s = value as? String, s.count > 60 { return "<long:\(s.count)>" }
        return value
    }

    static func dump(_ label: String, _ obj: Any) {
        let redacted = redact(obj)
        if JSONSerialization.isValidJSONObject(redacted),
           let data = try? JSONSerialization.data(withJSONObject: redacted,
                                                  options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("--- \(label) ---")
            print(text)
        } else {
            print("--- \(label) --- \(redacted)")
        }
    }

    // MARK: - Codex

    static func codex() async {
        let url = CodexRollouts.defaultBase.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String
        else { print("codex: no auth.json"); return }
        let account = tokens["account_id"] as? String

        for path in ["https://chatgpt.com/backend-api/wham/usage",
                     "https://chatgpt.com/backend-api/wham/usage?include_all=true",
                     "https://chatgpt.com/backend-api/codex/usage"] {
            var request = URLRequest(url: URL(string: path)!)
            request.timeoutInterval = 15
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            guard let (body, response) = try? await URLSession.shared.data(for: request) else {
                print("codex \(path): request failed"); continue
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("codex \(path) -> HTTP \(code)")
            if let json = try? JSONSerialization.jsonObject(with: body) {
                dump("codex payload", json)
            } else {
                print(String(data: body.prefix(400), encoding: .utf8) ?? "<binary>")
            }
        }
    }

    // MARK: - Claude

    static func claude() async {
        print("keychain service: \(ClaudeKeychain.findServiceName() ?? "<none>")")
        guard case .found(let creds) = ClaudeKeychain.read() else {
            print("claude: no credentials readable"); return
        }
        let expiry = creds.expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        let expired = (creds.expiresAt.map { $0 < Date() }) ?? false
        print("expiresAt: \(expiry) (expired: \(expired)) · plan: \(creds.subscriptionType ?? "nil")")
        print("token length: \(creds.accessToken.count), prefix: \(creds.accessToken.prefix(8))…")

        let attempts: [(String, [String: String])] = [
            ("https://api.anthropic.com/api/oauth/usage",
             ["anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-code/2.1.0"]),
            ("https://api.anthropic.com/api/oauth/usage",
             ["anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-cli/2.1.0 (external, cli)",
              "anthropic-version": "2023-06-01"]),
            ("https://api.anthropic.com/api/oauth/profile",
             ["anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-code/2.1.0"]),
        ]

        for (path, headers) in attempts {
            var request = URLRequest(url: URL(string: path)!)
            request.timeoutInterval = 15
            request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            guard let (body, response) = try? await URLSession.shared.data(for: request) else {
                print("claude \(path): request failed"); continue
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("claude \(path) [\(headers["User-Agent"] ?? "")] -> HTTP \(code)")
            if let json = try? JSONSerialization.jsonObject(with: body) {
                dump("claude payload", json)
            } else {
                print(String(data: body.prefix(400), encoding: .utf8) ?? "<binary>")
            }
        }
    }

    static func run(_ which: String) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if which == "codex" || which == "all" { await codex() }
            if which == "claude" || which == "all" { await claude() }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
