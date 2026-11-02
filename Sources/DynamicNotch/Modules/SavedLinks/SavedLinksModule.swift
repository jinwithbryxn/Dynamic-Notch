import AppKit
import SwiftUI

/// 저장 링크: 지금 보던 브라우저 페이지(사용자가 누를 때 AppleScript로 주소를 읽음)나 붙여넣은 링크를 저장해
/// 탭과 명령 팔레트에서 연다. 자동화 권한이 필요할 수 있어 기본 꺼짐.
final class SavedLinksModule: NotchModule {
    let id = "savedlinks"
    var title: String { T("저장 링크", "Saved Links") }
    let symbol = "bookmark"
    var enabledByDefault: Bool { false }

    struct Link: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var url: String
        var title: String
        var added = Date()
    }

    fileprivate var context: ModuleContext?
    private let key = "module.savedlinks.items"
    private var reader: LaunchProcess?

    var links: [Link] {
        guard let d = UserDefaults.standard.data(forKey: key), let l = try? JSONDecoder().decode([Link].self, from: d) else { return [] }
        return l
    }
    func setLinks(_ l: [Link]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }

    func start(context: ModuleContext) { self.context = context }
    func stop() {
        reader?.cancel()
        reader = nil
        context = nil
    }

    func tabView() -> AnyView? { AnyView(SavedLinksTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 230) }

    @discardableResult
    func save(url: URL, title: String?) -> Bool {
        var l = links
        guard !l.contains(where: { $0.url == url.absoluteString }) else { return false }
        let t = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? (url.host ?? url.absoluteString)
        l.insert(Link(url: url.absoluteString, title: String(t.prefix(200))), at: 0)
        setLinks(l)
        return true
    }

    func remove(_ link: Link) { setLinks(links.filter { $0.id != link.id }) }
    func restore(_ link: Link, at index: Int) {
        var l = links
        l.insert(link, at: min(index, l.count))
        setLinks(l)
    }

    func open(_ link: Link) {
        guard let u = URL(string: link.url) else { return }
        NSWorkspace.shared.open(u)
        context?.collapse()
    }

    // MARK: 브라우저 현재 페이지

    /// 지원 브라우저: 번들 ID → AppleScript (주소와 제목을 줄바꿈으로 돌려준다)
    static let browsers: [String: (name: String, script: String)] = {
        func chromium(_ app: String) -> String {
            "tell application \"\(app)\" to if (count of windows) > 0 then return (URL of active tab of front window) & linefeed & (title of active tab of front window)"
        }
        return [
            "com.apple.Safari": ("Safari", "tell application \"Safari\" to if (count of windows) > 0 then return (URL of current tab of front window) & linefeed & (name of current tab of front window)"),
            "com.google.Chrome": ("Google Chrome", chromium("Google Chrome")),
            "company.thebrowser.Browser": ("Arc", chromium("Arc")),
            "com.microsoft.edgemac": ("Microsoft Edge", chromium("Microsoft Edge")),
            "com.brave.Browser": ("Brave Browser", chromium("Brave Browser")),
            "com.vivaldi.Vivaldi": ("Vivaldi", chromium("Vivaldi")),
        ]
    }()

    /// 대상 브라우저: 노치를 열기 전 앱이 브라우저면 그것, 아니면 실행 중인 첫 지원 브라우저
    static func targetBrowser() -> (bundleID: String, name: String, script: String)? {
        if let prev = ModuleServices.previousApp?.bundleIdentifier, let b = browsers[prev] { return (prev, b.name, b.script) }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let b = browsers[id] { return (id, b.name, b.script) }
        }
        return nil
    }

    /// 사용자가 누른 경우에만: 브라우저에 현재 탭 주소를 물어 저장한다 (처음엔 macOS가 자동화 권한을 묻는다)
    func saveCurrentPage(done: ((String) -> Void)? = nil) {
        guard let b = Self.targetBrowser() else {
            let msg = T("실행 중인 지원 브라우저가 없음 (Safari, Chrome, Arc, Edge, Brave, Vivaldi)", "No supported browser is running (Safari, Chrome, Arc, Edge, Brave, Vivaldi)")
            done?(msg)
            return
        }
        reader?.cancel()
        let p = LaunchProcess()
        reader = p
        p.run("/usr/bin/osascript", ["-e", b.script], timeout: 15) { [weak self] r in
            guard let self else { return }
            self.reader = nil
            let lines = r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard r.status == 0, let first = lines.first, let url = URL(string: first), let scheme = url.scheme, scheme.hasPrefix("http") else {
                let denied = r.err.contains("-1743") || r.err.lowercased().contains("not authorized")
                done?(denied ? T("\(b.name) 자동화 권한이 없음 · 시스템 설정 > 개인정보 보호 > 자동화에서 허용", "No automation access to \(b.name) · allow it in System Settings > Privacy > Automation")
                             : T("\(b.name)에서 웹 페이지 주소를 읽지 못함", "Could not read a web page address from \(b.name)"))
                return
            }
            let title = lines.dropFirst().joined(separator: " ")
            let added = self.save(url: url, title: title)
            done?(added ? T("저장함: ", "Saved: ") + (title.isEmpty ? (url.host ?? first) : title) : T("이미 저장된 링크", "Already saved"))
        }
    }

    func paletteActions() -> [PaletteAction] {
        var out = [PaletteAction(id: "savedlinks.saveCurrent", title: T("현재 페이지 저장", "Save current page"), symbol: "bookmark.fill",
                                 keywords: ["save", "link", "bookmark", "저장", "링크", "북마크"]) { [weak self] in
            self?.saveCurrentPage { msg in self?.context?.notice(T("저장 링크", "Saved Links"), msg, symbol: "bookmark") }
        }]
        out += links.map { l in
            PaletteAction(id: "savedlinks.\(l.id)", title: l.title, subtitle: URL(string: l.url)?.host ?? l.url, symbol: symbol,
                          keywords: [l.url, "link", "링크"]) { [weak self] in self?.open(l) }
        }
        return out
    }

    func selfTest() -> [String] {
        var out = ["saved links: \(links.count)"]
        if let b = Self.targetBrowser() { out.append("target browser (not queried in self test): \(b.name)") }
        else { out.append("no supported browser running -> save button shows a hint") }
        out.append("supported: \(Self.browsers.values.map(\.name).sorted().joined(separator: ", "))")
        out.append("paste parse: \(LaunchSystem.webURL(from: "example.com/a?b=1")?.absoluteString ?? "nil"), \(LaunchSystem.webURL(from: "not a link") == nil ? "plain text rejected" : "FAIL")")
        out.append("AppleScript run in self test: no")
        return out
    }
}

private struct SavedLinksTab: View {
    let module: SavedLinksModule
    @State private var links: [SavedLinksModule.Link] = []
    @State private var text = ""
    @State private var status = ""
    @State private var undo: (SavedLinksModule.Link, Int)?
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LaunchField(placeholder: T("링크 붙여넣기 후 Return", "Paste a link and press Return"), text: $text, symbol: "link", focus: $focused) { addPasted() }
                LaunchChip(title: busy ? T("읽는 중…", "Reading…") : T("현재 페이지 저장", "Save current page"), symbol: "safari") {
                    busy = true
                    module.saveCurrentPage { msg in
                        busy = false
                        status = msg
                        links = module.links
                    }
                }
                .disabled(busy)
            }
            if let u = undo {
                HStack {
                    Text(T("뺌: ", "Removed: ") + u.0.title).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    LaunchChip(title: T("되돌리기", "Undo")) { module.restore(u.0, at: u.1); links = module.links; undo = nil }
                }
            } else if !status.isEmpty {
                Text(status).font(.system(size: 11)).foregroundStyle(LaunchUI.secondary).lineLimit(1)
            }
            if links.isEmpty {
                LaunchUnsupportedView(title: T("저장한 링크 없음", "No saved links"),
                                      reason: T("브라우저에서 보던 페이지를 저장하거나 링크를 붙여넣기", "Save the page open in your browser or paste a link"),
                                      symbol: "bookmark")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(links) { l in row(l) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { links = module.links }
    }

    private func row(_ l: SavedLinksModule.Link) -> some View {
        HStack(spacing: 8) {
            Button { module.open(l) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(LaunchUI.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(l.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        Text(URL(string: l.url)?.host ?? l.url).font(.system(size: 10.5)).foregroundStyle(LaunchUI.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(l.url)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(l.url, forType: .string)
                status = T("주소 복사함", "Address copied")
            } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                .buttonStyle(.plain).help(T("주소 복사", "Copy address")).accessibilityLabel(T("주소 복사", "Copy address"))
            Button {
                let i = links.firstIndex(of: l) ?? 0
                module.remove(l)
                links = module.links
                undo = (l, i)
            } label: { Image(systemName: "minus.circle").font(.system(size: 11)) }
                .buttonStyle(.plain).help(T("목록에서 빼기", "Remove")).accessibilityLabel(T("빼기", "Remove"))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
    }

    private func addPasted() {
        guard let u = LaunchSystem.webURL(from: text) else { status = T("웹 주소가 아님", "Not a web address"); return }
        status = module.save(url: u, title: nil) ? T("저장함", "Saved") : T("이미 저장된 링크", "Already saved")
        text = ""
        links = module.links
    }
}
