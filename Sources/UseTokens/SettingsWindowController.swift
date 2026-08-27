import AppKit

/// Minimal programmatic settings window. Every change applies immediately
/// (macOS convention — no OK/Cancel).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: UsageStore

    private var loginSwitch: NSSwitch!
    private var loginLabel: NSTextField!
    private var loginHint: NSTextField!
    private var loginHintRow: NSGridRow?
    private var refreshLabel: NSTextField!
    private var refreshPopup: NSPopUpButton!
    private var claudeLabel: NSTextField!
    private var claudeSwitch: NSSwitch!
    private var claudeHint: NSTextField!
    private var lineLabel: NSTextField!
    private var lineSwitch: NSSwitch!
    private var lineHint: NSTextField!
    private var privacyTitle: NSTextField!
    private var privacyBody: NSTextField!
    private var barsLabel: NSTextField!
    private var barsSwitch: NSSwitch!
    private var barsHint: NSTextField!
    private var notifyLabel: NSTextField!
    private var notifySwitch: NSSwitch!
    private var notifyHint: NSTextField!
    private var updateLabel: NSTextField!
    private var updateSwitch: NSSwitch!
    private var updateHint: NSTextField!
    private var languageLabel: NSTextField!
    private var languagePopup: NSPopUpButton!

    private let refreshChoices = [5, 15, 30, 60]

    init(store: UsageStore) {
        self.store = store
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(relabel),
            name: .languageDidChange, object: nil)
    }

    func show() {
        if window == nil { buildWindow() }
        syncFromState()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Layout

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.delegate = self

        loginLabel = Self.label()
        loginSwitch = NSSwitch()
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged)

        loginHint = NSTextField(wrappingLabelWithString: "")
        loginHint.textColor = .secondaryLabelColor
        loginHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginHint.preferredMaxLayoutWidth = 300

        refreshLabel = Self.label()
        refreshPopup = NSPopUpButton()
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshIntervalChanged)

        claudeLabel = Self.label()
        claudeSwitch = NSSwitch()
        claudeSwitch.target = self
        claudeSwitch.action = #selector(claudeCredentialChanged)

        claudeHint = NSTextField(wrappingLabelWithString: "")
        claudeHint.textColor = .secondaryLabelColor
        claudeHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        claudeHint.preferredMaxLayoutWidth = 300

        lineLabel = Self.label()
        lineSwitch = NSSwitch()
        lineSwitch.target = self
        lineSwitch.action = #selector(claudeStatusLineChanged)

        lineHint = NSTextField(wrappingLabelWithString: "")
        lineHint.textColor = .secondaryLabelColor
        lineHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        lineHint.preferredMaxLayoutWidth = 300

        privacyTitle = Self.label()
        privacyTitle.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        privacyBody = NSTextField(wrappingLabelWithString: "")
        privacyBody.textColor = .secondaryLabelColor
        privacyBody.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        privacyBody.preferredMaxLayoutWidth = 300

        barsLabel = Self.label()
        barsSwitch = NSSwitch()
        barsSwitch.target = self
        barsSwitch.action = #selector(barsChanged)

        barsHint = NSTextField(wrappingLabelWithString: "")
        barsHint.textColor = .secondaryLabelColor
        barsHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        barsHint.preferredMaxLayoutWidth = 300

        notifyLabel = Self.label()
        notifySwitch = NSSwitch()
        notifySwitch.target = self
        notifySwitch.action = #selector(notifyChanged)

        notifyHint = NSTextField(wrappingLabelWithString: "")
        notifyHint.textColor = .secondaryLabelColor
        notifyHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notifyHint.preferredMaxLayoutWidth = 300

        updateLabel = Self.label()
        updateSwitch = NSSwitch()
        updateSwitch.target = self
        updateSwitch.action = #selector(autoUpdateChanged)

        updateHint = NSTextField(wrappingLabelWithString: "")
        updateHint.textColor = .secondaryLabelColor
        updateHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        updateHint.preferredMaxLayoutWidth = 300

        languageLabel = Self.label()
        languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: ["Português (Brasil)", "English"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)

        let grid = NSGridView(views: [
            [loginLabel, loginSwitch],
            [loginHint, NSGridCell.emptyContentView],
            [refreshLabel, refreshPopup],
            [lineLabel, lineSwitch],
            [lineHint, NSGridCell.emptyContentView],
            [claudeLabel, claudeSwitch],
            [claudeHint, NSGridCell.emptyContentView],
            [barsLabel, barsSwitch],
            [barsHint, NSGridCell.emptyContentView],
            [notifyLabel, notifySwitch],
            [notifyHint, NSGridCell.emptyContentView],
            [updateLabel, updateSwitch],
            [updateHint, NSGridCell.emptyContentView],
            [languageLabel, languagePopup],
            [privacyTitle, NSGridCell.emptyContentView],
            [privacyBody, NSGridCell.emptyContentView],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline
        grid.cell(for: loginHint)?.row?.mergeCells(in: NSRange(location: 0, length: 2))
        let hintCell = grid.cell(for: loginHint)
        hintCell?.xPlacement = .leading
        // Hiding the view alone would not collapse the grid row — hide the row.
        loginHintRow = hintCell?.row
        loginHintRow?.isHidden = true

        for hint in [claudeHint!, lineHint!, barsHint!, notifyHint!, updateHint!,
                     privacyTitle!, privacyBody!] {
            grid.cell(for: hint)?.row?.mergeCells(in: NSRange(location: 0, length: 2))
            grid.cell(for: hint)?.xPlacement = .leading
        }

        let content = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        win.contentView = content
        window = win
        relabel()
        win.setContentSize(content.fittingSize)
    }

    private static func label() -> NSTextField {
        NSTextField(labelWithString: "")
    }

    // MARK: - State sync

    @objc private func relabel() {
        loginLabel.stringValue = L10n.t("settings.launchAtLogin")
        loginHint.stringValue = L10n.t("settings.loginHint")
        refreshLabel.stringValue = L10n.t("settings.refreshEvery")
        lineLabel.stringValue = L10n.t("settings.claudeStatusLine")
        lineHint.stringValue = L10n.t("settings.claudeStatusLineHint")
        privacyTitle.stringValue = L10n.t("settings.privacy")
        privacyBody.stringValue = L10n.t("settings.privacyBody")
        claudeLabel.stringValue = L10n.t("settings.claudeCredential")
        claudeHint.stringValue = L10n.t("settings.claudeCredentialHint")
        barsLabel.stringValue = L10n.t("settings.menuBarBars")
        barsHint.stringValue = L10n.t("settings.menuBarBarsHint")
        notifyLabel.stringValue = L10n.t("settings.notifyOnReset")
        notifyHint.stringValue = L10n.t("settings.notifyHint")
        updateLabel.stringValue = L10n.t("settings.autoUpdate")
        updateHint.stringValue = L10n.t("settings.autoUpdateHint")
        languageLabel.stringValue = L10n.t("settings.language")
        window?.title = L10n.t("settings.title")

        let selected = refreshPopup.indexOfSelectedItem
        refreshPopup.removeAllItems()
        refreshPopup.addItems(withTitles: refreshChoices.map {
            String(format: L10n.t("settings.minutes"), $0)
        })
        if selected >= 0 && selected < refreshChoices.count {
            refreshPopup.selectItem(at: selected)
        }
    }

    private func setHintVisible(_ visible: Bool) {
        guard loginHintRow?.isHidden != !visible else { return }
        loginHintRow?.isHidden = !visible
        if let content = window?.contentView {
            window?.setContentSize(content.fittingSize)
        }
    }

    private func syncFromState() {
        setHintVisible(false)
        loginSwitch.state = LoginItem.isEnabled ? .on : .off
        let index = refreshChoices.firstIndex(of: Prefs.refreshIntervalMinutes) ?? 1
        refreshPopup.selectItem(at: index)
        lineSwitch.state = Prefs.claudeStatusLine ? .on : .off
        claudeSwitch.state = Prefs.claudeKeychainConsent ? .on : .off
        barsSwitch.state = Prefs.menuBarBars ? .on : .off
        notifySwitch.state = Prefs.notifyOnReset ? .on : .off
        updateSwitch.state = Prefs.autoUpdate ? .on : .off
        languagePopup.selectItem(at: L10n.current == .ptBR ? 0 : 1)
    }

    // MARK: - Actions

    @objc private func loginChanged() {
        let wanted = loginSwitch.state == .on
        let ok = LoginItem.set(enabled: wanted)
        if !ok && wanted {
            // Registration fails when translocated / outside Applications.
            loginSwitch.state = .off
        }
        setHintVisible(!ok && wanted)
    }

    @objc private func refreshIntervalChanged() {
        let index = refreshPopup.indexOfSelectedItem
        guard index >= 0 && index < refreshChoices.count else { return }
        Prefs.refreshIntervalMinutes = refreshChoices[index]
        store.restartTimer()
    }

    /// Opting in is what allows the app to read Claude Code's saved login —
    /// the first read triggers the one-time macOS Keychain prompt.
    @objc private func claudeCredentialChanged() {
        Prefs.claudeKeychainConsent = claudeSwitch.state == .on
        ClaudeProvider.invalidateGate()
        store.refresh(manual: true)
    }

    /// Registers or removes the Claude Code status-line bridge. Turning it off
    /// puts back whatever status line the user had before.
    @objc private func claudeStatusLineChanged() {
        Prefs.claudeStatusLine = lineSwitch.state == .on
        AppDelegate.syncClaudeStatusLine()
        store.refresh(manual: true)
    }

    @objc private func barsChanged() {
        Prefs.menuBarBars = barsSwitch.state == .on
        NotificationCenter.default.post(name: .usageDidUpdate, object: nil)
    }

    @objc private func notifyChanged() {
        Prefs.notifyOnReset = notifySwitch.state == .on
        Notifier.requestAuthorizationIfNeeded()
    }

    @objc private func autoUpdateChanged() {
        Prefs.autoUpdate = updateSwitch.state == .on
        if Prefs.autoUpdate { Task { await Updater.checkAndInstall() } }
    }

    @objc private func languageChanged() {
        L10n.current = languagePopup.indexOfSelectedItem == 0 ? .ptBR : .en
    }
}
