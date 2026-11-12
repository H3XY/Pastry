// Draws Pastry's app icon (a pasty!) and writes Resources/AppIcon.icns.
// Run from the repo root:  xcrun swift tools/make-icon.swift
import AppKit

let S: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func drawIcon() {
    // Background: macOS-style rounded square with a soft blue gradient.
    let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x5B8DEF).setFill()
    bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x9CCBFF), ending: color(0x4A6FD8))!.draw(in: bg, angle: -90)

    // Pasty geometry: a half-moon with a rope crimp along the curved edge.
    let cx: CGFloat = 512, base: CGFloat = 380, rx: CGFloat = 290, ry: CGFloat = 270

    // Shadow on the "plate".
    color(0x1B2D6B, 0.30).setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - rx - 10, y: base - 62, width: (rx + 10) * 2, height: 80)).fill()

    // Body: elliptical dome with a slightly rounded base.
    let dome = NSBezierPath()
    dome.move(to: NSPoint(x: cx - rx, y: base))
    let steps = 64
    for i in 0...steps {
        let t = CGFloat.pi * (1 - CGFloat(i) / CGFloat(steps))
        dome.line(to: NSPoint(x: cx + rx * cos(t), y: base + ry * sin(t)))
    }
    dome.curve(to: NSPoint(x: cx - rx, y: base),
               controlPoint1: NSPoint(x: cx + rx * 0.6, y: base - 52),
               controlPoint2: NSPoint(x: cx - rx * 0.6, y: base - 52))
    dome.close()
    NSGradient(colors: [color(0xF7C665), color(0xE59A35), color(0xB86A1C)])!.draw(in: dome, angle: -90)

    // Soft highlight on the upper-left of the crust.
    NSGraphicsContext.saveGraphicsState()
    dome.addClip()
    NSGradient(starting: color(0xFFF4D6, 0.55), ending: color(0xFFF4D6, 0))!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: cx - 230, y: base + 70, width: 300, height: 200)), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()

    // Crimp: overlapping rounded lumps along the dome edge.
    let crimps = 15
    for i in 0..<crimps {
        let t = CGFloat.pi * (1 - (CGFloat(i) + 0.5) / CGFloat(crimps))
        let p = NSPoint(x: cx + rx * cos(t), y: base + ry * sin(t))
        let r: CGFloat = 40
        let lump = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r * 0.85, width: r * 2, height: r * 1.7))
        var rot = AffineTransform(translationByX: p.x, byY: p.y)
        rot.rotate(byRadians: t - .pi / 2 + 0.5)
        rot.translate(x: -p.x, y: -p.y)
        lump.transform(using: rot)
        NSGradient(starting: color(0xF9D27C), ending: color(0xC9792A))!.draw(in: lump, angle: -70)
        color(0x9A5414, 0.55).setStroke()
        lump.lineWidth = 5
        lump.stroke()
    }

    // Steam vents.
    color(0x7A3E0E).setStroke()
    for (x, y, a) in [(412.0, 520.0, 0.5), (512.0, 545.0, 0.0), (612.0, 520.0, -0.5)] as [(CGFloat, CGFloat, CGFloat)] {
        let slit = NSBezierPath()
        slit.move(to: NSPoint(x: x, y: y - 34))
        slit.line(to: NSPoint(x: x, y: y + 34))
        var rot = AffineTransform(translationByX: x, byY: y)
        rot.rotate(byRadians: a)
        rot.translate(x: -x, y: -y)
        slit.transform(using: rot)
        slit.lineWidth = 18
        slit.lineCapStyle = .round
        slit.stroke()
    }

    // Little puffs of steam.
    color(0xFFFFFF, 0.85).setStroke()
    for x in [452.0, 572.0] as [CGFloat] {
        let s = NSBezierPath()
        s.move(to: NSPoint(x: x, y: 700))
        s.curve(to: NSPoint(x: x, y: 820), controlPoint1: NSPoint(x: x + 40, y: 740), controlPoint2: NSPoint(x: x - 40, y: 780))
        s.lineWidth = 16
        s.lineCapStyle = .round
        s.stroke()
    }
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
drawIcon()
NSGraphicsContext.restoreGraphicsState()

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = iconset.appendingPathComponent("icon_512x512@2x.png")
try! rep.representation(using: .png, properties: [:])!.write(to: master)

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512)] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent("icon_\(name).png").path]
    p.standardOutput = FileHandle.nullDevice
    try! p.run(); p.waitUntilExit()
}

try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try? fm.removeItem(atPath: "Resources/AppIcon-1024.png")
try! fm.copyItem(at: master, to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
let ic = Process()
ic.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
ic.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! ic.run(); ic.waitUntilExit()
print("Wrote Resources/AppIcon.icns and Resources/AppIcon-1024.png")
