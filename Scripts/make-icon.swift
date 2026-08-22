import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Draws the app icon: a monitor lit from behind by a bulb.
//
// Drawn in code rather than exported from a design tool so it re-renders sharply
// at every icon size, and so the geometry stays editable without binary assets.
//
// All coordinates are expressed top-down in a 1024x1024 design space; the context
// is flipped once up front so the numbers read the way a designer would write them.

let design: CGFloat = 1024

// MARK: - Geometry helpers

/// Apple's icon shape is a squircle (continuous corners), not a rounded rectangle.
/// A superellipse with an exponent near 5 matches it closely; a plain rounded rect
/// reads as subtly wrong next to real macOS icons.
func squircle(center: CGPoint, half: CGFloat, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 512
    for i in 0...steps {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
        let c = cos(t), s = sin(t)
        let x = center.x + half * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = center.y + half * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
           cornerWidth: r, cornerHeight: r, transform: nil)
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

extension CGContext {
    func fill(_ path: CGPath, gradientFrom a: CGColor, to b: CGColor,
              start: CGPoint, end: CGPoint) {
        saveGState()
        addPath(path); clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [a, b] as CFArray, locations: [0, 1])!
        drawLinearGradient(gradient, start: start, end: end, options: [])
        restoreGState()
    }

    func fill(_ path: CGPath, color: CGColor) {
        saveGState(); addPath(path); setFillColor(color); fillPath(); restoreGState()
    }

    func stroke(_ path: CGPath, color: CGColor, width: CGFloat) {
        saveGState()
        addPath(path); setStrokeColor(color); setLineWidth(width); strokePath()
        restoreGState()
    }

    func radialGlow(center: CGPoint, radius: CGFloat, color: CGColor) {
        saveGState()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color, color.copy(alpha: 0)!] as CFArray,
                                  locations: [0, 1])!
        drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
        restoreGState()
    }
}

// MARK: - The icon

func drawIcon(in ctx: CGContext, pixels: CGFloat) {
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Work in the 1024 design space regardless of output size, with y running
    // downward so the layout numbers read top-down.
    let scale = pixels / design
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: design)
    ctx.scaleBy(x: 1, y: -1)

    // --- Background plate -------------------------------------------------
    let plate = squircle(center: CGPoint(x: 512, y: 496), half: 412)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 40, color: rgb(0x1B2333, 0.22))
    ctx.fill(plate, color: rgb(0xFFFFFF))
    ctx.restoreGState()

    ctx.fill(plate, gradientFrom: rgb(0xFFF9F0), to: rgb(0xDDE4F5),
             start: CGPoint(x: 140, y: 110), end: CGPoint(x: 900, y: 890))

    // Subjects overrun the plate and are clipped by it. That cropping is what
    // gives the reference icons their scale.
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()

    // --- Monitor -----------------------------------------------------------
    // Centred on the plate. Deliberately dark: the bulb is the subject, and a
    // deep screen is what lets a warm light read as actually glowing.
    let cx: CGFloat = 512

    ctx.fill(roundedRect(cx - 42, 670, 84, 116, 22), color: rgb(0x13245C))
    ctx.fill(roundedRect(cx - 130, 766, 260, 52, 26),
             gradientFrom: rgb(0x2E4FA8), to: rgb(0x13245C),
             start: CGPoint(x: cx - 130, y: 766), end: CGPoint(x: cx + 130, y: 818))

    // Left and right edges stay inside the plate. Cropping them makes the shape
    // read as a band across the icon rather than as a monitor.
    let bezel = roundedRect(cx - 372, 206, 744, 476, 74)
    ctx.fill(bezel, gradientFrom: rgb(0x2E55B4), to: rgb(0x0B1848),
             start: CGPoint(x: cx - 360, y: 216), end: CGPoint(x: cx + 360, y: 674))
    ctx.stroke(bezel, color: rgb(0xFFFFFF, 0.24), width: 6)

    let panel = roundedRect(cx - 332, 246, 664, 396, 50)
    ctx.fill(panel, gradientFrom: rgb(0x16307E), to: rgb(0x060F30),
             start: CGPoint(x: cx - 332, y: 246), end: CGPoint(x: cx + 332, y: 642))

    // Light pooling on the panel. Kept pale rather than saturated amber: strong
    // orange over navy turns brown and reads as grime instead of illumination.
    ctx.saveGState()
    ctx.addPath(panel); ctx.clip()
    ctx.radialGlow(center: CGPoint(x: cx, y: 322), radius: 356, color: rgb(0xFFEFC8, 0.55))
    ctx.restoreGState()

    // --- Bulb --------------------------------------------------------------
    // Sits over the top bezel rather than fully inside the panel: overlapping the
    // frame is what makes it read as a separate layer in front, and it keeps the
    // whole silhouette -- glass, neck and screw base -- visible. Hiding the base
    // is what makes a bulb read as a balloon.
    ctx.radialGlow(center: CGPoint(x: cx, y: 308), radius: 300, color: rgb(0xFFC24D, 0.42))

    // Screw base first, so the glass overlaps it.
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: cx - 84, y: 418))
    neck.addLine(to: CGPoint(x: cx + 84, y: 418))
    neck.addLine(to: CGPoint(x: cx + 62, y: 494))
    neck.addLine(to: CGPoint(x: cx - 62, y: 494))
    neck.closeSubpath()
    ctx.fill(neck, gradientFrom: rgb(0xF2B160), to: rgb(0xCE8630),
             start: CGPoint(x: cx - 84, y: 418), end: CGPoint(x: cx + 84, y: 494))

    let base = roundedRect(cx - 64, 480, 128, 122, 24)
    ctx.fill(base, gradientFrom: rgb(0xEBA855), to: rgb(0xB87220),
             start: CGPoint(x: cx - 64, y: 480), end: CGPoint(x: cx + 64, y: 602))

    // Two grooves is enough to say "screw base" and they survive to 128px,
    // where finer threading would turn to mush.
    for y in [CGFloat(518), CGFloat(560)] {
        ctx.fill(roundedRect(cx - 64, y, 128, 14, 7), color: rgb(0x8E4F10, 0.40))
    }
    ctx.fill(roundedRect(cx - 34, 596, 68, 34, 16), color: rgb(0xA05E16))

    // Glass.
    let glass = CGPath(ellipseIn: CGRect(x: cx - 152, y: 144, width: 304, height: 304),
                       transform: nil)
    ctx.fill(glass, gradientFrom: rgb(0xFFEE96), to: rgb(0xFF9F22),
             start: CGPoint(x: cx - 128, y: 170), end: CGPoint(x: cx + 136, y: 426))
    ctx.stroke(glass, color: rgb(0xFFFFFF, 0.45), width: 6)

    // Filament: the detail that settles "bulb" beyond doubt at large sizes.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(rgb(0xC2700F, 0.50))
    ctx.setLineWidth(15)
    ctx.move(to: CGPoint(x: cx - 46, y: 358))
    ctx.addLine(to: CGPoint(x: cx - 46, y: 310))
    ctx.addQuadCurve(to: CGPoint(x: cx + 46, y: 310), control: CGPoint(x: cx, y: 232))
    ctx.addLine(to: CGPoint(x: cx + 46, y: 358))
    ctx.strokePath()
    ctx.restoreGState()

    // Specular highlight, top-left, the way the reference icons catch light.
    ctx.fill(CGPath(ellipseIn: CGRect(x: cx - 110, y: 188, width: 120, height: 86),
                    transform: nil),
             color: rgb(0xFFFFFF, 0.38))

    ctx.restoreGState()

    // Rim light, which is what keeps macOS icons from looking flat against a
    // dark wallpaper.
    ctx.stroke(plate, color: rgb(0xFFFFFF, 0.55), width: 3)
}

// MARK: - Output

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: ctx, pixels: CGFloat(pixels))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// The sizes an .iconset requires.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    write(render(pixels: variant.pixels), to: outputDir.appendingPathComponent("\(variant.name).png"))
}
print("wrote \(variants.count) images to \(outputDir.path)")
