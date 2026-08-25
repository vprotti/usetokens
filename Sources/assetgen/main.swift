import AppKit

// Renders every raster asset for UseTokens from code. The token/chip shape
// mirrors the runtime menu bar glyph in Sources/UseTokens/StatusIcons.swift —
// keep the two in sync.
//
// Usage:
//   assetgen icon <out.png>            1024x1024 app icon
//   assetgen dmg-background <out.png>  1320x800 px (660x400 pt @2x)
//   assetgen web <outdir>              usetokens@2x.png + usetokens.png ONLY
//                                      (favicon/apple-touch-icon belong to the site brand)

let teal = NSColor(calibratedRed: 0.24, green: 0.78, blue: 0.66, alpha: 1.0)
let tealLight = NSColor(calibratedRed: 0.45, green: 0.89, blue: 0.78, alpha: 1.0)

// MARK: - PNG rendering harness (same as caffeine-free's assetgen)

func renderPNG(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize? = nil,
               draw: (NSRect) -> Void) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("could not create bitmap rep") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    if let pt = pointSize { rep.size = pt } // stamps 144 dpi for the DMG background
    guard let data = rep.representation(using: .png, properties: [:])
    else { fatalError("could not encode png") }
    return data
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try data.write(to: url)
        print("wrote \(path)")
    } catch {
        FileHandle.standardError.write("failed to write \(path): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// MARK: - Token drawing (mirror of StatusIcons.drawToken, scaled design)

func drawChip(in rect: NSRect, gradient: NSGradient?) {
    let s = min(rect.width, rect.height)
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let outerR = s / 2

    func circle(_ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2))
    }

    // The whole chip is composed in a transparency layer: notches, ring and
    // center dot are PUNCHED OUT (destinationOut), so the background shows
    // through and any caller-set shadow wraps the final composite shape.
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    let disc = circle(outerR)
    if let gradient {
        gradient.draw(in: disc, angle: -90)
    } else {
        teal.setFill()
        disc.fill()
    }

    ctx.setBlendMode(.destinationOut)
    NSColor.black.setFill()
    NSColor.black.setStroke()

    // Rim notches, rotated 45° off the cardinal axes.
    let notchWidth = outerR * 0.30
    for angle in stride(from: 45.0, to: 405.0, by: 90.0) {
        let rad = angle * .pi / 180
        circle(notchWidth / 2).transformed(
            byTranslatingX: cos(rad) * outerR, y: sin(rad) * outerR).fill()
    }

    // Inner concentric ring + center dot.
    let ring = circle(outerR * 0.58)
    ring.lineWidth = s * 0.045
    ring.stroke()
    circle(outerR * 0.07).fill()

    ctx.setBlendMode(.normal)
    ctx.endTransparencyLayer()
}

extension NSBezierPath {
    func transformed(byTranslatingX dx: CGFloat, y dy: CGFloat) -> NSBezierPath {
        let t = AffineTransform(translationByX: dx, byY: dy)
        let copy = self.copy() as! NSBezierPath
        copy.transform(using: t)
        return copy
    }
}

// MARK: - App icon

func drawIcon(_ canvas: NSRect) {
    let px = canvas.width
    let u = px / 1024.0
    let bgDark = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 1)

    // Standard macOS icon grid: 824x824 squircle centered on a 1024 canvas.
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u),
        xRadius: 186 * u, yRadius: 186 * u)

    let bg = NSGradient(
        starting: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.13, alpha: 1),
        ending: bgDark)
    bg?.draw(in: squircle, angle: -90)

    // Soft teal glow behind the chip.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let glow = NSGradient(colors: [
        teal.withAlphaComponent(0.20),
        teal.withAlphaComponent(0.0),
    ])
    glow?.draw(
        fromCenter: NSPoint(x: 512 * u, y: 490 * u), radius: 0,
        toCenter: NSPoint(x: 512 * u, y: 490 * u), radius: 420 * u,
        options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.07).setStroke()
    squircle.lineWidth = 2 * u
    squircle.stroke()

    // The chip, teal gradient, centered.
    let chipRect = NSRect(x: 242 * u, y: 232 * u, width: 540 * u, height: 540 * u)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.shadowBlurRadius = 28 * u
    shadow.set()
    drawChip(in: chipRect, gradient: NSGradient(starting: tealLight, ending: teal))
    NSGraphicsContext.current?.restoreGraphicsState()
}

// MARK: - DMG background (1320x800 px @2x = 660x400 pt)

func drawDMGBackground(_ canvas: NSRect) {
    // Two zones, and the reason is not decoration: a Finder window that has a
    // background picture is always rendered in the LIGHT appearance, so item
    // labels are black for every user regardless of their system setting.
    // The brand lives in the dark hero band (text we draw ourselves, in white);
    // the icons and their black labels sit on a light shelf below it.
    let u = canvas.width / 1320.0
    func pt(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
        NSPoint(x: x * 2 * u, y: canvas.height - yFromTop * 2 * u)
    }

    let shelfTop = pt(0, 150).y

    NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.04, alpha: 1).setFill()
    canvas.fill()

    // Warm ivory shelf — ~18:1 against black labels.
    NSColor(calibratedRed: 0.945, green: 0.933, blue: 0.910, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: canvas.width, height: shelfTop).fill()

    NSColor(calibratedWhite: 0.0, alpha: 0.35).setFill()
    NSRect(x: 0, y: shelfTop, width: canvas.width, height: 1 * 2 * u).fill()

    // Teal glow behind the wordmark, clipped to the hero band.
    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 0, y: shelfTop, width: canvas.width,
                              height: canvas.height - shelfTop)).addClip()
    let glow = NSGradient(colors: [
        teal.withAlphaComponent(0.16),
        teal.withAlphaComponent(0.0),
    ])
    glow?.draw(fromCenter: NSPoint(x: canvas.width / 2, y: pt(0, 78).y), radius: 0,
               toCenter: NSPoint(x: canvas.width / 2, y: pt(0, 78).y),
               radius: canvas.width * 0.30, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    // Wordmark with a small teal chip to its left.
    let title = "UseTokens" as NSString
    let titleFont = NSFont.systemFont(ofSize: 30 * 2 * u, weight: .semibold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
        .kern: -0.5 * 2 * u,
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    let chipSide = 38.0 * 2 * u
    let groupWidth = chipSide + 14 * 2 * u + titleSize.width
    let groupLeft = (canvas.width - groupWidth) / 2
    let titleBaseline = pt(0, 88).y
    drawChip(in: NSRect(x: groupLeft, y: titleBaseline - 2 * 2 * u,
                        width: chipSide, height: chipSide),
             gradient: NSGradient(starting: tealLight, ending: teal))
    title.draw(at: NSPoint(x: groupLeft + chipSide + 14 * 2 * u, y: titleBaseline),
               withAttributes: titleAttrs)

    // Arrow between the two icon slots, on the light shelf.
    let arrowY = pt(0, 228).y
    let arrowStart = pt(258, 0).x
    let arrowEnd = pt(402, 0).x
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: arrowStart, y: arrowY))
    arrow.line(to: NSPoint(x: arrowEnd, y: arrowY))
    let head = 13.0 * 2 * u
    arrow.move(to: NSPoint(x: arrowEnd - head, y: arrowY + head * 0.72))
    arrow.line(to: NSPoint(x: arrowEnd, y: arrowY))
    arrow.line(to: NSPoint(x: arrowEnd - head, y: arrowY - head * 0.72))
    NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
    arrow.lineWidth = 2.5 * 2 * u
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    let caption = "Arraste para Aplicativos  ·  Drag to Applications" as NSString
    let captionAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12 * 2 * u, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
    ]
    let captionSize = caption.size(withAttributes: captionAttrs)
    caption.draw(at: NSPoint(x: (canvas.width - captionSize.width) / 2, y: pt(0, 368).y),
                 withAttributes: captionAttrs)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(
        "usage: assetgen icon|dmg-background <out.png> | assetgen web <outdir>\n"
            .data(using: .utf8)!)
    exit(64)
}

switch args[1] {
case "icon":
    write(renderPNG(pixelsWide: 1024, pixelsHigh: 1024, draw: drawIcon), to: args[2])

case "dmg-background":
    write(renderPNG(pixelsWide: 1320, pixelsHigh: 800,
                    pointSize: NSSize(width: 660, height: 400),
                    draw: drawDMGBackground),
          to: args[2])

case "web":
    let dir = args[2]
    write(renderPNG(pixelsWide: 1024, pixelsHigh: 1024, draw: drawIcon),
          to: dir + "/usetokens@2x.png")
    write(renderPNG(pixelsWide: 512, pixelsHigh: 512, draw: drawIcon),
          to: dir + "/usetokens.png")

default:
    FileHandle.standardError.write("unknown command \(args[1])\n".data(using: .utf8)!)
    exit(64)
}
