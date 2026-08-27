import Foundation

/// Single source of truth for every UserDefaults key the app uses.
enum Prefs {
    private static let d = UserDefaults.standard

    private enum Key {
        static let appLanguage = "appLanguage"
        static let launchAtLogin = "launchAtLogin"
        static let autoUpdate = "autoUpdate"
        static let updateAttempts = "updateAttempts"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let claudeKeychainConsent = "claudeKeychainConsent"
        static let claudeStatusLine = "claudeStatusLine"
        static let cachedStatusJSON = "cachedStatusJSON"
        static let notifyOnReset = "notifyOnReset"
        static let claudePlanCache = "claudePlanCache"
        static let menuBarBars = "menuBarBars"
    }

    static func registerDefaults() {
        d.register(defaults: [
            Key.launchAtLogin: true,
            Key.autoUpdate: true,
            Key.refreshIntervalMinutes: 15,
            Key.claudeKeychainConsent: true,
            Key.claudeStatusLine: true,
            Key.notifyOnReset: false,
            Key.menuBarBars: true,
        ])
    }

    /// "en" | "pt-BR"; nil means first launch hasn't completed yet.
    static var appLanguage: String? {
        get { d.string(forKey: Key.appLanguage) }
        set { d.set(newValue, forKey: Key.appLanguage) }
    }

    static var launchAtLogin: Bool {
        get { d.bool(forKey: Key.launchAtLogin) }
        set { d.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// How many times each version was attempted. An update that keeps
    /// failing is abandoned instead of relaunching the app forever.
    static func updateAttempts(for version: String) -> Int {
        (d.dictionary(forKey: Key.updateAttempts)?[version] as? Int) ?? 0
    }

    static func noteUpdateAttempt(_ version: String) {
        var all = d.dictionary(forKey: Key.updateAttempts) as? [String: Int] ?? [:]
        all[version] = (all[version] ?? 0) + 1
        // Keep only what matters: the version being installed right now.
        d.set([version: all[version]!], forKey: Key.updateAttempts)
    }

    /// Keep the app current automatically. On by default — a menu bar utility
    /// nobody thinks about should not quietly rot.
    static var autoUpdate: Bool {
        get { d.bool(forKey: Key.autoUpdate) }
        set { d.set(newValue, forKey: Key.autoUpdate) }
    }

    static var refreshIntervalMinutes: Int {
        get { d.integer(forKey: Key.refreshIntervalMinutes) }
        set { d.set(newValue, forKey: Key.refreshIntervalMinutes) }
    }

    /// Whether the app may ask macOS for the Claude Code credential.
    ///
    /// On by default because macOS itself is the consent gate: the first read
    /// raises the system's own Keychain prompt, the user answers it, and that
    /// answer sticks. Denying flips this off so the app stops asking. The token
    /// is used for Anthropic's usage endpoint and nothing else — never stored,
    /// never sent anywhere else, never refreshed.
    static var claudeKeychainConsent: Bool {
        get { d.bool(forKey: Key.claudeKeychainConsent) }
        set { d.set(newValue, forKey: Key.claudeKeychainConsent) }
    }

    /// Last good ProviderStatus array (percentages/dates only — never tokens),
    /// so the popover renders instantly on launch.
    static var cachedStatusJSON: Data? {
        get { d.data(forKey: Key.cachedStatusJSON) }
        set { d.set(newValue, forKey: Key.cachedStatusJSON) }
    }

    /// Announce (with a short sound) when a spent limit rolls over.
    static var notifyOnReset: Bool {
        get { d.bool(forKey: Key.notifyOnReset) }
        set { d.set(newValue, forKey: Key.notifyOnReset) }
    }

    /// Let Claude Code report its own usage through its `statusLine` hook.
    ///
    /// This is the only way to get exact, current plan percentages without
    /// touching a credential, so it is on by default — the welcome screen says
    /// so, and turning it off puts `~/.claude/settings.json` back as it was.
    static var claudeStatusLine: Bool {
        get { d.bool(forKey: Key.claudeStatusLine) }
        set { d.set(newValue, forKey: Key.claudeStatusLine) }
    }

    /// Draw the usage bars in the menu bar instead of the plain token.
    ///
    /// On by default: the whole point of a menu bar app is answering the
    /// question without being opened. Off restores the single square glyph for
    /// anyone whose menu bar is already full.
    static var menuBarBars: Bool {
        get { d.bool(forKey: Key.menuBarBars) }
        set { d.set(newValue, forKey: Key.menuBarBars) }
    }

    /// Last known Claude subscription name, so the plan chip survives refreshes
    /// that never touch the Keychain.
    static var claudePlanCache: String? {
        get { d.string(forKey: Key.claudePlanCache) }
        set { d.set(newValue, forKey: Key.claudePlanCache) }
    }
}
