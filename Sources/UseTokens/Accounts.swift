import Foundation

/// Finding every signed-in account on whatever Mac the app happens to run on.
///
/// Nothing here is tailored to one machine: the app looks in the places these
/// tools are documented to use, takes whatever is there, and shows a card per
/// account it can actually read.
enum Accounts {

    /// A credential the app can read, plus how to label it in the UI.
    struct Source {
        /// Stable identity for history keys and card ordering.
        let id: String
        /// Where it came from, for the fallback label ("Codex", "Claude").
        let origin: String
    }

    // MARK: - Labels

    /// `alexandre@exemplo.com` → `a********@exemplo.com`.
    /// Enough to tell two accounts apart, without putting a full address on
    /// screen for anyone glancing at the menu bar.
    static func mask(email: String) -> String {
        guard let at = email.firstIndex(of: "@"), at > email.startIndex else { return email }
        let local = email[email.startIndex..<at]
        let domain = email[at...]
        let stars = String(repeating: "*", count: min(max(local.count - 1, 1), 8))
        return "\(local.first!)\(stars)\(domain)"
    }

    /// Reads the e-mail claim out of a JWT locally — no signature check and no
    /// network; the token already carries the label we want to show.
    static func emailFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        for key in ["email", "preferred_username", "sub_email"] {
            if let value = claims[key] as? String, value.contains("@") { return value }
        }
        // Some tokens nest the profile one level down.
        for value in claims.values {
            if let nested = value as? [String: Any],
               let email = nested["email"] as? String, email.contains("@") {
                return email
            }
        }
        return nil
    }

    /// Digs an e-mail out of an arbitrary decoded JSON blob, wherever the
    /// provider decided to put it this month.
    static func findEmail(in object: Any, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        if let dict = object as? [String: Any] {
            for key in ["email", "email_address", "account_email", "userEmail"] {
                if let value = dict[key] as? String, value.contains("@") { return value }
            }
            for value in dict.values {
                if let found = findEmail(in: value, depth: depth + 1) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findEmail(in: value, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    // MARK: - Codex credential files

    /// Every `auth.json` a Codex install might have written. Multi-account
    /// setups use either a second CODEX_HOME or a suffixed file next to the
    /// first one, so both shapes are covered.
    static func codexAuthFiles() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var roots: [URL] = []

        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            roots.append(URL(fileURLWithPath: custom))
        }
        roots.append(home.appendingPathComponent(".codex"))
        roots.append(home.appendingPathComponent(".config/codex"))

        var files: [URL] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for entry in entries.sorted()
            where entry.hasPrefix("auth") && entry.hasSuffix(".json") {
                files.append(root.appendingPathComponent(entry))
            }
            // A per-account folder, if this install uses one.
            let accounts = root.appendingPathComponent("accounts")
            if let nested = try? fm.contentsOfDirectory(atPath: accounts.path) {
                for entry in nested.sorted() where entry.hasSuffix(".json") {
                    files.append(accounts.appendingPathComponent(entry))
                }
            }
        }

        // Same file reachable by two paths counts once.
        var seen = Set<String>()
        return files.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    // MARK: - Claude credential files

    /// The file-based Claude Code store, used when the Keychain is not.
    static func claudeCredentialFiles() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/.credentials.json"),
            home.appendingPathComponent(".config/claude/.credentials.json"),
        ]
        return candidates.filter { fm.fileExists(atPath: $0.path) }
    }
}
