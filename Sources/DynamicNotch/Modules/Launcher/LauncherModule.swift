import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 고정 앱 목록 (런처 탭과 런처 휠이 같이 쓴다). 번들 ID로 저장해 앱 이름 변경·이동 뒤에도 동작한다.
enum LauncherStore {
    static let defaults = ModuleDefaults(module: "launcher")

    static var apps: [String] { defaults.strings("apps", default: []) }
    static func setApps(_ list: [String]) { defaults.set(list, "apps") }

    /// 앱 위치 → 저장 값 (번들 ID, 없으면 경로)
    static func key(for url: URL) -> String { Bundle(url: url)?.bundleIdentifier ?? url.path }

    static func add(_ url: URL) {
        let k = key(for: url)
        guard !apps.contains(k) else { return }
        setApps(apps + [k])
    }
    static func remove(_ k: String) { setApps(apps.filter { $0 != k }) }
    static func move(_ k: String, to index: Int) {
        var list = apps
        guard let from = list.firstIndex(of: k) else { return }
        list.remove(at: from)
        list.insert(k, at: max(0, min(index, list.count)))
        setApps(list)
    }

    /// 설치된 앱 (선택기용): /Applications, /System/Applications, ~/Applications 와 그 Utilities
    static func installedApps() -> [URL] {
        let fm = FileManager.default
        var dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        dirs.append(contentsOf: (try? fm.contentsOfDirectory(atPath: "/Applications"))?
            .filter { !$0.hasSuffix(".app") && !$0.hasPrefix(".") }
            .map { "/Applications/\($0)" } ?? [])
        var seen = Set<String>()
        var out: [URL] = []
        for d in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
            for i in items where i.hasSuffix(".app") && !i.hasPrefix(".") {
                let u = URL(fileURLWithPath: d).appendingPathComponent(i)
                let k = key(for: u)
                if seen.insert(k).inserted { out.append(u) }
            }
        }
        return out.sorted { LaunchApps.name(of: $0).localizedCaseInsensitiveCompare(LaunchApps.name(of: $1)) == .orderedAscending }
    }
}

/// 앱 런처 탭: 고른 앱을 한 번 눌러 실행하는 타일. 끌어서 순서 변경, 마우스를 올려 제거.
final class LauncherModule: NotchModule {
    let id = "launcher"
    var title: String { T("앱 런처", "Launcher") }
    let symbol = "square.grid.3x3"
    var enabledByDefault: Bool { false }

    fileprivate var context: ModuleContext?

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }

    func tabView() -> AnyView? { AnyView(LauncherTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 220) }

    func launch(_ key: String) {
        guard let url = LaunchApps.resolve(key) else {
            context?.notice(T("앱을 찾을 수 없음", "App not found"), key, symbol: "questionmark.app")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        context?.collapse()
    }

    func paletteActions() -> [PaletteAction] {
        LauncherStore.apps.compactMap { k in
            guard let url = LaunchApps.resolve(k) else { return nil }
            let name = LaunchApps.name(of: url)
            return PaletteAction(id: "launcher.\(k)", title: T("열기: ", "Open: ") + name, symbol: "app",
                                 keywords: [name, "launch", "open", "실행", "앱"]) { [weak self] in self?.launch(k) }
        }
    }

    func selfTest() -> [String] {
        let installed = LauncherStore.installedApps()
        var out = ["installed apps found: \(installed.count)"]
        if let first = installed.first { out.append("first: \(LaunchApps.name(of: first)) key=\(LauncherStore.key(for: first))") }
        for id in ["com.apple.Safari", "com.apple.finder", "com.apple.TextEdit"] {
            out.append("resolve \(id): \(LaunchApps.resolve(id)?.path ?? "not found")")
        }
        out.append("pinned: \(LauncherStore.apps.count) \(LauncherStore.apps.prefix(5).joined(separator: ", "))")
        out.append("unresolvable pinned: \(LauncherStore.apps.filter { LaunchApps.resolve($0) == nil }.count)")
        return out
    }
}

private struct LauncherTab: View {
    let module: LauncherModule
    @State private var apps: [String] = LauncherStore.apps
    @State private var picking = false
    @State private var hover: String?
    @State private var dragging: String?

    private let columns = Array(repeating: GridItem(.fixed(78), spacing: 6), count: 6)

    var body: some View {
        Group {
            if picking {
                LauncherPicker(existing: Set(apps), onPick: { url in
                    LauncherStore.add(url)
                    apps = LauncherStore.apps
                }, onDone: { picking = false }, focusInput: { module.context?.focusInput() })
            } else {
                grid
            }
        }
        .foregroundStyle(.white)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(apps, id: \.self) { k in tile(k) }
                Button { picking = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        Text(T("앱 추가", "Add app")).font(.system(size: 10.5)).foregroundStyle(LaunchUI.secondary)
                    }
                    .frame(width: 78, height: 70)
                }
                .buttonStyle(.plain).help(T("앱 추가", "Add an app")).accessibilityLabel(T("앱 추가", "Add an app"))
            }
            .padding(.top, 2)
            if apps.isEmpty {
                Text(T("앱을 추가하면 한 번 눌러 실행할 수 있음 · 끌어서 순서 변경", "Add apps to launch them with one click · drag to reorder"))
                    .font(.system(size: 11)).foregroundStyle(LaunchUI.secondary).padding(.top, 8)
            }
        }
    }

    @ViewBuilder private func tile(_ k: String) -> some View {
        let url = LaunchApps.resolve(k)
        let name = url.map(LaunchApps.name(of:)) ?? k
        ZStack(alignment: .topTrailing) {
            Button { module.launch(k) } label: {
                VStack(spacing: 4) {
                    if let url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "questionmark.app.dashed").font(.system(size: 30)).frame(width: 44, height: 44)
                    }
                    Text(name).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(url == nil ? LaunchUI.secondary : .white)
                }
                .frame(width: 78, height: 70)
                .background(RoundedRectangle(cornerRadius: 10).fill(hover == k ? LaunchUI.fill : .clear))
                .opacity(dragging == k ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .help(url == nil ? T("앱을 찾을 수 없음: ", "App not found: ") + k : T("열기: ", "Open ") + name)
            .accessibilityLabel(name)
            if hover == k {
                Button {
                    LauncherStore.remove(k)
                    apps = LauncherStore.apps
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(.white, Color.gray.opacity(0.8))
                }
                .buttonStyle(.plain).help(T("목록에서 빼기", "Remove from launcher"))
                .accessibilityLabel(T("빼기: ", "Remove ") + name)
                .offset(x: -4, y: 2)
            }
        }
        .onHover { hover = $0 ? k : (hover == k ? nil : hover) }
        .onDrag {
            dragging = k
            return NSItemProvider(object: k as NSString)
        }
        .onDrop(of: [UTType.text], delegate: LauncherDropDelegate(target: k, apps: $apps, dragging: $dragging))
    }
}

/// 끌어 놓을 때 순서 바꾸기
private struct LauncherDropDelegate: DropDelegate {
    let target: String
    @Binding var apps: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target, let from = apps.firstIndex(of: d), let to = apps.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            apps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        LauncherStore.setApps(apps)
        dragging = nil
        return true
    }
}

/// 설치된 앱 선택기 (무거운 열기 패널 대신 노치 안에서 고른다)
private struct LauncherPicker: View {
    let existing: Set<String>
    let onPick: (URL) -> Void
    let onDone: () -> Void
    let focusInput: () -> Void
    @State private var query = ""
    @State private var all: [URL] = []
    @State private var added: Set<String> = []
    @FocusState private var focused: Bool

    private var filtered: [URL] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return all.filter { q.isEmpty || LaunchApps.name(of: $0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                LaunchField(placeholder: T("앱 이름 검색", "Search apps"), text: $query, focus: $focused)
                LaunchChip(title: T("완료", "Done"), action: onDone)
            }
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered, id: \.self) { u in
                        let k = LauncherStore.key(for: u)
                        let isIn = existing.contains(k) || added.contains(k)
                        Button {
                            guard !isIn else { return }
                            onPick(u)
                            added.insert(k)
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 20, height: 20)
                                Text(LaunchApps.name(of: u)).font(.system(size: 12.5))
                                Spacer()
                                Image(systemName: isIn ? "checkmark" : "plus").font(.system(size: 11)).foregroundStyle(LaunchUI.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isIn ? T("이미 추가됨", "Already added") : T("추가", "Add"))
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let list = LauncherStore.installedApps()
                DispatchQueue.main.async { all = list }
            }
            focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }
}
