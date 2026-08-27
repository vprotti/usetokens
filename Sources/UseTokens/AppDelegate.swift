import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var welcomeController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        if Prefs.appLanguage == nil {
            // First launch: pick a language, then default-enable launch at login.
            welcomeController = WelcomeWindowController { [weak self] in
                LoginItem.set(enabled: true)
                self?.start()
                self?.welcomeController = nil
            }
            welcomeController?.show()
        } else {
            start()
        }
    }

    private func start() {
        // Launch at login is the default; re-assert it if the registration was
        // lost (first run from the DMG, an update, a moved bundle).
        if Prefs.launchAtLogin && !LoginItem.isEnabled {
            LoginItem.set(enabled: true)
        }
        Notifier.requestAuthorizationIfNeeded()
        syncClaudeStatusLine()

        let store = UsageStore(providers: [CodexProvider(), ClaudeProvider()])
        let status = StatusItemController(store: store)
        let settings = SettingsWindowController(store: store)

        status.onOpenSettings = { [weak settings] in settings?.show() }

        self.store = store
        self.statusController = status
        self.settingsController = settings

        // A second launch — a double click while it is already running, or a
        // login item that fired twice — should surface the copy that is here
        // rather than look like nothing happened.
        SingleInstance.onSecondLaunch { [weak settings] in
            NSApp.activate(ignoringOtherApps: true)
            settings?.show()
        }

        store.refresh()

        // Don't restart the app while the user is reading the popover.
        Updater.shouldPostpone = { [weak status] in status?.isPopoverVisible ?? false }
        Updater.start()
    }

    /// Keeps `~/.claude/settings.json` matching the preference. Re-running
    /// install on every launch is deliberate: it repoints the bridge script at
    /// the app's current path after an update or a move to /Applications.
    static func syncClaudeStatusLine() {
        if Prefs.claudeStatusLine {
            ClaudeStatusLine.install()
        } else if ClaudeStatusLine.isInstalled() {
            ClaudeStatusLine.uninstall()
        }
    }

    private func syncClaudeStatusLine() { Self.syncClaudeStatusLine() }
}
