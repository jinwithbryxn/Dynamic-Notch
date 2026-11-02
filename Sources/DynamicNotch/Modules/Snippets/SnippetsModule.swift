import AppKit
import SwiftUI

/// 재사용 글자 하나
struct ClipSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
    var created = Date()
    var updated = Date()
}

/// 스니펫 저장소: `~/Library/Application Support/<번들 ID>/Snippets/snippets.json` (소유자 전용).
/// 본 앱과 설정 도우미가 같은 파일을 쓰고, 바꾸면 ModuleDefaults "revision"으로 서로 알린다.
final class ClipSnippetStore: ObservableObject {
    @Published private(set) var snippets: [ClipSnippet] = []
    let url: URL
    /// 저장할 때 다른 프로세스에 알릴지 (자체 검사용 임시 저장소는 알리지 않음)
    var announces = true

    init(url: URL = ClipSnippetStore.defaultURL()) {
        self.url = url
    }

    static func defaultURL() -> URL {
        if AppSettings.isHelper, let custom = ProcessInfo.processInfo.environment["DMN_SNIPPETS_FILE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dynamicnotch.app", isDirectory: true)
            .appendingPathComponent("Snippets", isDirectory: true).appendingPathComponent("snippets.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ClipSnippet].self, from: data) else { snippets = []; return }
        snippets = list
    }

    /// 사용자가 바꿀 때만 쓴다 (자동 쓰기 없음)
    private func save() {
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: url, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        if announces { ModuleDefaults(module: "snippets").set(Date().timeIntervalSince1970, "revision") }
    }

    @discardableResult
    func add(name: String, text: String) -> ClipSnippet {
        let s = ClipSnippet(name: name, text: text)
        snippets.insert(s, at: 0)
        save()
        return s
    }

    func update(_ id: UUID, name: String, text: String) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[i].name = name
        snippets[i].text = text
        snippets[i].updated = Date()
        save()
    }

    /// 지운 스니펫과 자리 (되돌리기용)
    func delete(_ id: UUID) -> (ClipSnippet, Int)? {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return nil }
        let s = snippets.remove(at: i)
        save()
        return (s, i)
    }

    func restore(_ s: ClipSnippet, at index: Int) {
        guard !snippets.contains(where: { $0.id == s.id }) else { return }
        snippets.insert(s, at: min(index, snippets.count))
        save()
    }

    /// 이름 앞부분 > 이름 포함 > 내용 포함 순
    func search(_ query: String) -> [ClipSnippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return snippets }
        func rank(_ s: ClipSnippet) -> Int? {
            let name = s.name.lowercased(), lq = q.lowercased()
            if name.hasPrefix(lq) { return 0 }
            if s.name.localizedStandardContains(q) { return 1 }
            if s.text.localizedStandardContains(q) { return 2 }
            return nil
        }
        return snippets.compactMap { s in rank(s).map { (s, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// 지금 클립보드 글자로 이름을 짓는다 (첫 줄 앞부분)
    static func suggestedName(_ text: String) -> String {
        let line = ClipItem.firstLine(text)
        return line.count > 32 ? String(line.prefix(32)) + "…" : line
    }
}

/// 텍스트 스니펫: 저장해 둔 글자를 팔레트에서 이름 몇 글자로 찾아 직전 앱에 붙여넣는다.
/// 붙여넣기는 임시(transient) 표시라 클립보드 기록에 남지 않고, 끝나면 원래 클립보드를 되돌린다.
final class SnippetsModule: NotchModule {
    let id = "snippets"
    var title: String { T("스니펫", "Snippets") }
    let symbol = "text.badge.plus"
    /// 직전 앱에 붙여넣기는 손쉬운 사용 권한을 쓰므로 기본은 끔
    let enabledByDefault = false

    let store = ClipSnippetStore()
    let undo = SnippetUndo()
    /// 탭 키보드 처리 (탭이 보일 때만)
    let tabKeys = ClipKeyMonitor()
    private(set) var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        store.load()
    }

    func stop() {
        tabKeys.remove()
        context = nil
    }

    func settingsChanged() { store.load() }

    func tabView() -> AnyView? { AnyView(SnippetsTab(module: self, store: store, undo: undo)) }
    var tabContentSize: CGSize { CGSize(width: 540, height: 280) }
    func settingsView() -> AnyView? { AnyView(SnippetsSettingsView()) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "snippets.saveClipboard", title: T("클립보드를 스니펫으로 저장", "Save Clipboard as Snippet"),
                          symbol: "square.and.arrow.down", keywords: ["snippet", "스니펫", "save", "저장", "clipboard", "클립보드"],
                          run: { [weak self] in self?.saveClipboard() }),
            PaletteAction(id: "snippets.open", title: T("스니펫 열기", "Open Snippets"), symbol: symbol,
                          keywords: ["snippet", "스니펫", "text", "글자"], run: { [weak self] in self?.context?.openTab("snippets") }),
        ]
    }

    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard context != nil, !q.isEmpty else { return [] }
        return store.search(q).prefix(6).map { s in
            PaletteAction(id: "snippets.\(s.id.uuidString)", title: s.name,
                          subtitle: T("스니펫 · ", "Snippet · ") + ClipItem.firstLine(s.text),
                          symbol: symbol, run: { [weak self] in self?.paste(s) })
        }
    }

    /// 직전 앱에 붙여넣는다. 권한이 없으면 클립보드에 남기고 알린다.
    func paste(_ s: ClipSnippet) {
        context?.collapse()
        ClipPasteboard.pasteOnce(s.text, waitForModifiers: false) { [weak self] ok in
            guard !ok else { return }
            self?.context?.notice(T("스니펫을 클립보드에 넣음", "Snippet is on the clipboard"),
                                  T("손쉬운 사용 권한이 없어 ⌘V로 붙여넣기", "No Accessibility permission · press ⌘V"),
                                  symbol: "text.badge.plus",
                                  actions: [ActivityAction(id: "snippets.ax", title: T("권한 열기", "Grant access")) { ClipboardModule.requestAccessibility() }])
        }
    }

    /// 지금 클립보드 글자를 스니펫으로 저장한다
    @discardableResult
    func saveClipboard() -> ClipSnippet? {
        guard let text = ClipPasteboard.plainText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            context?.notice(T("저장할 글자가 없음", "Nothing to save"), T("지금 클립보드에 글자가 없음", "The clipboard has no text"), symbol: "text.badge.plus", duration: 2)
            return nil
        }
        let s = store.add(name: ClipSnippetStore.suggestedName(text), text: text)
        context?.notice(T("스니펫으로 저장함", "Saved as a snippet"), s.name, symbol: "text.badge.plus", tab: id, duration: 2)
        return s
    }

    func selfTest() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            out.append("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-snippets-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let s = ClipSnippetStore(url: tmp.appendingPathComponent("snippets.json"))
        s.announces = false
        let addr = s.add(name: "Address", text: "1 Infinite Loop, Cupertino")
        s.add(name: "Reply thanks", text: "Thanks for the address!")
        s.add(name: "코드 블록", text: "```swift\n```")
        check("search name prefix first", s.search("addr").first?.id == addr.id, s.search("addr").map(\.name).joined(separator: ","))
        check("search text", s.search("cupertino").count == 1)
        check("search korean", s.search("코드").first?.name == "코드 블록")
        let removed = s.delete(addr.id)
        check("delete", s.snippets.count == 2)
        if let (snip, i) = removed { s.restore(snip, at: i) }
        check("undo delete", s.snippets.contains { $0.id == addr.id })
        let reload = ClipSnippetStore(url: s.url)
        reload.load()
        check("reload file", reload.snippets.count == 3)
        let perms = (try? FileManager.default.attributesOfItem(atPath: s.url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        check("file 0600", perms == 0o600, String(perms, radix: 8))
        check("suggested name", ClipSnippetStore.suggestedName("  hello\nworld") == "hello")
        out.append("snippets file: \(ClipSnippetStore.defaultURL().path)")
        out.append("accessibility trusted: \(AXIsProcessTrusted()) (\(AXIsProcessTrusted() ? "pastes with ⌘V" : "copy only, press ⌘V"))")
        return out
    }
}

/// 방금 지운 스니펫 (몇 초 동안 되돌리기)
final class SnippetUndo: ObservableObject {
    @Published private(set) var last: (snippet: ClipSnippet, index: Int)?
    private var work: DispatchWorkItem?

    func remember(_ s: ClipSnippet, _ i: Int) {
        last = (s, i)
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.last = nil }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    func clear() { work?.cancel(); last = nil }
}
