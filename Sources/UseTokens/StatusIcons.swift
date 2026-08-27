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

    // MARK: - The reading, drawn in the menu bar

    /// Claude's terracotta and the teal above, so the two stacks are told apart
    /// without a label. Fixed values rather than system colours: these are
    /// brand marks, and they have to look the same on either menu bar shade.
    static let claudeTint = NSColor(calibratedRed: 0.84, green: 0.47, blue: 0.33, alpha: 1.0)

    /// One service's reading: the session window and the week.
    struct Bars {
        let session: Double?
        let week: Double?
        let tint: NSColor
    }

    private enum Bar {
        static let width: CGFloat = 18
        static let height: CGFloat = 3.5
        static let gap: CGFloat = 3.5          // between the two bars of a pair
        static let groupGap: CGFloat = 5       // between services
        static let inset: CGFloat = 3          // breathing room at either end
    }

    /// A compact reading drawn straight into the menu bar: two bars per
    /// service, the session window on top and the week below, always in that
    /// order.
    ///
    /// No numbers. At this size a number is unreadable and a bar is not — how
    /// full it is carries the whole message, and the colour carries the rest.
    /// A service with nothing current to say is simply left out; showing an old
    /// number at a bar's length would be a claim about right now.
    static func barsIcon(_ groups: [Bars]) -> NSImage? {
        let drawable = groups.filter { $0.session != nil || $0.week != nil }
        guard !drawable.isEmpty else { return nil }

        let pairHeight = Bar.height * 2 + Bar.gap
        let width = Bar.inset * 2 + CGFloat(drawable.count) * Bar.width
            + CGFloat(drawable.count - 1) * Bar.groupGap

        let image = NSImage(size: NSSize(width: width, height: size.height),
                            flipped: false) { rect in
            var x = rect.minX + Bar.inset
            let top = rect.midY + pairHeight / 2 - Bar.height
            for group in drawable {
                draw(percent: group.session, tint: group.tint,
                     at: NSPoint(x: x, y: top))
                draw(percent: group.week, tint: group.tint,
                     at: NSPoint(x: x, y: top - Bar.height - Bar.gap))
                x += Bar.width + Bar.groupGap
            }
            return true
        }
        // Not a template: a template is flattened to a monochrome mask, and the
        // colour is half of what these bars say.
        image.isTemplate = false
        return image
    }

    /// One bar: the full length as a faint track, the used part filled over it.
    ///
    /// `labelColor` resolves against whichever menu bar it is drawn into, so
    /// the track stays visible on both. A window with no reading at all draws
    /// the track alone — visibly an empty slot rather than a confident zero.
    private static func draw(percent: Double?, tint: NSColor, at origin: NSPoint) {
        let track = NSRect(x: origin.x, y: origin.y,
                           width: Bar.width, height: Bar.height)
        let radius = Bar.height / 2

        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard let percent else { return }
        let filled = max(0, min(100, percent)) / 100
        guard filled > 0 else { return }

        // Below a couple of points a rounded rectangle collapses into nothing;
        // keep a visible stub so "barely used" still reads as used.
        let width = max(Bar.height, Bar.width * filled)
        color(forPercent: percent, tint: tint).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x, y: origin.y,
                                         width: width, height: Bar.height),
                     xRadius: radius, yRadius: radius).fill()
    }

    /// The brand colour until the limit is close, then the warning takes over —
    /// at a glance, "which service" matters less than "you are nearly out".
    private static func color(forPercent percent: Double, tint: NSColor) -> NSColor {
        if percent >= criticalPercent { return red }
        if percent >= warningPercent { return amber }
        return tint
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
