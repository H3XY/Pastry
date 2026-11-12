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

@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    var maxItems: Int {
        get { let v = UserDefaults.standard.integer(forKey: "maxItems"); return v > 0 ? v : 200 }
        set { UserDefaults.standard.set(newValue, forKey: "maxItems"); trim(); save() }
    }

    let dir: URL
    let imagesDir: URL
    private let file: URL
    private var saveWork: DispatchWorkItem?
    private let thumbCache = NSCache<NSString, NSImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Pastry", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        file = dir.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Adding

    func add(_ new: ClipItem) {
        if let i = items.firstIndex(where: { $0.sameContent(as: new) }) {
            var existing = items.remove(at: i)
            existing.date = new.date
            if let app = new.sourceApp { existing.sourceApp = app }
            items.insert(existing, at: 0)
        } else {
            items.insert(new, at: 0)
        }
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
        items.filter { !$0.pinned }.forEach(deleteFiles)
        items.removeAll { !$0.pinned }
        save()
    }

    /// Pinned items first, then most recent.
    var ordered: [ClipItem] {
        items.filter(\.pinned) + items.filter { !$0.pinned }
    }

    // MARK: Pasteboard

    func write(_ item: ClipItem, to pb: NSPasteboard = .general) {
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
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

    private func deleteFiles(of item: ClipItem) {
        guard let name = item.imageFile else { return }
        // Only delete if no other item references the same file.
        if items.contains(where: { $0.imageFile == name && $0.id != item.id }) { return }
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
