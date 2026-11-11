// Draws the DisplayDial icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let center = NSPoint(x: 512 * s, y: 512 * s)

    // Body: warm sunrise gradient.
    let body = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    color(0xF97316).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xFDBA4D), color(0xF97316), color(0xDB2777)])!.draw(in: body, angle: -90)

    // Dial track: a 270° arc with ticks, filled most of the way like a brightness knob.
    let radius: CGFloat = 300 * s
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: -45, clockwise: true)
    track.lineWidth = 46 * s
    track.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.28).setStroke()
    track.stroke()

    let level = NSBezierPath()
    level.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: 20, clockwise: true)
    level.lineWidth = 46 * s
    level.lineCapStyle = .round
    NSColor.white.setStroke()
    level.stroke()

    // Knob dot at the end of the filled part.
    let angle = 20 * CGFloat.pi / 180
    let knob = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0x7C2D12, 0.45)
    glow.shadowBlurRadius = 18 * s
    glow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: knob.x - 48 * s, y: knob.y - 48 * s, width: 96 * s, height: 96 * s)).fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0xF97316).setFill()
    NSBezierPath(ovalIn: NSRect(x: knob.x - 22 * s, y: knob.y - 22 * s, width: 44 * s, height: 44 * s)).fill()

    // Sun in the middle.
    let config = NSImage.SymbolConfiguration(pointSize: 250 * s, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let rect = NSRect(x: center.x - sun.size.width / 2, y: center.y - sun.size.height / 2,
                          width: sun.size.width, height: sun.size.height)
        sun.draw(in: rect)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("DisplayDialIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let png = drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
