// Regenerates Loqui's brand assets from code: the macOS app icon
// (Loqui/AppIcon.icns) and the README icon (docs/brand/loqui-icon.png).
//
//   swift scripts/generate-brand-assets.swift
//
// The mark is the "Cursor Wave" in the Spectrum colorway: four sound bars that
// step up and resolve into a text cursor. Geometry uses the same 120x100 grid
// as the design canvas, and every size is drawn as vectors rather than scaled.
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

enum Brand {
    static let ground = color(0x0F1419)
    static let bars = [color(0xFF6B5B), color(0xFFB547), color(0x3DDC97), color(0x5AC8FA)]
    static let cursor = color(0xFFFFFF)
    // (x, y, height) of each 10-unit-wide bar in the 120x100 mark grid.
    static let barGeometry: [(CGFloat, CGFloat, CGFloat)] = [(6, 38, 24), (24, 26, 48), (42, 16, 68), (60, 32, 36)]
}

/// Apple's icon body is a continuous-corner squircle, close to a superellipse
/// with exponent 5.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2, n: CGFloat = 5
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Draws the mark with its 120x100 grid mapped so the grid's height is `height`
/// and its center is `center`. The context must be flipped (y down).
func drawMark(_ ctx: CGContext, center: CGPoint, height: CGFloat) {
    let unit = height / 100
    let origin = CGPoint(x: center.x - 60 * unit, y: center.y - 50 * unit)
    for ((x, y, h), fill) in zip(Brand.barGeometry, Brand.bars) {
        let rect = CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: 10 * unit, height: h * unit)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5 * unit, cornerHeight: 5 * unit, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    ctx.setStrokeColor(Brand.cursor)
    ctx.setLineWidth(8 * unit)
    ctx.setLineCap(.round)
    for (x1, y1, x2, y2) in [(94.0, 14.0, 94.0, 86.0), (82, 14, 106, 14), (82, 86, 106, 86)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        ctx.move(to: CGPoint(x: origin.x + x1 * unit, y: origin.y + y1 * unit))
        ctx.addLine(to: CGPoint(x: origin.x + x2 * unit, y: origin.y + y2 * unit))
    }
    ctx.strokePath()
}

/// Renders the app icon at `pixels` square, following the macOS icon grid:
/// an 824/1024 body with a soft drop shadow.
func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let scale = size / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale, color: color(0x000000, 0.3))
    ctx.addPath(squircle(in: body))
    ctx.setFillColor(Brand.ground)
    ctx.fillPath()
    ctx.restoreGState()
    drawMark(ctx, center: CGPoint(x: body.midX, y: body.midY), height: body.height * 0.5)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try writePNG(renderIcon(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(renderIcon(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let icns = root.appendingPathComponent("Loqui/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(icns.path)")

let readmeIcon = root.appendingPathComponent("docs/brand/loqui-icon.png")
try writePNG(renderIcon(pixels: 512), to: readmeIcon)
print("wrote \(readmeIcon.path)")
