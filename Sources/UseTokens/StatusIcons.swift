import AppKit

/// Menu bar token glyph, drawn at runtime. The same chip shape (scaled up)
/// lives in Sources/assetgen/main.swift for the app icon and DMG artwork —
/// keep the two in sync if the shape changes.
///
/// The glyph always carries the brand colour; severity is a small badge dot so
/// the icon stays recognisable at a glance:
///   under 90 %  → no dot
///   90–99 %     → yellow dot (close to the limit)
///   100 %       → red dot (limit reached)
enum StatusIcons {
    private static let size = NSSize(width: 18, height: 18)

    static let teal = NSColor(calibratedRed: 0.24, green: 0.78, blue: 0.66, alpha: 1.0)
    static let amber = NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0)
    static let red = NSColor(calibratedRed: 0.94, green: 0.29, blue: 0.24, alpha: 1.0)

    /// Percentages at which the badge appears and turns critical.
    static let warningPercent: Double = 90
    static let criticalPercent: Double = 100

    private static let plain = icon(badge: nil)
    private static let warning = icon(badge: amber)
    private static let critical = icon(badge: red)

    static func icon(forPercent percent: Double) -> NSImage {
        if percent >= criticalPercent { return critical }
        if percent >= warningPercent { return warning }
        return plain
    }

    private static func icon(badge: NSColor?) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            drawToken(in: rect, filled: true, color: teal, badge: badge)
            return true
        }
        // Never a template: a template image is flattened to a monochrome mask
        // and both the brand colour and the badge would be lost.
        img.isTemplate = false
        return img
    }

    /// Poker-chip token in an 18×18 design space: outer disc, inner ring and
    /// centre dot punched out so the glyph reads on any menu bar shade.
    static func drawToken(in rect: NSRect, filled: Bool, color: NSColor,
                          badge: NSColor? = nil) {
        let s = min(rect.width, rect.height) / 18.0
        let center = NSPoint(x: rect.midX, y: rect.midY)

        func circle(radius: CGFloat, at point: NSPoint? = nil) -> NSBezierPath {
            let c = point ?? center
            return NSBezierPath(ovalIn: NSRect(
                x: c.x - radius * s, y: c.y - radius * s,
                width: radius * 2 * s, height: radius * 2 * s))
        }

        color.setStroke()
        color.setFill()

        if filled {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            circle(radius: 6.5).fill()

            ctx.setBlendMode(.destinationOut)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let ring = circle(radius: 3.6)
            ring.lineWidth = 1.3 * s
            ring.stroke()
            circle(radius: 1.1).fill()

            if badge != nil {
                // Clear a moat so the badge never blends into the disc.
                circle(radius: 3.3, at: NSPoint(x: rect.minX + 13.6 * s,
                                                y: rect.minY + 13.6 * s)).fill()
            }
            ctx.setBlendMode(.normal)
            ctx.endTransparencyLayer()

            if let badge {
                badge.setFill()
                circle(radius: 2.5, at: NSPoint(x: rect.minX + 13.6 * s,
                                                y: rect.minY + 13.6 * s)).fill()
            }
        } else {
            let outer = circle(radius: 6.5)
            outer.lineWidth = 1.4 * s
            outer.stroke()
            let ring = circle(radius: 3.5)
            ring.lineWidth = 1.2 * s
            ring.stroke()
            circle(radius: 1.1).fill()
        }
    }
}
