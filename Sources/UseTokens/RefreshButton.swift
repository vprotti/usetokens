import AppKit

/// Refresh control whose icon spins while a fetch is in flight, so a click
/// always produces visible feedback even when the numbers come back unchanged.
///
/// The icon lives in a sublayer we own (not the view's backing layer), which is
/// what makes a centred anchor point — and therefore a centred rotation —
/// reliable in AppKit.
final class RefreshButton: NSButton {
    private let iconLayer = CALayer()
    private var spinning = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        imagePosition = .noImage
        wantsLayer = true
        iconLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(iconLayer)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
        ])
        updateIcon()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        iconLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateIcon()
    }

    private func updateIcon() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let symbol = NSImage(systemSymbolName: "arrow.clockwise",
                                 accessibilityDescription: nil)
            guard let symbol else { return }
            let size = NSSize(width: 14, height: 14)
            let tinted = NSImage(size: size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSColor.secondaryLabelColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            iconLayer.contents = tinted
        }
    }

    func setSpinning(_ value: Bool) {
        guard value != spinning else { return }
        spinning = value
        if value {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 0.85
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            iconLayer.add(spin, forKey: "spin")
        } else {
            // Let the turn in progress finish so it never stops mid-rotation.
            let remaining = 0.85 - iconLayer.convertTime(CACurrentMediaTime(), from: nil)
                .truncatingRemainder(dividingBy: 0.85)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, remaining)) { [weak self] in
                guard let self, !self.spinning else { return }
                self.iconLayer.removeAnimation(forKey: "spin")
            }
        }
    }
}
