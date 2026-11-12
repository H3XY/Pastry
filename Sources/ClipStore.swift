import AppKit
import CryptoKit

enum ClipKind: String, Codable {
    case text, image, files
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    var text: String?
    var imageFile: String?
    var imageHash: String?
    var imageSize: String?
    var files: [String]?
    var date = Date()
    var pinned = false
    var sourceApp: String?
    /// Formatting copied alongside the text, stored as files in `rich/` (nil when the copy was plain text).
    var rtfFile: String?
    var htmlFile: String?

    var isRich: Bool { rtfFile != nil || htmlFile != nil }

    func sameContent(as other: ClipItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imageHash == other.imageHash
        case .files: return files == other.files
        }
    }

    var previewText: String {
        switch kind {
        case .text:
            let raw = String((text ?? "").prefix(400))
            return raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        case .image:
            return "Image" + (imageSize.map { "  ·  \($0)" } ?? "")
        case .files:
            let names = (files ?? []).map { URL(fileURLWithPath: $0).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names.count) files: " + names.joined(separator: ", ")
        }
    }

    func matches(_ query: String) -> Bool {
        if query.isEmpty { return true }
        switch kind {
        case .text: return (text ?? "").localizedCaseInsensitiveContains(query)
        case .image: return "image".localizedCaseInsensitiveContains(query) || (sourceApp ?? "").localizedCaseInsensitiveContains(query)
        case .files: return (files ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

/// Formatting that came with a text copy.
struct RichData {
    var rtf: Data?
    var html: Data?
    var isEmpty: Bool { rtf == nil && html == nil }
}

@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    var maxItems: Int {
        get { let v = defaults.integer(forKey: "maxItems"); return v > 0 ? v : 200 }
        set { defaults.set(newValue, forKey: "maxItems"); trim(); save() }
    }

    let dir: URL
    let imagesDir: URL
    let richDir: URL
    private let file: URL
    private let defaults: UserDefaults
    private var saveWork: DispatchWorkItem?
    private let thumbCache = NSCache<NSString, NSImage>()

    /// `directory` and `defaults` are injectable so tests can use a throwaway location.
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = directory ?? base.appendingPathComponent("Pastry", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        richDir = dir.appendingPathComponent("rich", isDirectory: true)
        file = dir.appendingPathComponent("history.json")
        self.defaults = defaults
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: richDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Adding

    func add(_ new: ClipItem, rich: RichData? = nil) {
        var item: ClipItem
        if let i = items.firstIndex(where: { $0.sameContent(as: new) }) {
            item = items.remove(at: i)
            item.date = new.date
            if let app = new.sourceApp { item.sourceApp = app }
        } else {
            item = new
        }
        if item.kind == .text, let rich {
            // The latest copy decides the formatting.
            deleteRichFiles(of: item)
            item.rtfFile = nil
            item.htmlFile = nil
            if let rtf = rich.rtf { item.rtfFile = writeRich(rtf, name: "\(item.id.uuidString).rtf") }
            if let html = rich.html { item.htmlFile = writeRich(html, name: "\(item.id.uuidString).html") }
        }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func addImage(png: Data, source: String?) {
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if items.contains(where: { $0.kind == .image && $0.imageHash == hash }) {
            add(ClipItem(kind: .image, imageHash: hash, sourceApp: source))
            return
        }
        let name = "\(hash.prefix(24)).png"
        do { try png.write(to: imagesDir.appendingPathComponent(name), options: .atomic) } catch { return }
        var size: String?
        if let rep = NSBitmapImageRep(data: png) { size = "\(rep.pixelsWide)×\(rep.pixelsHigh)" }
        add(ClipItem(kind: .image, imageFile: name, imageHash: hash, imageSize: size, sourceApp: source))
    }

    // MARK: Editing

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        deleteFiles(of: items.remove(at: i))
        save()
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func bumpToTop(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.date = Date()
        items.insert(item, at: 0)
        save()
    }

    func clearUnpinned() {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        removed.forEach(deleteFiles)
        save()
    }

    /// Pinned items first, then most recent.
    var ordered: [ClipItem] {
        items.filter(\.pinned) + items.filter { !$0.pinned }
    }

    // MARK: Pasteboard

    func richData(for item: ClipItem) -> RichData {
        RichData(rtf: item.rtfFile.flatMap { try? Data(contentsOf: richDir.appendingPathComponent($0)) },
                 html: item.htmlFile.flatMap { try? Data(contentsOf: richDir.appendingPathComponent($0)) })
    }

    /// Puts an item back on the pasteboard. `plainText` drops any formatting.
    func write(_ item: ClipItem, to pb: NSPasteboard = .general, plainText: Bool = false) {
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
            if !plainText {
                let rich = richData(for: item)
                if let rtf = rich.rtf { pb.setData(rtf, forType: .rtf) }
                if let html = rich.html { pb.setData(html, forType: .html) }
            }
        case .image:
            guard let name = item.imageFile,
                  let png = try? Data(contentsOf: imagesDir.appendingPathComponent(name)) else { return }
            pb.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        case .files:
            let urls = (item.files ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        }
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let name = item.imageFile else { return nil }
        if let cached = thumbCache.object(forKey: name as NSString) { return cached }
        guard let img = NSImage(contentsOf: imagesDir.appendingPathComponent(name)) else { return nil }
        let side: CGFloat = 80
        let scale = min(side / max(img.size.width, 1), side / max(img.size.height, 1), 1)
        let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        thumbCache.setObject(thumb, forKey: name as NSString)
        return thumb
    }

    // MARK: Persistence

    private func trim() {
        var unpinned = items.filter { !$0.pinned }.count
        while unpinned > maxItems, let i = items.lastIndex(where: { !$0.pinned }) {
            deleteFiles(of: items.remove(at: i))
            unpinned -= 1
        }
    }

    private func writeRich(_ data: Data, name: String) -> String? {
        (try? data.write(to: richDir.appendingPathComponent(name), options: .atomic)) == nil ? nil : name
    }

    private func deleteRichFiles(of item: ClipItem) {
        for name in [item.rtfFile, item.htmlFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: richDir.appendingPathComponent(name))
        }
    }

    /// Call only after `item` has been removed from `items`.
    private func deleteFiles(of item: ClipItem) {
        deleteRichFiles(of: item)
        guard let name = item.imageFile else { return }
        // Only delete if no other item references the same file.
        if items.contains(where: { $0.imageFile == name }) { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(name))
        thumbCache.removeObject(forKey: name as NSString)
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded
    }

    func save() {
        saveWork?.cancel()
        let snapshot = items
        let target = file
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: target, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: file, options: .atomic) }
    }
}
