import AppKit

/// Popover content: header (title + refresh), one card per provider, footer
/// with the last-checked timestamp. Re-renders countdowns every 30 s and
/// auto-refreshes every 5 min while visible.
final class PopoverViewController: NSViewController {
    private let store: UsageStore
    private var cards: [String: ProviderCardView] = [:]
    private var root: NSStackView!
    private let footer = NSTextField(labelWithString: "")
    private let refreshButton = RefreshButton()
    private var countdownTimer: Timer?
    private var openRefreshTimer: Timer?

    init(store: UsageStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = NSTextField(labelWithString: "UseTokens")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        refreshButton.toolTip = L10n.t("popover.refreshTooltip")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [title, spacer, refreshButton])
        header.orientation = .horizontal
        header.spacing = 8

        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let root = NSStackView(views: [header])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(footer)
        self.root = root

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 320),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        footer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true

        view = container

        NotificationCenter.default.addObserver(
            self, selector: #selector(render), name: .usageDidUpdate, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(render), name: .languageDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStateChanged),
            name: .usageRefreshStateChanged, object: nil)
        render()
    }

    /// One card per account. Cards appear and disappear as the user signs in
    /// and out, so a second ChatGPT or Claude login shows up on the next refresh.
    private func syncCards() {
        // The stack is [header, ...cards..., footer]; cards start after the header.
        let headerOffset = 1
        let wanted = store.statuses.map { $0.key }

        for (key, card) in cards where !wanted.contains(key) {
            root.removeArrangedSubview(card)
            card.removeFromSuperview()
            cards.removeValue(forKey: key)
        }

        for (index, status) in store.statuses.enumerated() {
            let card: ProviderCardView
            if let existing = cards[status.key] {
                card = existing
            } else {
                let provider = store.provider(for: status)
                card = ProviderCardView(
                    providerID: status.providerID,
                    displayName: provider?.displayName ?? status.providerID,
                    glyph: provider?.glyph ?? NSImage())
                card.onConnect = { [weak self] in
                    Prefs.claudeKeychainConsent = true
                    self?.store.refresh(manual: true)
                }
                cards[status.key] = card
                // Must join the hierarchy before the width constraint can bind.
                root.insertArrangedSubview(card, at: index + headerOffset)
                card.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true
                continue
            }
            // Keep the visual order matching the status order.
            root.insertArrangedSubview(card, at: index + headerOffset)
        }
    }

    // MARK: - Spin the refresh icon while a fetch is in flight

    @objc private func refreshStateChanged() {
        refreshButton.setSpinning(store.isRefreshing)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let countdown = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.render() }
        RunLoop.main.add(countdown, forMode: .common)
        countdownTimer = countdown

        let autoRefresh = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
        RunLoop.main.add(autoRefresh, forMode: .common)
        openRefreshTimer = autoRefresh
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        countdownTimer?.invalidate(); countdownTimer = nil
        openRefreshTimer?.invalidate(); openRefreshTimer = nil
    }

    /// Manual refresh: re-checks credentials too, so a newly signed-in account
    /// shows up without restarting the app.
    @objc private func refreshPressed() {
        store.refresh(manual: true)
    }

    @objc private func render() {
        syncCards()
        for status in store.statuses {
            cards[status.key]?.update(with: status)
        }
        if let newest = store.statuses.map({ $0.lastUpdated }).max() {
            footer.stringValue = String(format: L10n.t("popover.lastChecked"),
                                        RelativeTime.lastChecked(newest))
        } else {
            footer.stringValue = ""
        }
        refreshButton.toolTip = L10n.t("popover.refreshTooltip")

        // NSPopover only tracks growth on its own; without this it keeps the
        // tallest size it ever had and leaves a blank strip when rows go away.
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }
}
