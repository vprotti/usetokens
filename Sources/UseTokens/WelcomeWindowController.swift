import AppKit

/// First-launch language picker. Pre-selects the system language and hands
/// control back to the AppDelegate when the user continues.
final class WelcomeWindowController: NSObject {
    private var window: NSWindow?
    private var ptRadio: NSButton!
    private var enRadio: NSButton!
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func show() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 340),
            styleMask: [.titled],
            backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true

        let detected = L10n.detectSystemLanguage()

        let token = NSImageView()
        token.image = NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
            StatusIcons.drawToken(in: rect, filled: true, color: StatusIcons.teal)
            return true
        }
        token.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: welcomeBilingual("welcome.title", detected))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.alignment = .center

        let hint = NSTextField(wrappingLabelWithString: welcomeBilingual("welcome.hint", detected))
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.preferredMaxLayoutWidth = 250

        let subtitle = NSTextField(labelWithString: welcomeBilingual("welcome.subtitle", detected))
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        ptRadio = NSButton(radioButtonWithTitle: "Português (Brasil)",
                           target: self, action: #selector(radioChanged))
        enRadio = NSButton(radioButtonWithTitle: "English",
                           target: self, action: #selector(radioChanged))
        (detected == .ptBR ? ptRadio : enRadio)?.state = .on

        let continueButton = NSButton(title: welcomeBilingual("welcome.continue", detected),
                                      target: self, action: #selector(continuePressed))
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"

        let radios = NSStackView(views: [ptRadio, enRadio])
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 10

        let stack = NSStackView(views: [token, title, hint, subtitle, radios, continueButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(8, after: title)
        stack.setCustomSpacing(26, after: hint)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(24, after: radios)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 28, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            token.widthAnchor.constraint(equalToConstant: 72),
            token.heightAnchor.constraint(equalToConstant: 72),
        ])

        win.contentView = stack
        win.setContentSize(stack.fittingSize)
        win.center()
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    /// Before a language is chosen, label the window in the detected language.
    private func welcomeBilingual(_ key: String, _ lang: Language) -> String {
        let saved = Prefs.appLanguage
        Prefs.appLanguage = lang.rawValue
        let text = L10n.t(key)
        Prefs.appLanguage = saved
        return text
    }

    @objc private func radioChanged() {
        // Radio group handled by AppKit; nothing else to do until Continue.
    }

    @objc private func continuePressed() {
        L10n.current = ptRadio.state == .on ? .ptBR : .en
        window?.orderOut(nil)
        window = nil
        onComplete()
    }
}
