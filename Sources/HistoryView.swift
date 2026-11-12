import SwiftUI

@MainActor
final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var focusToken = 0
    @Published var axTrusted = true

    func visible(_ store: ClipStore) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.ordered.filter { $0.matches(q) }
    }
}

struct HistoryView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: PanelModel
    var onPaste: (ClipItem) -> Void
    var onOpenAccessibility: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.visible(store)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                        .foregroundStyle(.secondary)
                    if store.items.isEmpty {
                        Text("Copy something with ⌘C and it will show up here.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                ClipRow(item: item, index: idx, selected: idx == model.selection, store: store)
                                    .id(item.id)
                                    .onTapGesture { onPaste(item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) { sel in
                        if items.indices.contains(sel) { proxy.scrollTo(items[sel].id) }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                if model.axTrusted {
                    Text("↩ paste   ⇧↩ plain text   ⌘P pin   ⌘⌫ delete   esc")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    Button(action: onOpenAccessibility) {
                        Label("Allow Accessibility to auto-paste", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    .help("Without it, choosing an item copies it and you press ⌘V yourself.")
                }
                Spacer()
                Button("Clear") { store.clearUnpinned() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("Remove all unpinned items")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 400, height: 480)
        .background(.regularMaterial)
        .onChange(of: model.query) { _ in model.selection = 0 }
        .onReceive(model.$focusToken) { _ in
            DispatchQueue.main.async { searchFocused = true }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    @ObservedObject var store: ClipStore
    @State private var hovering = false

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var secondary: Color { selected ? .white.opacity(0.75) : .secondary }

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewText)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if item.pinned { Image(systemName: "pin.fill") }
                    if let app = item.sourceApp { Text(app); Text("·") }
                    Text(Self.relative.localizedString(for: item.date, relativeTo: Date()))
                }
                .font(.system(size: 10))
                .foregroundStyle(secondary)
            }

            if hovering {
                Button { store.togglePin(item.id) } label: {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.borderless)
                .help(item.pinned ? "Unpin" : "Pin (kept forever, shown at top)")
                Button { store.remove(item.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete")
            } else if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(secondary)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor : (hovering ? Color.primary.opacity(0.07) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .image:
            if let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").font(.system(size: 18))
            }
        case .files:
            if let first = item.files?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first)).resizable()
            } else {
                Image(systemName: "doc").font(.system(size: 18))
            }
        case .text:
            Image(systemName: looksLikeURL ? "link" : "text.alignleft")
                .font(.system(size: 15))
                .foregroundStyle(secondary)
        }
    }

    private var looksLikeURL: Bool {
        let t = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ")
    }
}
