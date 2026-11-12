// Renders the App Store screenshots from Pastry's real SwiftUI panel, filled with demo data
// (never your own clipboard). Run: tools/make-screenshots.sh  → AppStore/screenshot-*.png
import AppKit
import SwiftUI

let canvas = CGSize(width: 2880, height: 1800) // Apple's largest 16:10 Mac screenshot size
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppStore")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

@MainActor
func demoStore() -> ClipStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pastry-shots-\(UUID().uuidString)")
    let files = dir.appendingPathComponent("files")
    try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    for name in ["Q3 Report.pdf", "Invoice-4821.pdf"] {
        FileManager.default.createFile(atPath: files.appendingPathComponent(name).path, contents: Data())
    }
    let store = ClipStore(directory: dir, defaults: UserDefaults(suiteName: "pastry-shots-\(UUID().uuidString)")!)
    let now = Date()
    func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    // Oldest first: each add goes on top.
    let entries: [(ClipItem, Bool)] = [
        (ClipItem(kind: .text, text: "123 Baker Street, Springfield", date: ago(4320), sourceApp: "Contacts"), true),
        (ClipItem(kind: .text, text: "Thanks so much, talk soon! 🙌", date: ago(2900), sourceApp: "Mail"), true),
        (ClipItem(kind: .text, text: "Invoice #4790 (paid)", date: ago(1500), sourceApp: "Numbers"), false),
        (ClipItem(kind: .text, text: "Grocery list: flour, butter, apples, cinnamon, puff pastry", date: ago(600), sourceApp: "Notes"), false),
        (ClipItem(kind: .files, files: [files.appendingPathComponent("Q3 Report.pdf").path,
                                        files.appendingPathComponent("Invoice-4821.pdf").path], date: ago(240), sourceApp: "Finder"), false),
        (ClipItem(kind: .text, text: "Q3 summary: revenue up 18% quarter over quarter, led by new customers in Europe.", date: ago(95), sourceApp: "Pages"), false),
        (ClipItem(kind: .text, text: "let greeting = \"Hello, Pastry!\"", date: ago(41), sourceApp: "Xcode"), false),
        (ClipItem(kind: .text, text: "Meeting moved to 3:30 pm tomorrow", date: ago(18), sourceApp: "Messages"), false),
        (ClipItem(kind: .text, text: "Invoice #4821, due Nov 30: $1,240.00", date: ago(7), sourceApp: "Mail"), false),
        (ClipItem(kind: .text, text: "https://github.com/H3XY/Pastry", date: ago(2), sourceApp: "Safari"), false),
    ]
    for (item, pinned) in entries {
        store.add(item)
        if pinned { store.togglePin(store.items[0].id) }
    }
    if let png = try? Data(contentsOf: URL(fileURLWithPath: "Resources/AppIcon-1024.png")) {
        store.addImage(png: png, source: "Preview")
    }
    return store
}

/// Renders the real panel (400×480 pt) at 3× into a bitmap.
@MainActor
func renderPanel(store: ClipStore, query: String, selection: Int) -> NSBitmapImageRep {
    let model = PanelModel()
    model.axTrusted = true
    model.query = query
    let view = HistoryView(store: store, model: model, onPaste: { _ in }, onOpenAccessibility: {})
        .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 480)
    let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 400, height: 480),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.backgroundColor = .white
    window.contentView = host
    window.orderFrontRegardless()
    model.selection = selection
    // Let SwiftUI lay out and settle (onChange resets selection when the query changes).
    for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    model.selection = selection
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()

    let scale: CGFloat = 3
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(400 * scale), pixelsHigh: Int(480 * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    window.orderOut(nil)
    return rep
}

func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor, centerY: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: c, .paragraphStyle: p]
    let str = NSAttributedString(string: s, attributes: attrs)
    let h = str.boundingRect(with: NSSize(width: canvas.width - 300, height: 1000), options: .usesLineFragmentOrigin).height
    str.draw(with: NSRect(x: 150, y: centerY - h / 2, width: canvas.width - 300, height: h), options: .usesLineFragmentOrigin)
}

@MainActor
func screenshot(_ name: String, title: String, subtitle: String, store: ClipStore, query: String = "", selection: Int = 0) {
    let panel = renderPanel(store: store, query: query, selection: selection)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: color(0x9CCBFF), ending: color(0x4A6FD8))!.draw(in: NSRect(origin: .zero, size: canvas), angle: -90)
    drawText(title, size: 112, weight: .bold, color: .white, centerY: canvas.height - 200)
    drawText(subtitle, size: 54, weight: .medium, color: color(0xFFFFFF, 0.88), centerY: canvas.height - 330)

    // Panel: 1000×1200 px, rounded, with a soft shadow, like the real floating window.
    let frame = NSRect(x: (canvas.width - 1000) / 2, y: 90, width: 1000, height: 1200)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 46, yRadius: 46)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x0B1B4D, 0.45); shadow.shadowBlurRadius = 70; shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.set()
    NSColor.white.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    panel.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
    print("✓ \(outDir.path)/\(name).png")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let store = demoStore()
    screenshot("screenshot-1", title: "Everything you copy, one shortcut away",
               subtitle: "Press ⇧⌘V anywhere to bring back text, links, images and files.", store: store)
    screenshot("screenshot-2", title: "Find anything as you type",
               subtitle: "Search your whole history, then press ↩ to paste it right where you are.",
               store: store, query: "invoice")
    screenshot("screenshot-3", title: "Pin what you use all the time",
               subtitle: "Pinned items stay at the top. ⌘1–⌘9 paste the first nine instantly.",
               store: store, selection: 1)
}
