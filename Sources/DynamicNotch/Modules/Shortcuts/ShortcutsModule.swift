import AppKit
import SwiftUI

/// Apple 단축어 목록과 실행 상태 (단축어 탭과 홈 탭이 같이 쓴다).
/// 목록은 `/usr/bin/shortcuts list --show-identifiers`, 실행은 사용자가 누를 때만 `shortcuts run`.
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()
    static let cli = "/usr/bin/shortcuts"

    struct Item: Identifiable, Hashable { let id: String; let name: String; var folder: String? }
    enum RunState: Equatable { case running, success, failure(String) }

    @Published private(set) var items: [Item] = []
    @Published private(set) var loading = false
    @Published private(set) var loadedAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var states: [String: RunState] = [:]
    private var runners: [String: LaunchProcess] = [:]
    private var lister: LaunchProcess?

    var available: Bool { FileManager.default.isExecutableFile(atPath: Self.cli) }

    /// 단축어 탭·홈 탭 중 켜진 수. 둘 다 꺼질 때만 실행을 멈춘다.
    private var users = 0
    func retain() { users += 1 }
    func release() {
        users = max(0, users - 1)
        if users == 0 { cancelAll() }
    }

    /// "이름 (UUID)" 줄을 나눈다. 이름에 괄호가 있어도 마지막 UUID만 떼어 낸다.
    static func parseList(_ out: String) -> [Item] {
        out.split(separator: "\n").compactMap { line in
            let s = String(line)
            if let r = s.range(of: #" \(([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\)$"#, options: .regularExpression) {
                let id = String(s[r].dropFirst(2).dropLast())
                return Item(id: id, name: String(s[..<r.lowerBound]))
            }
            return s.isEmpty ? nil : Item(id: s, name: s)
        }
    }

    func refresh() {
        guard available, !loading else { return }
        loading = true
        error = nil
        let p = LaunchProcess()
        lister = p
        p.run(Self.cli, ["list", "--show-identifiers"], timeout: 20) { [weak self] r in
            guard let self else { return }
            self.loading = false
            self.lister = nil
            if r.status == 0 {
                self.items = Self.parseList(r.out)
                self.loadedAt = Date()
            } else {
                self.error = r.err.isEmpty ? T("목록을 읽지 못함", "Could not list shortcuts") : r.err
            }
        }
    }

    /// 사용자가 누른 단축어 실행
    func run(_ item: Item, done: ((Bool) -> Void)? = nil) {
        guard states[item.id] != .running else { return }
        states[item.id] = .running
        let p = LaunchProcess()
        runners[item.id] = p
        p.run(Self.cli, ["run", item.id], timeout: 300) { [weak self] r in
            guard let self else { return }
            self.runners[item.id] = nil
            let ok = r.status == 0
            self.states[item.id] = ok ? .success : .failure(r.err.trimmingCharacters(in: .whitespacesAndNewlines))
            done?(ok)
            // 성공·실패 표시는 4초 뒤 지운다
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.states[item.id] != .running { self?.states[item.id] = nil }
            }
        }
    }

    func cancelAll() {
        runners.values.forEach { $0.cancel() }
        runners = [:]
        lister?.cancel()
        lister = nil
        loading = false
        states = [:]
    }
}

/// 단축어 탭: 모든 단축어를 칩으로, 누르면 실행하고 스피너·성공·실패를 보여 준다.
final class ShortcutsModule: NotchModule {
    let id = "shortcuts"
    var title: String { T("단축어", "Shortcuts") }
    let symbol = "square.stack.3d.up"
    var enabledByDefault: Bool { false }

    fileprivate var context: ModuleContext?

    private var started = false

    func start(context: ModuleContext) {
        self.context = context
        if !started { ShortcutsStore.shared.retain(); started = true }
        if ShortcutsStore.shared.items.isEmpty { ShortcutsStore.shared.refresh() }
    }
    func stop() {
        if started { ShortcutsStore.shared.release(); started = false }
        context = nil
    }

    func tabView() -> AnyView? { AnyView(ShortcutsTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 220) }

    func paletteActions() -> [PaletteAction] {
        ShortcutsStore.shared.items.map { item in
            PaletteAction(id: "shortcuts.\(item.id)", title: T("단축어: ", "Shortcut: ") + item.name, symbol: symbol,
                          keywords: [item.name, "shortcut", "단축어"]) { [weak self] in self?.run(item) }
        }
    }

    func run(_ item: ShortcutsStore.Item) {
        ShortcutsStore.shared.run(item) { [weak self] ok in
            if !ok {
                self?.context?.notice(T("단축어 실패", "Shortcut failed"), item.name, symbol: "xmark.octagon", tint: .red)
            }
        }
    }

    func selfTest() -> [String] {
        let store = ShortcutsStore.shared
        guard store.available else { return ["shortcuts CLI missing at \(ShortcutsStore.cli) -> tab shows unsupported"] }
        let r = LaunchProcess.runSync(ShortcutsStore.cli, ["list", "--show-identifiers"], timeout: 15)
        let items = ShortcutsStore.parseList(r.out)
        var out = ["shortcuts list exit \(r.status): \(items.count) shortcuts"]
        out += items.prefix(5).map { "  \($0.name) [\($0.id.prefix(8))…]" }
        let sample = ShortcutsStore.parseList("Lights (On) (0CDB815F-2B92-4075-9D7E-06FB17C91F95)\n")
        out.append("parse name with parentheses: \(sample.first?.name ?? "nil")")
        let home = HomeShortcutsModule.classify(items.map(\.name), overrides: [:])
        out.append("home view: \(home.scenes.count) scenes, \(home.accessories.count) accessories (by name keywords)")
        out.append("shortcuts run in self test: no")
        return out
    }
}

private struct ShortcutsTab: View {
    let module: ShortcutsModule
    @ObservedObject private var store = ShortcutsStore.shared
    @State private var query = ""
    @FocusState private var focused: Bool

    private var filtered: [ShortcutsStore.Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.items.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        if !store.available {
            LaunchUnsupportedView(title: T("단축어를 쓸 수 없음", "Shortcuts unavailable"),
                                  reason: T("/usr/bin/shortcuts 명령이 없음 (macOS 12 이상 필요)", "/usr/bin/shortcuts is missing (needs macOS 12+)"),
                                  alternative: T("대안: 단축어 앱에서 직접 실행", "Alternative: run them in the Shortcuts app"))
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    LaunchField(placeholder: T("단축어 찾기", "Find a shortcut"), text: $query, focus: $focused) {
                        if let first = filtered.first { module.run(first) }
                    }
                    Button { store.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.island(.subhead, .semibold))
                            .rotationEffect(.degrees(store.loading ? 180 : 0))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(LaunchUI.fill))
                    }
                    .buttonStyle(.plain).help(T("새로 고침", "Refresh")).accessibilityLabel(T("새로 고침", "Refresh"))
                }
                if let e = store.error {
                    Text(e).font(.island(.footnote)).foregroundStyle(.red.opacity(0.8)).lineLimit(2)
                }
                if store.items.isEmpty && !store.loading {
                    LaunchUnsupportedView(title: T("단축어 없음", "No shortcuts"),
                                          reason: T("단축어 앱에서 단축어를 만들면 여기에 나타남", "Shortcuts you create in the Shortcuts app appear here"),
                                          symbol: "square.stack.3d.up")
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                            ForEach(filtered) { item in ShortcutChip(item: item, state: store.states[item.id]) { module.run(item) } }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .onAppear {
                if store.items.isEmpty { store.refresh() }
            }
        }
    }
}

/// 단축어 칩: 실행 중 스피너, 끝나면 체크·엑스
struct ShortcutChip: View {
    let item: ShortcutsStore.Item
    let state: ShortcutsStore.RunState?
    var symbol = "square.stack.3d.up.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    switch state {
                    case .running: ProgressView().controlSize(.small).scaleEffect(0.7)
                    case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    case nil: Image(systemName: symbol).foregroundStyle(LaunchUI.secondary)
                    }
                }
                .frame(width: 16, height: 16)
                Text(item.name).font(.island(.subhead)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(LaunchUI.fill))
        }
        .buttonStyle(.plain)
        .help({ if case .failure(let m) = state { return m.isEmpty ? T("실패", "Failed") : m }; return T("실행: ", "Run ") + item.name }())
        .accessibilityLabel(item.name)
    }
}

/// 홈 탭: 이름으로 홈 관련 단축어를 찾아 장면과 기기로 나눈다 (HomeKit 직접 접근 없음).
/// 잘못 분류된 타일은 오른쪽 클릭으로 장면·기기로 고정하거나 홈에서 뺀다.
final class HomeShortcutsModule: NotchModule {
    let id = "homeshortcuts"
    var title: String { T("홈", "Home") }
    let symbol = "house"
    var enabledByDefault: Bool { false }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?

    /// 단축어 이름 → "scene" | "accessory" | "hidden"
    var overrides: [String: String] {
        guard let d = defaults.data("overrides"), let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }
    func setOverride(_ name: String, _ value: String?) {
        var m = overrides
        m[name] = value
        defaults.set(try? JSONEncoder().encode(m), "overrides")
    }

    private var started = false

    func start(context: ModuleContext) {
        self.context = context
        if !started { ShortcutsStore.shared.retain(); started = true }
        if ShortcutsStore.shared.items.isEmpty { ShortcutsStore.shared.refresh() }
    }
    func stop() {
        if started { ShortcutsStore.shared.release(); started = false }
        context = nil
    }

    func tabView() -> AnyView? { AnyView(HomeShortcutsTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 500, height: 230) }

    static let sceneWords = ["scene", "장면", "모드", "mode", "good morning", "good night", "굿모닝", "굿나잇", "취침", "기상", "외출", "귀가",
                             "arrive", "leave", "movie", "영화", "파티", "party", "relax", "휴식"]
    static let accessoryWords = ["light", "lamp", "조명", "전등", "불 ", "불켜", "불 켜", "불끄", "불 끄", "스탠드", "thermostat", "온도", "난방", "냉방",
                                 "에어컨", "히터", "heater", "fan", "선풍기", "plug", "플러그", "콘센트", "outlet", "switch", "스위치", "blind", "블라인드",
                                 "커튼", "curtain", "shade", "lock", "도어락", "잠금", "door", "garage", "차고", "tv", "티비", "공기청정", "purifier",
                                 "humidifier", "가습기", "제습기", "로봇청소기", "vacuum", "speaker"]

    struct Classified { var scenes: [String]; var accessories: [String] }

    /// 이름으로 분류. 사용자 고정이 이름 분류보다 앞선다.
    static func classify(_ names: [String], overrides: [String: String]) -> Classified {
        var c = Classified(scenes: [], accessories: [])
        for n in names {
            if let o = overrides[n] {
                if o == "scene" { c.scenes.append(n) } else if o == "accessory" { c.accessories.append(n) }
                continue
            }
            let l = n.lowercased() + " "
            if accessoryWords.contains(where: { l.contains($0) }) { c.accessories.append(n) }
            else if sceneWords.contains(where: { l.contains($0) }) { c.scenes.append(n) }
        }
        return c
    }

    func run(_ item: ShortcutsStore.Item) {
        ShortcutsStore.shared.run(item) { [weak self] ok in
            if ok { self?.context?.collapse() } else {
                self?.context?.notice(T("단축어 실패", "Shortcut failed"), item.name, symbol: "xmark.octagon", tint: .red)
            }
        }
    }

    func paletteActions() -> [PaletteAction] {
        let c = Self.classify(ShortcutsStore.shared.items.map(\.name), overrides: overrides)
        let names = Set(c.scenes + c.accessories)
        return ShortcutsStore.shared.items.filter { names.contains($0.name) }.map { item in
            PaletteAction(id: "home.\(item.id)", title: T("홈: ", "Home: ") + item.name, symbol: symbol,
                          keywords: [item.name, "home", "홈", "homekit"]) { [weak self] in self?.run(item) }
        }
    }

    func selfTest() -> [String] {
        let names = ["거실 조명 켜기", "Good Night", "외출 모드", "Bedroom Lamp Off", "에어컨 끄기", "QR인증", "플레이리스트 재생", "Movie Time"]
        let c = Self.classify(names, overrides: ["플레이리스트 재생": "scene", "Movie Time": "hidden"])
        return ["sample scenes: \(c.scenes.joined(separator: ", "))",
                "sample accessories: \(c.accessories.joined(separator: ", "))",
                "overrides stored: \(overrides.count)",
                "HomeKit accessed directly: no (Shortcuts only)"]
    }
}

private struct HomeShortcutsTab: View {
    let module: HomeShortcutsModule
    @ObservedObject private var store = ShortcutsStore.shared
    @State private var overrides: [String: String] = [:]
    @State private var showAll = false

    var body: some View {
        let c = HomeShortcutsModule.classify(store.items.map(\.name), overrides: overrides)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showAll ? T("모든 단축어 · 오른쪽 클릭으로 홈에 고정", "All shortcuts · right-click to pin to Home")
                             : T("이름으로 찾은 홈 단축어", "Home shortcuts found by name"))
                    .font(.island(.footnote)).foregroundStyle(LaunchUI.secondary)
                Spacer()
                LaunchChip(title: showAll ? T("홈만", "Home only") : T("모두 보기", "Show all"), selected: showAll) { showAll.toggle() }
                LaunchChip(title: "", symbol: "arrow.clockwise", help: T("새로 고침", "Refresh")) { store.refresh() }
            }
            if !store.available {
                LaunchUnsupportedView(title: T("단축어를 쓸 수 없음", "Shortcuts unavailable"),
                                      reason: T("/usr/bin/shortcuts 명령이 없음", "/usr/bin/shortcuts is missing"),
                                      alternative: T("대안: 홈 앱 사용", "Alternative: use the Home app"))
            } else if !showAll && c.scenes.isEmpty && c.accessories.isEmpty {
                LaunchUnsupportedView(title: T("홈 단축어 없음", "No Home shortcuts"),
                                      reason: T("macOS는 다른 앱의 HomeKit 접근을 막아 단축어를 거쳐 제어함", "macOS blocks direct HomeKit access, so Home control goes through Shortcuts"),
                                      alternative: T("단축어 앱에서 '거실 조명 켜기'처럼 기기·장면 이름을 넣은 단축어를 만들거나 '모두 보기'에서 고정",
                                                     "Create shortcuts named after devices or scenes (\"Living Room Lights On\"), or pin one from Show all"),
                                      symbol: "house")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if showAll {
                            grid(store.items, symbol: "square.stack.3d.up.fill")
                        } else {
                            section(T("장면", "Scenes"), c.scenes, symbol: "sparkles")
                            section(T("기기", "Accessories"), c.accessories, symbol: "lightbulb.fill")
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            overrides = module.overrides
            if store.items.isEmpty { store.refresh() }
        }
    }

    @ViewBuilder private func section(_ title: String, _ names: [String], symbol: String) -> some View {
        if !names.isEmpty {
            Text(title).font(.island(.footnote, .semibold)).foregroundStyle(LaunchUI.secondary)
            grid(store.items.filter { names.contains($0.name) }, symbol: symbol)
        }
    }

    private func grid(_ items: [ShortcutsStore.Item], symbol: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
            ForEach(items) { item in
                ShortcutChip(item: item, state: store.states[item.id], symbol: symbol) { module.run(item) }
                    .contextMenu {
                        Button(T("장면으로 고정", "Pin as scene")) { set(item.name, "scene") }
                        Button(T("기기로 고정", "Pin as accessory")) { set(item.name, "accessory") }
                        Button(T("홈에서 빼기", "Hide from Home")) { set(item.name, "hidden") }
                        if overrides[item.name] != nil { Button(T("고정 해제 (이름으로 분류)", "Unpin (classify by name)")) { set(item.name, nil) } }
                    }
            }
        }
    }

    private func set(_ name: String, _ v: String?) {
        module.setOverride(name, v)
        overrides = module.overrides
    }
}
