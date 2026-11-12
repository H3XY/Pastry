import AppKit

/// A one-color pasty for the menu bar, drawn in code. It's a template image,
/// so macOS tints it to match light and dark menu bars like system icons.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let cx: CGFloat = 10, base: CGFloat = 3.2, rx: CGFloat = 7.6, ry: CGFloat = 7.0
            let point = { (t: CGFloat, grow: CGFloat) in
                NSPoint(x: cx + (rx + grow) * cos(t), y: base + (ry + grow) * sin(t))
            }

            // Crust: a half-moon dome with a gently rounded base.
            let dome = NSBezierPath()
            dome.move(to: point(.pi, 0))
            for i in 0...48 { dome.line(to: point(.pi * (1 - CGFloat(i) / 48), 0)) }
            dome.curve(to: point(.pi, 0),
                       controlPoint1: NSPoint(x: cx + rx * 0.6, y: base - 1.8),
                       controlPoint2: NSPoint(x: cx - rx * 0.6, y: base - 1.8))
            dome.close()
            NSColor.black.setFill()
            dome.fill()

            // Crimp: little lumps along the curved edge.
            let lumps = 9
            for i in 0..<lumps {
                let p = point(.pi * (1 - (CGFloat(i) + 0.5) / CGFloat(lumps)), 0.4)
                NSBezierPath(ovalIn: NSRect(x: p.x - 1.55, y: p.y - 1.55, width: 3.1, height: 3.1)).fill()
            }

            // Steam vents, cut out of the crust.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for (x, tilt) in [(7.0, 0.45), (10.0, 0.0), (13.0, -0.45)] as [(CGFloat, CGFloat)] {
                let vent = NSBezierPath()
                let y: CGFloat = 6.4, half: CGFloat = 1.5
                vent.move(to: NSPoint(x: x - half * sin(tilt), y: y - half * cos(tilt)))
                vent.line(to: NSPoint(x: x + half * sin(tilt), y: y + half * cos(tilt)))
                vent.lineWidth = 1.3
                vent.lineCapStyle = .round
                vent.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pastry"
        return image
    }
}
