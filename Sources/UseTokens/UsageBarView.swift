import AppKit

/// 6 pt layer-backed progress bar. Neutral fill, amber ≥80%, red ≥95%.
final class UsageBarView: NSView {
    private let track = CALayer()
    private let fill = CALayer()
    private var percent: Double = 0

    /// Same thresholds as the menu bar badge, so the two never disagree.
    static func fillColor(for percent: Double) -> NSColor {
        if percent >= StatusIcons.criticalPercent { return StatusIcons.red }
        if percent >= StatusIcons.warningPercent { return StatusIcons.amber }
        return NSColor.labelColor.withAlphaComponent(0.85)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.cornerRadius = 3
        fill.cornerRadius = 3
        layer?.addSublayer(track)
        track.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPercent(_ value: Double) {
        percent = max(0, min(100, value))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        let width = bounds.width * percent / 100
        // A rounded zero-width layer still renders a sliver — hide it instead.
        fill.isHidden = width < 0.5
        fill.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            fill.backgroundColor = Self.fillColor(for: percent).cgColor
        }
    }
}
