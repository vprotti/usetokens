import AppKit

/// Provider marks. Preferred source is the icon of the app already installed on
/// this Mac (ChatGPT.app / Claude.app), rendered in black and white so the two
/// cards read as one system. Nothing is bundled or redistributed — the icon is
/// loaded at runtime from the user's own copy. If the app isn't installed, a
/// drawn glyph stands in.
enum ProviderGlyphs {
    static let side: CGFloat = 24

    static let codex: NSImage = monochromeAppIcon(
        named: ["ChatGPT", "OpenAI ChatGPT", "Codex"]) ?? drawnCodex

    static let claude: NSImage = monochromeAppIcon(
        named: ["Claude"]) ?? drawnClaude

    // MARK: - Installed app icon, desaturated

    private static func monochromeAppIcon(named candidates: [String]) -> NSImage? {
        let fm = FileManager.default
        let roots = ["/Applications",
                     NSHomeDirectory() + "/Applications",
                     "/System/Applications"]
        for name in candidates {
            for root in roots {
                let path = "\(root)/\(name).app"
                guard fm.fileExists(atPath: path) else { continue }
                let icon = NSWorkspace.shared.icon(forFile: path)
                if let mono = desaturate(icon) { return mono }
            }
        }
        return nil
    }

    private static func desaturate(_ image: NSImage) -> NSImage? {
        let pixels = 128 // plenty for a 24 pt slot on retina
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = rep.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)   // black and white
        filter.setValue(1.05, forKey: kCIInputContrastKey)    // keep the mark crisp
        guard let output = filter.outputImage else { return nil }

        let result = NSImage(size: NSSize(width: side, height: side))
        result.addRepresentation(NSCIImageRep(ciImage: output))
        result.size = NSSize(width: side, height: side)
        return result
    }

    // MARK: - Drawn fallbacks (template: adapt to light/dark automatically)

    private static let drawnCodex: NSImage = roundel { rect in
        let u = rect.width / 24
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 8 * u, y: 15 * u))
        chevron.line(to: NSPoint(x: 11.5 * u, y: 12 * u))
        chevron.line(to: NSPoint(x: 8 * u, y: 9 * u))
        chevron.lineWidth = 1.6 * u
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.stroke()

        let cursor = NSBezierPath()
        cursor.move(to: NSPoint(x: 13.5 * u, y: 9 * u))
        cursor.line(to: NSPoint(x: 16.5 * u, y: 9 * u))
        cursor.lineWidth = 1.6 * u
        cursor.lineCapStyle = .round
        cursor.stroke()
    }

    private static let drawnClaude: NSImage = roundel { rect in
        let u = rect.width / 24
        let font = NSFont.systemFont(ofSize: 11 * u, weight: .semibold)
        let rounded = NSFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor,
                             size: 11 * u) ?? font
        let text = "C" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: NSColor.black]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (rect.width - size.width) / 2,
                              y: (rect.height - size.height) / 2),
                  withAttributes: attrs)
    }

    private static func roundel(_ inner: @escaping (NSRect) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let u = rect.width / 24
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1 * u, dy: 1 * u))
            circle.lineWidth = 1.5 * u
            circle.stroke()
            inner(rect)
            return true
        }
        img.isTemplate = true
        return img
    }
}
