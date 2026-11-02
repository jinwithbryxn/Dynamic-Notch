import AppKit
import SwiftUI

/// 검색 엔진 하나. url의 %s 자리에 검색어가 들어간다.
struct QuickSearchEngine: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var keyword: String
    var builtIn = false

    func searchURL(_ query: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: url.replacingOccurrences(of: "%s", with: q))
    }

    static let builtIns: [QuickSearchEngine] = [
        .init(id: "google", name: "Google", url: "https://www.google.com/search?q=%s", keyword: "g", builtIn: true),
        .init(id: "duckduckgo", name: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s", keyword: "d", builtIn: true),
        .init(id: "bing", name: "Bing", url: "https://www.bing.com/search?q=%s", keyword: "b", builtIn: true),
        .init(id: "perplexity", name: "Perplexity", url: "https://www.perplexity.ai/search?q=%s", keyword: "p", builtIn: true),
        .init(id: "youtube", name: "YouTube", url: "https://www.youtube.com/results?search_query=%s", keyword: "yt", builtIn: true),
        .init(id: "github", name: "GitHub", url: "https://github.com/search?q=%s", keyword: "gh", builtIn: true),
        .init(id: "wikipedia", name: "Wikipedia",
              url: T("https://ko.wikipedia.org/w/index.php?search=%s", "https://en.wikipedia.org/w/index.php?search=%s"), keyword: "w", builtIn: true),
        .init(id: "naver", name: "Naver", url: "https://search.naver.com/search.naver?query=%s", keyword: "n", builtIn: true),
        .init(id: "chatgpt", name: "ChatGPT", url: "https://chatgpt.com/?q=%s", keyword: "c", builtIn: true),
    ]
}

/// 빠른 검색 탭: 엔진 칩과 접두어("yt 고양이"), 붙여넣은 링크는 바로 연다.
/// ⌥1–9로 엔진 선택 (⌘1–9는 패널 탭 이동과 겹쳐 쓰지 않음).
final class QuickSearchModule: NotchModule {
    let id = "quicksearch"
    var title: String { T("빠른 검색", "Quick Search") }
    let symbol = "magnifyingglass"
    var enabledByDefault: Bool { true }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?

    var customEngines: [QuickSearchEngine] {
        guard let d = defaults.data("custom"), let list = try? JSONDecoder().decode([QuickSearchEngine].self, from: d) else { return [] }
        return list
    }
    func setCustomEngines(_ list: [QuickSearchEngine]) { defaults.set(try? JSONEncoder().encode(list), "custom") }

    var engines: [QuickSearchEngine] { QuickSearchEngine.builtIns + customEngines }
    var defaultEngineID: String { defaults.string("default", default: "google") }
    var defaultEngine: QuickSearchEngine { engines.first { $0.id == defaultEngineID } ?? QuickSearchEngine.builtIns[0] }
    func setDefaultEngine(_ id: String) { defaults.set(id, "default") }

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }

    func tabView() -> AnyView? { AnyView(QuickSearchTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 120) }
    func settingsView() -> AnyView? { AnyView(QuickSearchSettings(module: self)) }

    /// 입력 해석: 링크면 링크, 접두어가 맞으면 그 엔진, 아니면 고른 엔진
    func resolve(_ text: String, engine: QuickSearchEngine? = nil) -> (url: URL, engine: QuickSearchEngine?, query: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let u = LaunchSystem.webURL(from: t) { return (u, nil, t) }
        if let (e, q) = keywordMatch(t), let u = e.searchURL(q) { return (u, e, q) }
        let e = engine ?? defaultEngine
        return e.searchURL(t).map { ($0, e, t) }
    }

    func keywordMatch(_ t: String) -> (QuickSearchEngine, String)? {
        guard let sp = t.firstIndex(of: " ") else { return nil }
        let k = t[..<sp].lowercased()
        let rest = t[sp...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, let e = engines.first(where: { $0.keyword.lowercased() == k }) else { return nil }
        return (e, rest)
    }

    func open(_ text: String, engine: QuickSearchEngine? = nil) {
        guard let r = resolve(text, engine: engine) else { return }
        NSWorkspace.shared.open(r.url)
        context?.collapse()
    }

    func paletteResults(for query: String) -> [PaletteAction] {
        let t = query.trimmingCharacters(in: .whitespaces)
        if let u = LaunchSystem.webURL(from: t) {
            return [PaletteAction(id: "quicksearch.link", title: T("링크 열기", "Open link"), subtitle: u.absoluteString,
                                  symbol: "link") { NSWorkspace.shared.open(u) }]
        }
        if let (e, q) = keywordMatch(t), let u = e.searchURL(q) {
            return [PaletteAction(id: "quicksearch.\(e.id)", title: T("\(e.name)에서 검색: \(q)", "Search \(e.name) for \(q)"),
                                  subtitle: u.host, symbol: symbol) { NSWorkspace.shared.open(u) }]
        }
        return []
    }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "quicksearch.tab", title: T("빠른 검색 열기", "Open Quick Search"), symbol: symbol,
                       keywords: ["search", "web", "검색", "웹"]) { [weak self] in self?.context?.openTab("quicksearch") }]
    }

    func selfTest() -> [String] {
        var out: [String] = []
        for t in ["yt lofi beats", "g 날씨 & 미세먼지", "gh swiftui", "n 맛집", "c what is 2+2", "https://apple.com/mac", "apple.com", "hello world", "w 서울"] {
            if let r = resolve(t) { out.append("\(t) -> \(r.engine?.name ?? "link"): \(r.url.absoluteString)") }
            else { out.append("\(t) -> nil") }
        }
        let e = QuickSearchEngine(id: "x", name: "MDN", url: "https://developer.mozilla.org/search?q=%s", keyword: "mdn")
        out.append("custom: \(e.searchURL("fetch api")?.absoluteString ?? "nil")")
        out.append("engines: \(engines.count) (built-in \(QuickSearchEngine.builtIns.count), custom \(customEngines.count)), default \(defaultEngine.name)")
        for q in ["g swift concurrency", "apple.com", "hello"] {
            out.append("palette \"\(q)\": " + (paletteResults(for: q).first.map { $0.title } ?? "(none)"))
        }
        out.append("browser opened in self test: no")
        return out
    }
}

private struct QuickSearchTab: View {
    let module: QuickSearchModule
    @State private var text = ""
    @State private var engineID: String?
    @FocusState private var focused: Bool

    private var engine: QuickSearchEngine {
        module.engines.first { $0.id == engineID } ?? module.defaultEngine
    }

    private var hint: String {
        guard let r = module.resolve(text, engine: engine) else {
            return T("Return: \(engine.name)에서 검색 · 접두어 예: yt, gh, n · ⌥1–9 엔진", "Return: search \(engine.name) · prefixes like yt, gh, n · ⌥1–9 engines")
        }
        if let e = r.engine { return T("Return: \(e.name)에서 \"\(r.query)\" 검색", "Return: search \(e.name) for \"\(r.query)\"") }
        return T("Return: 링크 열기 ", "Return: open link ") + r.url.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LaunchField(placeholder: T("검색어 또는 링크", "Search or paste a link"), text: $text, focus: $focused) {
                module.open(text, engine: engine)
                text = ""
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(module.engines.enumerated()), id: \.element.id) { i, e in
                        chip(e, index: i)
                    }
                }
            }
            Text(hint).font(.system(size: 10.5)).foregroundStyle(LaunchUI.secondary).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(.white)
        .onAppear {
            module.context?.focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }

    @ViewBuilder private func chip(_ e: QuickSearchEngine, index: Int) -> some View {
        let c = LaunchChip(title: e.name, selected: e.id == engine.id, help: "\(e.name) · \(e.keyword)") {
            if text.trimmingCharacters(in: .whitespaces).isEmpty { engineID = e.id } else { module.open(text, engine: e); text = "" }
        }
        if index < 9 {
            c.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
        } else {
            c
        }
    }
}

private struct QuickSearchSettings: View {
    let module: QuickSearchModule
    @State private var custom: [QuickSearchEngine] = []
    @State private var defaultID = "google"
    @State private var name = ""
    @State private var url = ""
    @State private var keyword = ""

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && url.contains("%s")
            && URL(string: url.replacingOccurrences(of: "%s", with: "x"))?.scheme?.hasPrefix("http") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(T("기본 엔진", "Default engine"), selection: $defaultID) {
                ForEach(QuickSearchEngine.builtIns + custom) { Text($0.name).tag($0.id) }
            }
            .onChange(of: defaultID) { _, v in module.setDefaultEngine(v) }
            Text(T("사용자 엔진", "Custom engines")).font(.headline)
            ForEach(custom) { e in
                HStack {
                    Text(e.name)
                    Text(e.keyword).foregroundStyle(.secondary)
                    Text(e.url).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(T("빼기", "Remove")) { custom.removeAll { $0.id == e.id }; module.setCustomEngines(custom) }
                }
            }
            HStack {
                TextField(T("이름", "Name"), text: $name).frame(width: 110)
                TextField(T("검색 URL (%s = 검색어)", "Search URL (%s = query)"), text: $url)
                TextField(T("접두어", "Keyword"), text: $keyword).frame(width: 70)
                Button(T("추가", "Add")) {
                    custom.append(QuickSearchEngine(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces), url: url,
                                                    keyword: keyword.trimmingCharacters(in: .whitespaces).lowercased()))
                    module.setCustomEngines(custom)
                    name = ""; url = ""; keyword = ""
                }
                .disabled(!valid)
            }
            Text(T("기본 접두어: g Google · d DuckDuckGo · b Bing · p Perplexity · yt YouTube · gh GitHub · w Wikipedia · n Naver · c ChatGPT",
                   "Built-in keywords: g Google · d DuckDuckGo · b Bing · p Perplexity · yt YouTube · gh GitHub · w Wikipedia · n Naver · c ChatGPT"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { custom = module.customEngines; defaultID = module.defaultEngineID }
    }
}
