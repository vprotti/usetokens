import AppKit

/// One provider card: mark + name + plan chip, then the limit groups — the
/// plan's general limits first, then one titled block per model group.
final class ProviderCardView: NSView {
    private let providerID: String
    private let displayName: String
    private let glyphView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let accountLabel = NSTextField(labelWithString: "")
    private let planChip = NSTextField(labelWithString: "")
    private let sourceChip = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private var lastStatus: ProviderStatus?

    /// Set by the popover: user pressed "Connect to Claude".
    var onConnect: (() -> Void)?

    init(providerID: String, displayName: String, glyph: NSImage) {
        self.providerID = providerID
        self.displayName = displayName
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        glyphView.image = glyph
        glyphView.imageScaling = .scaleProportionallyUpOrDown
        glyphView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = displayName
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        accountLabel.font = .systemFont(ofSize: 10)
        accountLabel.textColor = .tertiaryLabelColor
        accountLabel.isHidden = true

        let titleStack = NSStackView(views: [nameLabel, accountLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        for chip in [sourceChip, planChip] {
            chip.font = .systemFont(ofSize: 10, weight: .medium)
            chip.textColor = .tertiaryLabelColor
            chip.isHidden = true
        }
        planChip.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [glyphView, titleStack, spacer, sourceChip, planChip])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 5

        let root = NSStackView(views: [header, rowsStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
            rowsStack.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24),
            glyphView.widthAnchor.constraint(equalToConstant: ProviderGlyphs.side),
            glyphView.heightAnchor.constraint(equalToConstant: ProviderGlyphs.side),
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }

    func update(with status: ProviderStatus?) {
        lastStatus = status
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        glyphView.alphaValue = 1

        guard let status else {
            planChip.isHidden = true
            sourceChip.isHidden = true
            accountLabel.isHidden = true
            return
        }

        // "Claude" na primeira linha, "(v*******@gmail.com)" na segunda.
        accountLabel.isHidden = status.accountLabel == nil
        if let account = status.accountLabel {
            accountLabel.stringValue = "(\(account))"
        }

        planChip.isHidden = status.planType == nil
        if let plan = status.planType {
            // Providers hand over raw keys ("pro", "max_20x"); the account file
            // hands over a finished name ("Max 20x"). Capitalizing the second
            // kind turns "20x" into "20X", so only tidy what still looks raw.
            let spaced = plan.replacingOccurrences(of: "_", with: " ")
            planChip.stringValue = spaced.contains(where: \.isUppercase)
                ? spaced : spaced.capitalized
        }
        sourceChip.isHidden = status.source == .live
        let estimated = status.source == .localEstimate
        sourceChip.stringValue = L10n.t(estimated ? "state.estimate" : "state.localReading")
        sourceChip.toolTip = L10n.t(estimated ? "state.estimateTip" : "state.localReadingTip")

        switch status.state {
        case .needsConsent:
            glyphView.alphaValue = 0.4
            sourceChip.isHidden = true
            planChip.isHidden = true
            let button = NSButton(title: L10n.t("claude.connect"), target: self,
                                  action: #selector(connectPressed))
            button.bezelStyle = .rounded
            button.controlSize = .small
            rowsStack.addArrangedSubview(button)
            addQuietRow(text: L10n.t("claude.keychainHint"), wrapping: true)
            return
        case .notConnected:
            glyphView.alphaValue = 0.4
            sourceChip.isHidden = true
            planChip.isHidden = true
            addQuietRow(text: L10n.t(status.noteKey ?? "state.notConnected.\(providerID)"),
                        wrapping: true)
            return
        case .needsReconnect, .rateLimited:
            if let note = status.noteKey { addQuietRow(text: L10n.t(note), wrapping: true) }
        case .ok:
            // A working provider can still have nothing current to report —
            // say so in words rather than showing an old number.
            if let note = status.noteKey { addQuietRow(text: L10n.t(note), wrapping: true) }
        }

        for (index, group) in status.groups.enumerated() {
            let multipleGroups = status.groups.count > 1
            if multipleGroups {
                addGroupTitle(group.title ?? L10n.t("group.general"), first: index == 0)
            }
            for window in group.windows { addWindowRows(window) }
        }
    }

    // MARK: - Rows

    private func addGroupTitle(_ text: String, first: Bool) {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 9, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        // Slight optical tracking so the small caps don't feel cramped.
        label.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                         .foregroundColor: NSColor.tertiaryLabelColor,
                         .kern: 0.6])
        if !first, let previous = rowsStack.arrangedSubviews.last {
            rowsStack.setCustomSpacing(14, after: previous)
        }
        rowsStack.addArrangedSubview(label)
        rowsStack.setCustomSpacing(7, after: label)
    }

    /// "5 horas", or "Semana (Fable)" once the model name is substituted in.
    private func caption(for window: LimitWindow) -> String {
        let base = L10n.t(window.labelKey)
        guard let argument = window.labelArgument else { return base }
        return base.contains("%@") ? String(format: base, argument) : argument
    }

    private func addWindowRows(_ window: LimitWindow) {
        if let percent = window.usedPercent {
            let label = NSTextField(labelWithString: caption(for: window))
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor

            let value = NSTextField(labelWithString: "\(Int(percent.rounded()))%")
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            value.textColor = UsageBarView.fillColor(for: percent)

            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: [label, spacer, value])
            row.orientation = .horizontal
            row.spacing = 6
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true

            let bar = UsageBarView(frame: .zero)
            bar.setPercent(percent)
            rowsStack.addArrangedSubview(bar)
            bar.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        } else if let tokens = window.tokensUsed {
            let text = String(format: L10n.t("tokens.last5h"), RelativeTime.formatTokens(tokens))
                + " · " + L10n.t("state.estimate")
            addQuietRow(text: text)
        }

        if let resets = window.resetsAt, resets > Date() {
            addQuietRow(text: RelativeTime.resetString(until: resets), tertiary: true)
        } else if window.usedPercent != nil {
            // Sources that report a percentage but no reset time (the Claude
            // desktop history) get one once a rollover has been observed.
            addQuietRow(text: L10n.t("resets.unknown"), tertiary: true)
        }
        // A value read from another app's snapshot says how old it is, so a
        // number that stopped moving never poses as current.
        if let readAt = window.readAt {
            let age = Date().timeIntervalSince(readAt)
            if age > 10 * 60 {
                addQuietRow(text: String(format: L10n.t("state.readAgo"),
                                         RelativeTime.duration(seconds: age)),
                            tertiary: true)
            }
        }
        if let reset = UsageHistory.recentReset(for: window.id) {
            addQuietRow(text: RelativeTime.resetNotice(at: reset.at,
                                                       percentBefore: reset.percentBefore),
                        tertiary: true)
        }
        if let last = rowsStack.arrangedSubviews.last {
            rowsStack.setCustomSpacing(9, after: last)
        }
    }

    private func addQuietRow(text: String, wrapping: Bool = false, tertiary: Bool = false) {
        let label: NSTextField = wrapping
            ? NSTextField(wrappingLabelWithString: text)
            : NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = tertiary ? .tertiaryLabelColor : .secondaryLabelColor
        rowsStack.addArrangedSubview(label)
        if wrapping {
            label.preferredMaxLayoutWidth = 260
            label.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
    }

    /// Re-render countdown lines and localized text without a new fetch.
    func rerender() {
        update(with: lastStatus)
    }

    @objc private func connectPressed() {
        onConnect?()
    }
}
