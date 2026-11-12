// Pastry's tests. Run with ./test.sh (no Xcode project needed).
// Each test uses a throwaway history folder and UserDefaults suite, so your real history is never touched.
import AppKit

var failures = 0
var passed = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() { passed += 1 } else { failures += 1; print("  ✗ line \(line): \(message)") }
}

@MainActor
func withStore(_ body: (ClipStore, URL) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pastry-tests-\(UUID().uuidString)")
    let suite = "pastry-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }
    body(ClipStore(directory: dir, defaults: defaults), dir)
}

func text(_ s: String, pinned: Bool = false) -> ClipItem {
    ClipItem(kind: .text, text: s, pinned: pinned)
}

func test(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

MainActor.assumeIsolated {
    test("New copies go to the top") {
        withStore { store, _ in
            store.add(text("one")); store.add(text("two"))
            expect(store.items.map(\.text) == ["two", "one"], "newest first")
        }
    }

    test("Copying the same text again moves it to the top instead of duplicating") {
        withStore { store, _ in
            store.add(text("a")); store.add(text("b")); store.add(text("a"))
            expect(store.items.map(\.text) == ["a", "b"], "deduplicated and bumped")
        }
    }

    test("Trimming drops the oldest unpinned items but never pinned ones") {
        withStore { store, _ in
            store.maxItems = 3
            store.add(text("keep me", pinned: true))
            for i in 1...5 { store.add(text("item \(i)")) }
            expect(store.items.filter { !$0.pinned }.count == 3, "3 unpinned kept")
            expect(store.items.contains { $0.text == "keep me" }, "pinned survives")
            expect(!store.items.contains { $0.text == "item 1" }, "oldest dropped")
        }
    }

    test("Clear keeps pinned items") {
        withStore { store, _ in
            store.add(text("pinned", pinned: true)); store.add(text("loose"))
            store.clearUnpinned()
            expect(store.items.map(\.text) == ["pinned"], "only pinned left")
        }
    }

    test("Pinned items are listed first") {
        withStore { store, _ in
            store.add(text("old pinned", pinned: true)); store.add(text("new"))
            expect(store.ordered.first?.text == "old pinned", "pinned before newer items")
        }
    }

    test("Pin, unpin and delete") {
        withStore { store, _ in
            store.add(text("x"))
            let id = store.items[0].id
            store.togglePin(id); expect(store.items[0].pinned, "pinned")
            store.togglePin(id); expect(!store.items[0].pinned, "unpinned")
            store.remove(id); expect(store.items.isEmpty, "deleted")
        }
    }

    test("History is saved and reloaded") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pastry-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = ClipStore(directory: dir)
        first.add(text("remember me", pinned: true))
        first.saveNow()
        let second = ClipStore(directory: dir)
        expect(second.items.first?.text == "remember me" && second.items.first?.pinned == true, "reloaded with pin")
    }

    test("Formatting is stored, restored, and can be dropped") {
        withStore { store, _ in
            let rtf = Data("{\\rtf1 {\\b bold}}".utf8), html = Data("<b>bold</b>".utf8)
            store.add(text("bold"), rich: RichData(rtf: rtf, html: html))
            let item = store.items[0]
            expect(item.isRich, "marked as rich")
            expect(store.richData(for: item).rtf == rtf, "RTF round-trips")

            let pb = NSPasteboard(name: NSPasteboard.Name("pastry-tests-\(UUID().uuidString)"))
            defer { pb.releaseGlobally() }
            store.write(item, to: pb)
            expect(pb.data(forType: .rtf) == rtf && pb.data(forType: .html) == html, "pasted with formatting")
            store.write(item, to: pb, plainText: true)
            expect(pb.string(forType: .string) == "bold" && pb.data(forType: .rtf) == nil, "plain text drops formatting")
        }
    }

    test("Recopying the same text as plain text clears old formatting files") {
        withStore { store, dir in
            store.add(text("t"), rich: RichData(rtf: Data("{\\rtf1 t}".utf8), html: nil))
            store.add(text("t"), rich: RichData())
            expect(!store.items[0].isRich, "no longer rich")
            let left = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("rich").path)) ?? []
            expect(left.isEmpty, "rich file deleted")
        }
    }

    test("Images with identical pixels are stored once") {
        withStore { store, dir in
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = rep.representation(using: .png, properties: [:])!
            store.addImage(png: png, source: nil); store.addImage(png: png, source: nil)
            expect(store.items.count == 1 && store.items[0].imageSize == "4×3", "one image, size recorded")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("images").path)) ?? []
            expect(files.count == 1, "one file on disk")
            store.remove(store.items[0].id)
            let after = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("images").path)) ?? []
            expect(after.isEmpty, "file removed with item")
        }
    }

    test("Search matches text, file names and images") {
        expect(text("Hello World").matches("world"), "case-insensitive text")
        expect(!text("Hello").matches("bye"), "non-match")
        expect(ClipItem(kind: .files, files: ["/tmp/Report.pdf"]).matches("report"), "file name")
        expect(ClipItem(kind: .image).matches("image"), "images match 'image'")
        expect(text("anything").matches(""), "empty query matches all")
    }

    test("Previews collapse whitespace") {
        expect(text("a\n\n  b\tc").previewText == "a b c", "collapsed")
        expect(ClipItem(kind: .files, files: ["/x/a.txt", "/x/b.txt"]).previewText == "2 files: a.txt, b.txt", "files")
    }
}

test("Version comparison") {
    expect(UpdateChecker.isNewer("v1.1.0", than: "1.0.0"), "minor bump")
    expect(UpdateChecker.isNewer("v2.0", than: "1.9.9"), "major bump")
    expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"), "numeric, not alphabetical")
    expect(!UpdateChecker.isNewer("v1.0.0", than: "1.0.0"), "same version")
    expect(!UpdateChecker.isNewer("v1.0", than: "1.0.0"), "missing parts count as zero")
    expect(!UpdateChecker.isNewer("v0.9.9", than: "1.0.0"), "older")
}

test("Custom shortcut labels and rules") {
    typealias M = HotkeyPreset.Mods
    expect(HotkeyPreset.label([.command, .shift, .control, .option], key: "K") == "⌃⌥⇧⌘K", "Apple's symbol order")
    expect(HotkeyPreset.isAllowed([.command]), "⌘ allowed")
    expect(HotkeyPreset.isAllowed([.control, .shift]), "⌃⇧ allowed")
    expect(!HotkeyPreset.isAllowed([.shift]), "⇧ alone rejected")
    expect(!HotkeyPreset.isAllowed([]), "no modifiers rejected")
    expect(HotkeyPreset.carbonModifiers([.command, .shift]) == HotkeyPreset.all[0].modifiers, "matches ⇧⌘ preset")
    expect(HotkeyPreset.keyName(keyCode: 49, characters: " ") == "Space", "space key")
    expect(HotkeyPreset.keyName(keyCode: 9, characters: "v") == "V", "letters upper-cased")
}

test("Knowing when Pastry is already in Applications") {
    let home = "/Users/test"
    expect(AppMover.isInApplications("/Applications/Pastry.app", home: home), "system Applications")
    expect(AppMover.isInApplications("/Users/test/Applications/Pastry.app", home: home), "user Applications")
    expect(AppMover.isInApplications("/Applications/Utilities/Pastry.app", home: home), "subfolder")
    expect(!AppMover.isInApplications("/Users/test/Downloads/Pastry.app", home: home), "Downloads")
    expect(!AppMover.isInApplications("/Applications Backup/Pastry.app", home: home), "look-alike folder")
    expect(!AppMover.isInApplications("/Users/test/Applications/../Downloads/Pastry.app", home: home), "path tricks")
}

test("Item ages read naturally") {
    MainActor.assumeIsolated {
        let now = Date()
        expect(ClipRow.age(of: now.addingTimeInterval(0.3), now: now) == "now", "a hair in the future is now")
        expect(ClipRow.age(of: now.addingTimeInterval(-2), now: now) == "now", "2 seconds ago is now")
        expect(ClipRow.age(of: now.addingTimeInterval(-120), now: now).contains("2"), "2 minutes ago")
    }
}

print("\n\(passed) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
