import Foundation
import Security

/// Reads the Claude Code OAuth credential from the login keychain.
/// The service name carries a per-install random suffix
/// (e.g. "Claude Code-credentials-33b91349"), so we match by prefix.
/// Phase A (attributes only) never prompts; phase B (secret) prompts once.
enum ClaudeKeychain {
    static let servicePrefix = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
        /// Account label, when the stored blob carries one.
        let email: String?
        /// Which store this came from — one card per credential.
        let sourceKey: String
    }

    enum ReadResult {
        case found(Credentials)
        case denied
        case absent
    }

    /// Same shape, read from the file-based store some installs use instead.
    static func readFile(at url: URL) -> Credentials? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any] ?? obj as [String: Any]?,
              let access = oauth["accessToken"] as? String, !access.isEmpty
        else { return nil }
        var expires: Date?
        if let ms = UsageJSON.double(oauth["expiresAt"]) {
            expires = Date(timeIntervalSince1970: ms / 1000)
        }
        return Credentials(accessToken: access, expiresAt: expires,
                           subscriptionType: oauth["subscriptionType"] as? String,
                           email: Accounts.findEmail(in: obj),
                           sourceKey: url.standardizedFileURL.path)
    }

    /// Plan name from the last successful read — lets the plan chip show even
    /// when this refresh used a source that carries no subscription info.
    static var cachedPlan: String? { Prefs.claudePlanCache }

    /// Every Claude Code credential on this Mac, newest first — a user who has
    /// signed in with more than one account has more than one item here.
    /// Attributes only: this never prompts and never reads a secret.
    static func allServiceNames() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }

        return items.compactMap { item -> (service: String, mdat: Date)? in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(servicePrefix) else { return nil }
            return (service, item[kSecAttrModificationDate as String] as? Date ?? .distantPast)
        }
        .sorted { $0.mdat > $1.mdat }
        .map { $0.service }
    }

    /// Phase A: enumerate generic-password attributes (no secret, no prompt).
    static func findServiceName() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return nil }

        let matches = items.compactMap { item -> (service: String, mdat: Date)? in
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(servicePrefix) else { return nil }
            let mdat = item[kSecAttrModificationDate as String] as? Date ?? .distantPast
            return (service, mdat)
        }
        return matches.max { $0.mdat < $1.mdat }?.service
    }

    /// Phase B: read the secret for the discovered service (one-time prompt).
    /// The token is used to call Anthropic's own usage endpoint and nothing
    /// else — it is never refreshed (rotating it would revoke Claude Code's
    /// own session), never written back, and never persisted by this app.
    /// The same read, with a bound on how long the caller waits for it.
    ///
    /// Asking for an item another app owns puts a dialog on screen, and
    /// `SecItemCopyMatching` does not return until somebody answers it. On an
    /// automatic refresh nobody may be at the keyboard, and waiting means the
    /// refresh never finishes at all: no card, no menu bar, no explanation for
    /// any of it — which is exactly how it behaved.
    ///
    /// So the wait is bounded and the cycle carries on with the local reading.
    /// The blocked call is left alone: it is holding a dialog the user may
    /// still answer, and whatever they choose is picked up next time round.
    static func read(service: String, waitingUpTo timeout: TimeInterval) async -> ReadResult {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            DispatchQueue.global(qos: .utility).async {
                once.finish(read(service: service))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                // Not "no credential" — "no answer yet". Same outcome for this
                // refresh, and the next one asks again.
                once.finish(.absent)
            }
        }
    }

    /// Resumes exactly once, whichever of the two racers arrives first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ReadResult, Never>?

        init(_ continuation: CheckedContinuation<ReadResult, Never>) {
            self.continuation = continuation
        }

        func finish(_ result: ReadResult) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: result)
        }
    }

    static func read(service explicitService: String? = nil) -> ReadResult {
        guard let service = explicitService ?? findServiceName() else { return .absent }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String, !access.isEmpty
            else { return .absent }
            var expires: Date?
            if let ms = UsageJSON.double(oauth["expiresAt"]) {
                expires = Date(timeIntervalSince1970: ms / 1000)
            }
            let plan = oauth["subscriptionType"] as? String
            if let plan { Prefs.claudePlanCache = plan }
            return .found(Credentials(
                accessToken: access,
                expiresAt: expires,
                subscriptionType: plan,
                email: Accounts.findEmail(in: obj),
                sourceKey: service))
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .denied
        default:
            return .absent
        }
    }
}
