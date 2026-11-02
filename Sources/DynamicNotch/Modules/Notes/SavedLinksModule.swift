import AppKit
import SwiftUI

/// 저장 링크: 웹 페이지 주소를 저장해 탭과 명령 팔레트에서 연다.
/// 페이지 제목을 가져오려고 인터넷에 접속하지 않는다 (제목은 직접 적거나 주소의 호스트 이름을 쓴다).
final class SavedLinksModule: NotchModule {
    let id = "links"
    var title: String { T("저장 링크", "Saved Links") }
    let symbol = "link"
    let enabledByDefault = false

    let model = SLinksModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        model.load()
    }

    func stop() { context = nil }

    func tabView() -> AnyView? { AnyView(SLinksTab(model: model, focusInput: { [weak self] in self?.context?.focusInput() })) }
    var tabContentSize: CGSize { CGSize(width: 440, height: 230) }

    func paletteActions() -> [PaletteAction] {
        model.items.prefix(30).map { link in
            PaletteAction(id: "links.\(link.id.uuidString)", title: link.title, subtitle: link.url.host ?? link.url.absoluteString,
                          symbol: "link", keywords: ["link", "링크", "bookmark", "북마크", link.url.absoluteString]) {
                NSWorkspace.shared.open(link.url)
            }
        }
    }

    /// "링크 저장 https://…", "save link https://…"
    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let p = ["링크 저장 ", "save link "].first(where: { q.lowercased().hasPrefix($0) }) else { return [] }
        let text = String(q.dropFirst(p.count))
        guard let parsed = SLinksModel.parse(text) else { return [] }
        return [PaletteAction(id: "links.add", title: T("링크 저장: \(parsed.title)", "Save Link: \(parsed.title)"),
                              subtitle: parsed.url.absoluteString, symbol: "link.badge.plus") { [weak self] in
            _ = self?.model.add(text)
        }]
    }

    func settingsView() -> AnyView? {
        AnyView(PIMSettingsGroup(title: T("저장 링크", "Saved Links")) {
            Text(T("저장한 웹 페이지는 탭과 명령 팔레트에 나타납니다. 이 Mac에만 저장하며 페이지에 접속해 제목을 가져오지 않습니다. '제목 https://주소' 형식으로 입력하면 제목을 붙일 수 있습니다.",
                   "Saved pages appear in the tab and the command palette. Stored only on this Mac; pages are never fetched for titles. Type 'Title https://address' to name a link."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        })
    }

    func selfTest() -> [String] {
        let probe = SLinksModel()
        probe.load()
        let checks = ["Docs https://developer.apple.com/documentation", "example.com/path", "not a link", "ftp://x.y"]
            .map { "\($0) → \(SLinksModel.parse($0).map { "\($0.title) | \($0.url.absoluteString)" } ?? "rejected")" }
        return ["stored links: \(probe.items.count)"] + checks
    }
}

struct SavedLink: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: URL
    var added: Date
}

final class SLinksModel: ObservableObject {
    @Published private(set) var items: [SavedLink] = []
    @Published var draft = ""
    @Published private(set) var removed: SavedLink?
    @Published var message: String?
    private var undoWork: DispatchWorkItem?

    func load() { items = PIMFiles.read([SavedLink].self, "links.json") ?? [] }
    private func save() { PIMFiles.write(items, "links.json") }

    /// "제목 https://주소" 또는 "주소"만. http(s)만 받는다.
    static func parse(_ raw: String) -> (title: String, url: URL)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var parts = text.split(separator: " ").map(String.init)
        guard var last = parts.popLast() else { return nil }
        if !last.contains("://") {
            guard last.contains("."), !last.contains("@") else { return nil }
            last = "https://" + last
        }
        guard let url = URL(string: last), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") else { return nil }
        let title = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? host.replacingOccurrences(of: "www.", with: "") : title, url)
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        guard let p = Self.parse(raw) else { message = T("http(s) 주소를 넣으세요", "Enter an http(s) address"); return false }
        if items.contains(where: { $0.url == p.url }) { message = T("이미 저장한 주소", "Already saved"); return false }
        items.insert(SavedLink(id: UUID(), title: p.title, url: p.url, added: Date()), at: 0)
        save()
        message = nil
        return true
    }

    /// 클립보드의 주소를 넣는다 (사용자가 누를 때만 클립보드를 읽음)
    func addFromClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string) else { message = T("클립보드에 주소가 없음", "No address on the clipboard"); return }
        add(s)
    }

    func remove(_ link: SavedLink) {
        items.removeAll { $0.id == link.id }
        removed = link
        save()
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.removed = nil }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func undoRemove() {
        guard let r = removed else { return }
        items.insert(r, at: 0)
        removed = nil
        save()
    }
}

private struct SLinksTab: View {
    @ObservedObject var model: SLinksModel
    let focusInput: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                TextField(T("주소 또는 '제목 https://…' 입력 후 Return", "Address or 'Title https://…', then Return"), text: $model.draft)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { if model.add(model.draft) { model.draft = "" } }
                    .accessibilityLabel(T("링크 입력", "Link"))
                Button { model.addFromClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(PIMPillStyle())
                    .help(T("클립보드의 주소 저장", "Save the address on the clipboard"))
                    .accessibilityLabel(T("클립보드에서 저장", "Save from clipboard"))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            if let r = model.removed {
                HStack {
                    Text(T("'\(r.title)' 뺌", "Removed '\(r.title)'")).font(.system(size: 10.5)).lineLimit(1)
                    Spacer()
                    Button(T("되돌리기", "Undo")) { model.undoRemove() }.buttonStyle(PIMPillStyle())
                }
            } else if let m = model.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange)
            }
            if model.items.isEmpty {
                PIMEmptyState(symbol: "link", title: T("저장한 링크 없음", "No saved links"),
                              detail: T("저장한 페이지는 명령 팔레트에서도 바로 열 수 있음", "Saved pages also open from the command palette"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.items) { link in
                            Button { NSWorkspace.shared.open(link.url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(link.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(link.url.absoluteString).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(link.url.absoluteString)
                            .contextMenu {
                                Button(T("주소 복사", "Copy Address")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
                                }
                                Button(T("빼기", "Remove")) { model.remove(link) }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }
}
