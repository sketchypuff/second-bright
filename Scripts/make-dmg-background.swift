import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Draws the background image for the installer disk image.
//
// Drawn in code for the same reason the app icon is: no binary asset to keep in
// sync, and the layout numbers stay editable. They are shared with
// Scripts/make-dmg.sh, which positions the two Finder icons on top of this
// image -- so if the geometry below changes, the AppleScript coordinates in that
// script have to move with it.
//
// The image deliberately does NOT draw the app or Applications icons. Finder
// draws those itself; this is only the surface underneath them.
//
// Coordinates are top-down in a 660x420 design space, matching the Finder window
// content size; the context is flipped once up front so the numbers read the way
// a designer would write them.

let designW: CGFloat = 660
let designH: CGFloat = 420

// Centres of the two Finder icons. Kept here as the single source for the arrow
// geometry; make-dmg.sh repeats them for `set position of item`.
let appIconCenter = CGPoint(x: 170, y: 198)
let appsIconCenter = CGPoint(x: 490, y: 198)

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

extension CGContext {
    func fill(_ path: CGPath, color: CGColor) {
        saveGState(); addPath(path); setFillColor(color); fillPath(); restoreGState()
    }

    func fill(_ path: CGPath, gradientFrom a: CGColor, to b: CGColor,
              start: CGPoint, end: CGPoint) {
        saveGState()
        addPath(path); clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [a, b] as CFArray, locations: [0, 1])!
        drawLinearGradient(gradient, start: start, end: end, options: [])
        restoreGState()
    }

    /// Draws a line of text centred on `centerX`, sitting on `baselineY`.
    ///
    /// The context runs top-down, so text drawn straight into it comes out
    /// mirrored; the y-flip is undone locally around the glyph run.
    func drawText(_ string: String, size: CGFloat, bold: Bool = false,
                  color: CGColor, centerX: CGFloat, baselineY: CGFloat,
                  tracking: CGFloat = 0) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        // CoreText's own attribute names: the `.font` / `.foregroundColor`
        // spellings come from AppKit, which this script does not link.
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)

        saveGState()
        translateBy(x: centerX - CGFloat(width) / 2, y: baselineY)
        scaleBy(x: 1, y: -1)
        textPosition = .zero
        CTLineDraw(line, self)
        restoreGState()
    }
}

// MARK: - The background

func drawBackground(in ctx: CGContext, scale: CGFloat) {
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: designH)
    ctx.scaleBy(x: 1, y: -1)

    // --- Surface ------------------------------------------------------------
    // The icon's palette, flattened. Kept very pale: Finder renders icon labels
    // in dark text over this, and anything saturated makes them hard to read.
    let sheet = CGPath(rect: CGRect(x: 0, y: 0, width: designW, height: designH), transform: nil)
    ctx.fill(sheet, gradientFrom: rgb(0xFFFBF4), to: rgb(0xE7ECF8),
             start: CGPoint(x: 0, y: 0), end: CGPoint(x: designW, y: designH))

    // --- Title --------------------------------------------------------------
    ctx.drawText("SecondBright", size: 25, bold: true, color: rgb(0x13245C),
                 centerX: designW / 2, baselineY: 62)
    ctx.drawText("Drag the icon onto the Applications folder",
                 size: 13, color: rgb(0x4A5878),
                 centerX: designW / 2, baselineY: 88)

    // --- Arrow --------------------------------------------------------------
    // Spans the gap between the two icons without reaching under either of
    // them; Finder's icon labels extend well below the icon art, and an arrow
    // that runs too close collides with the text.
    let y = appIconCenter.y
    let startX = appIconCenter.x + 92
    let endX = appsIconCenter.x - 92

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0x2E55B4, 0.55))
    ctx.setLineWidth(5)
    ctx.setLineDash(phase: 0, lengths: [1, 11])
    ctx.move(to: CGPoint(x: startX, y: y))
    // Stops clear of the head; a dot tucked behind it reads as a rendering slip.
    ctx.addLine(to: CGPoint(x: endX - 34, y: y))
    ctx.strokePath()
    ctx.restoreGState()

    let head = CGMutablePath()
    head.move(to: CGPoint(x: endX, y: y))
    head.addLine(to: CGPoint(x: endX - 22, y: y - 14))
    head.addLine(to: CGPoint(x: endX - 22, y: y + 14))
    head.closeSubpath()
    ctx.fill(head, color: rgb(0x2E55B4, 0.75))

    // --- First-launch note ---------------------------------------------------
    // The app is ad-hoc signed rather than notarized, so the first open is
    // blocked and the user has to approve it once. Saying so here means they
    // read it at the moment it happens, rather than on a web page they have
    // already navigated away from.
    let noteRect = CGPath(roundedRect: CGRect(x: 40, y: 322, width: designW - 80, height: 62),
                          cornerWidth: 14, cornerHeight: 14, transform: nil)
    ctx.fill(noteRect, color: rgb(0xFFFFFF, 0.62))

    ctx.drawText("The first time you open it, macOS will ask you to approve it.",
                 size: 12.5, bold: true, color: rgb(0x13245C),
                 centerX: designW / 2, baselineY: 348)
    ctx.drawText("Open System Settings \u{203A} Privacy & Security, scroll down, click \u{201C}Open Anyway\u{201D}.",
                 size: 12.5, color: rgb(0x4A5878),
                 centerX: designW / 2, baselineY: 370)
}

// MARK: - Output

func render(scale: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil,
                        width: Int(designW * scale), height: Int(designH * scale),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawBackground(in: ctx, scale: scale)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Both scales, so make-dmg.sh can pack them into one multi-resolution TIFF and
// the background stays sharp on a Retina display.
write(render(scale: 1), to: outputDir.appendingPathComponent("dmg-background.png"))
write(render(scale: 2), to: outputDir.appendingPathComponent("dmg-background@2x.png"))
print("wrote dmg-background.png and dmg-background@2x.png to \(outputDir.path)")
