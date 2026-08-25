import AppKit
import UserNotifications

/// Posts a notification (plus one short system sound) when a limit that had
/// been nearly exhausted rolls over. Opt-in from Settings.
enum Notifier {
    /// Only announce rollovers of windows that were actually spent — the same
    /// threshold that turns the menu bar badge yellow.
    static let exhaustedThreshold: Double = StatusIcons.warningPercent

    /// UNUserNotificationCenter traps when the process has no app bundle
    /// (`swift run`), so every entry point checks this first.
    private static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var authorized = false

    static func requestAuthorizationIfNeeded() {
        guard isBundled, Prefs.notifyOnReset, !authorized else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            authorized = granted
        }
    }

    static func announce(_ events: [UsageHistory.ResetEvent], providerNames: [String: String]) {
        let worth = events.filter { $0.percentBefore >= exhaustedThreshold }
        guard Prefs.notifyOnReset, !worth.isEmpty else { return }

        for event in worth {
            let provider = providerNames[event.providerID] ?? event.providerID
            let scope = event.groupTitle.map { "\(provider) · \($0)" } ?? provider
            let title = String(format: L10n.t("notify.resetTitle"), scope)
            let body = String(format: L10n.t("notify.resetBody"),
                              L10n.t(event.labelKey), Int(event.percentBefore.rounded()))
            // Stable id per window: a repeat for the same rollover coalesces
            // instead of stacking another banner in Notification Center.
            post(title: title, body: body, id: "reset.\(event.windowID)")
        }
        // One sound for the batch, never one per window.
        NSSound(named: "Glass")?.play()
    }

    private static func post(title: String, body: String, id: String) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
