import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Registration fails when the
/// app runs translocated (e.g. straight from the mounted DMG) or outside a
/// bundle (`swift run`) — callers degrade gracefully and show a hint.
enum LoginItem {
    /// System truth — the user can flip this in System Settings behind our back.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Prefs.launchAtLogin = enabled
            return true
        } catch {
            NSLog("LoginItem: %@ failed: %@", enabled ? "register" : "unregister",
                  error.localizedDescription)
            return false
        }
    }
}
