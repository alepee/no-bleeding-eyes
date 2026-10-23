// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift (needs macOS, `iconutil`)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpaceCreateDeviceRGB()
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle following the macOS icon grid: 824 pt body inside a 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x1c1f3f))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Dusk sky: deep night at the top, candle glow at the bottom.
    let sky = CGGradient(colorsSpace: space, colors: [color(0xff8a3d), color(0x8a4a7e), color(0x2a2a5c), color(0x14163a)] as CFArray,
                         locations: [0, 0.38, 0.72, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Halo behind the moon.
    let halo = CGGradient(colorsSpace: space, colors: [color(0xffb46b, 0.55), color(0xffb46b, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: CGPoint(x: 540, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 540, y: 560), endRadius: 340, options: [])

    // Crescent: a disc minus an offset disc.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: 540 - 215, y: 560 - 215, width: 430, height: 430))
    ctx.clip()
    let bite = CGMutablePath()
    bite.addRect(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    bite.addEllipse(in: CGRect(x: 540 - 215 + 130, y: 560 - 215 + 80, width: 400, height: 400))
    ctx.addPath(bite)
    ctx.clip(using: .evenOdd)
    let moon = CGGradient(colorsSpace: space, colors: [color(0xfff1d6), color(0xffc27d)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(moon, start: CGPoint(x: 400, y: 760), end: CGPoint(x: 560, y: 350), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Stars.
    ctx.setFillColor(color(0xfff1d6, 0.9))
    for (x, y, r) in [(720, 760, 13), (790, 640, 8), (610, 830, 7), (330, 330, 9)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // Subtle top highlight.
    let gloss = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.14), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
try render(size: 1024).write(to: URL(fileURLWithPath: "/tmp/nbe-icon-preview.png"))
print("Wrote \(icns.path)")
