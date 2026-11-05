import AppKit
import SwiftUI

/// 패키지: Homebrew 검색·설치·업그레이드·제거, 앱 업데이트 확인(Homebrew·App Store·Sparkle), 앱 제거(관련 파일까지 휴지통으로).
/// 외부 도구(brew)와 네트워크(업데이트 확인)를 쓰므로 기본은 꺼짐. 모든 조회·변경은 탭에서 사용자가 누를 때만 한다.
final class PackagesModule: NotchModule {
    let id = "packages"
    var title: String { T("패키지", "Packages") }
    let symbol = "shippingbox"
    let enabledByDefault = false

    let ui = PkgUI()
    let brew = PkgBrewStore()
    let updates = PkgUpdateStore()
    let uninstall = PkgUninstallStore()
    private var context: ModuleContext?

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    var checkAppStore: Bool { defaults.bool("checkAppStore", default: true) }
    var checkSparkle: Bool { defaults.bool("checkSparkle", default: true) }

    func start(context: ModuleContext) {
        self.context = context
        brew.onJobFinished = { [weak self] title, ok in self?.notice(title, ok) }
        uninstall.onFinished = { [weak self] title, ok in self?.notice(title, ok) }
    }

    /// 실행 중인 brew·조회·스캔을 모두 멈춘다
    func stop() {
        brew.processes.terminateAll()
        updates.cancel()
        uninstall.cancel()
        context = nil
    }

    func tabView() -> AnyView? {
        if AppSettings.isHelper { applyRenderHooks() }
        return AnyView(PkgTab(module: self, ui: ui, brew: brew, updates: updates, uninstall: uninstall))
    }

    /// 화면 그리기 검사(--render-tab)에서만 쓰는 환경 변수: 화면 선택·검색·확인·앱 고르기 (설치·삭제는 하지 않음)
    private var renderHooksApplied = false
    private func applyRenderHooks() {
        guard !renderHooksApplied else { return }
        renderHooksApplied = true
        let env = ProcessInfo.processInfo.environment
        if let m = env["DMN_PACKAGES_MODE"].flatMap(PkgUI.Mode.init(rawValue:)) { ui.mode = m }
        if env["DMN_PACKAGES_LIST"] == "outdated" { ui.brewList = .outdated }
        if let q = env["DMN_PACKAGES_QUERY"] { brew.detect(); brew.query = q; brew.search() }
        if env["DMN_PACKAGES_CHECK"] == "1" { brew.detect(); brew.loadLists(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.checkUpdates() } }
        if let name = env["DMN_PACKAGES_SELECT"], let app = PkgLocalApp.scan().first(where: { $0.name == name }) {
            uninstall.includeContainers = false   // 검사 중 다른 앱 컨테이너 허용 창을 띄우지 않게
            uninstall.loadApps()
            uninstall.select(app)
        }
    }
    var tabContentSize: CGSize { CGSize(width: 600, height: 290) }

    func checkUpdates() {
        brew.detect()
        updates.check(brew: brew, appStore: checkAppStore, sparkle: checkSparkle)
    }

    func focusInput() { context?.focusInput() }

    private func notice(_ title: String, _ ok: Bool) {
        context?.notice(title + (ok ? T(" 완료", " done") : T(" 실패", " failed")), nil,
                        symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        tint: ok ? .green : .orange, tab: id)
    }

    private func open(_ mode: PkgUI.Mode) {
        ui.mode = mode
        context?.openTab(id)
    }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "packages.brew", title: T("Homebrew 패키지", "Homebrew packages"),
                          subtitle: T("검색·설치·업그레이드·제거", "Search, install, upgrade, uninstall"), symbol: "shippingbox",
                          keywords: ["brew", "homebrew", "홈브루", "cask", "formula"], run: { [weak self] in self?.open(.brew) }),
            PaletteAction(id: "packages.updates", title: T("앱 업데이트 확인", "Check app updates"),
                          subtitle: "Homebrew · App Store · Sparkle", symbol: "arrow.down.app",
                          keywords: ["update", "업데이트", "outdated", "app store", "sparkle"],
                          run: { [weak self] in self?.open(.updates); self?.checkUpdates() }),
            PaletteAction(id: "packages.uninstall", title: T("앱 제거", "Uninstall an app"),
                          subtitle: T("관련 파일까지 휴지통으로", "Move the app and its files to the Trash"), symbol: "trash",
                          keywords: ["uninstall", "제거", "삭제", "remove", "app cleaner"], run: { [weak self] in self?.open(.uninstall) }),
        ]
    }

    /// "brew jq" 또는 "brew search jq" → Homebrew 검색
    func paletteResults(for query: String) -> [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.lowercased().hasPrefix("brew ") else { return [] }
        var rest = String(q.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix("search ") { rest = String(rest.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        guard rest.count >= 2 else { return [] }
        return [PaletteAction(id: "packages.brew.search", title: T("Homebrew 검색: \(rest)", "brew search \(rest)"),
                              subtitle: T("이름과 설명에서 찾기", "Name and description"), symbol: "magnifyingglass",
                              run: { [weak self] in
                                  guard let self else { return }
                                  self.brew.detect()
                                  self.brew.query = rest
                                  self.brew.search()
                                  self.open(.brew)
                              })]
    }

    func settingsView() -> AnyView? { AnyView(PkgSettings(defaults: defaults)) }

    func selfTest() -> [String] { PkgSelfTest.run(processes: brew.processes) }
}

/// 탭 안 화면 선택
final class PkgUI: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case brew, updates, uninstall
        var id: String { rawValue }
        var label: String {
            switch self {
            case .brew: return "Homebrew"
            case .updates: return T("업데이트", "Updates")
            case .uninstall: return T("앱 제거", "Uninstall")
            }
        }
        var symbol: String {
            switch self {
            case .brew: return "shippingbox"
            case .updates: return "arrow.down.app"
            case .uninstall: return "trash"
            }
        }
    }
    enum BrewList { case installed, outdated }
    @Published var mode: Mode = .brew
    @Published var brewList: BrewList = .installed
}

// MARK: - 탭

private struct PkgTab: View {
    let module: PackagesModule
    @ObservedObject var ui: PkgUI
    @ObservedObject var brew: PkgBrewStore
    @ObservedObject var updates: PkgUpdateStore
    @ObservedObject var uninstall: PkgUninstallStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                ForEach(PkgUI.Mode.allCases) { m in
                    Button { ui.mode = m } label: { Label(m.label, systemImage: m.symbol) }
                        .buttonStyle(FAPillStyle(tone: ui.mode == m ? .primary : .normal))
                        .accessibilityAddTraits(ui.mode == m ? .isSelected : [])
                }
                Spacer()
            }
            switch ui.mode {
            case .brew: PkgBrewView(module: module, brew: brew, ui: ui)
            case .updates: PkgUpdatesView(module: module, brew: brew, updates: updates)
            case .uninstall: PkgUninstallView(store: uninstall)
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            module.focusInput()   // 검색·앱 찾기 칸에 글자를 받으려면 노치 창이 키 창이어야 한다
            brew.detect()
            if brew.brewPath != nil, brew.listsLoadedAt == nil { brew.loadLists() }
        }
    }
}

// MARK: Homebrew

private struct PkgBrewView: View {
    let module: PackagesModule
    @ObservedObject var brew: PkgBrewStore
    @ObservedObject var ui: PkgUI
    @FocusState private var focused: Bool
    @State private var confirm: String?

    var body: some View {
        if brew.brewPath == nil {
            FAUnsupportedView(symbol: "shippingbox", title: T("Homebrew가 없음", "Homebrew isn't installed"),
                              reason: T("/opt/homebrew/bin/brew와 /usr/local/bin/brew 둘 다 없음", "Neither /opt/homebrew/bin/brew nor /usr/local/bin/brew exists"),
                              alternative: T("brew.sh에서 직접 설치한 뒤 다시 열기 (이 앱은 Homebrew를 설치하지 않음)", "Install it from brew.sh, then reopen (this app doesn't install Homebrew)"),
                              actionTitle: T("brew.sh 열기", "Open brew.sh")) {
                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.island(.footnote)).foregroundStyle(.white.opacity(0.5))
                        TextField(T("검색 (이름·설명) 후 ↩", "Search name or description, then ↩"), text: $brew.query)
                            .textFieldStyle(.plain).font(.island(.subhead))
                            .focused($focused)
                            .onSubmit { brew.search() }
                        if brew.searching { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12) }
                        if !brew.query.isEmpty {
                            Button { brew.clearSearch() } label: { Image(systemName: "xmark.circle.fill").font(.island(.footnote)) }
                                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                                .help(T("검색 지우기", "Clear search")).accessibilityLabel(T("검색 지우기", "Clear search"))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                    Button(T("설치됨 \(brew.installed.count)", "Installed \(brew.installed.count)")) {
                        brew.clearSearch(); ui.brewList = .installed
                    }
                    .buttonStyle(FAPillStyle(tone: brew.searchedQuery.isEmpty && ui.brewList == .installed ? .primary : .normal))
                    Button(T("업데이트 \(brew.outdated.count)", "Outdated \(brew.outdated.count)")) {
                        brew.clearSearch(); ui.brewList = .outdated
                    }
                    .buttonStyle(FAPillStyle(tone: brew.searchedQuery.isEmpty && ui.brewList == .outdated ? .primary : .normal))
                }
                if let job = brew.job {
                    PkgJobView(brew: brew, job: job)
                } else {
                    list
                }
                footer
            }
            .onAppear { focused = true }
        }
    }

    private var shown: [PkgBrewItem] {
        if !brew.searchedQuery.isEmpty { return brew.results }
        return ui.brewList == .installed ? brew.installed : brew.outdated
    }

    @ViewBuilder private var list: some View {
        let items = shown
        if items.isEmpty {
            VStack(spacing: 4) {
                if brew.loadingLists && brew.searchedQuery.isEmpty {
                    ProgressView().controlSize(.small)
                    Text(T("Homebrew 목록 읽는 중", "Reading Homebrew lists")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Image(systemName: brew.searchedQuery.isEmpty ? "checkmark.circle" : "questionmark.circle").font(.island(.title2))
                    Text(!brew.searchedQuery.isEmpty ? T("'\(brew.searchedQuery)' 결과 없음", "No results for '\(brew.searchedQuery)'")
                         : ui.brewList == .outdated ? T("오래된 항목 없음", "Everything is up to date")
                         : T("설치된 항목 없음", "Nothing installed"))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    if brew.searchedQuery.isEmpty, ui.brewList == .outdated {
                        HStack {
                            Text(T("\(items.count)개 오래됨 (마지막 brew update 기준)", "\(items.count) outdated (as of the last brew update)"))
                                .font(.island(.caption)).foregroundStyle(.white.opacity(0.55))
                            Spacer()
                            Button(T("모두 업그레이드", "Upgrade all")) { brew.perform(.upgradeAll) }.buttonStyle(FAPillStyle(tone: .primary))
                                .help("brew upgrade")
                        }
                        .padding(.bottom, 2)
                    }
                    ForEach(items) { row($0) }
                }
            }
        }
    }

    private func row(_ item: PkgBrewItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.isCask ? "macwindow" : "terminal").font(.island(.footnote)).frame(width: 16)
                .foregroundStyle(.white.opacity(0.7))
                .help(item.isCask ? "cask" : "formula")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(item.name).font(.island(.subhead, .semibold)).lineLimit(1)
                    if let d = item.displayName, d.lowercased() != item.name.lowercased() {
                        Text(d).font(.island(.caption)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    if item.pinned { Image(systemName: "pin.fill").font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)) }
                }
                if !item.desc.isEmpty {
                    Text(item.desc).font(.island(.caption)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let v = item.version {
                Text(item.latest.map { "\(v) → \($0)" } ?? v).font(.island(.caption)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            actions(item)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder private func actions(_ item: PkgBrewItem) -> some View {
        if item.version == nil {
            Button(T("설치", "Install")) { brew.perform(.install, item) }.buttonStyle(FAPillStyle(tone: .primary))
                .help("brew install\(item.isCask ? " --cask" : "") \(item.name)")
        } else {
            if item.latest != nil, !item.pinned {
                Button(T("업그레이드", "Upgrade")) { brew.perform(.upgrade, item) }.buttonStyle(FAPillStyle(tone: .primary))
                    .help("brew upgrade\(item.isCask ? " --cask" : "") \(item.name)")
            }
            if confirm == item.id {
                Button(T("제거 확인", "Confirm")) { confirm = nil; brew.perform(.uninstall, item) }
                    .buttonStyle(FAPillStyle(tone: .destructive))
                    .help("brew uninstall\(item.isCask ? " --cask" : "") \(item.name)")
            } else {
                Button { confirm = item.id } label: { Image(systemName: "trash") }
                    .buttonStyle(FAPillStyle())
                    .help(T("제거 (한 번 더 눌러 확인)", "Uninstall (click again to confirm)"))
                    .accessibilityLabel(T("\(item.name) 제거", "Uninstall \(item.name)"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let e = brew.error {
                Image(systemName: "exclamationmark.triangle.fill").font(.island(.caption2)).foregroundStyle(.orange)
                Text(e).lineLimit(1)
            } else if brew.loadingLists {
                Text(T("목록 새로 읽는 중", "Refreshing lists"))
            } else if let at = brew.listsLoadedAt {
                Text(T("의존성 \(brew.dependencies.count)개 숨김 · ", "\(brew.dependencies.count) dependencies hidden · ")
                     + at.formatted(date: .omitted, time: .shortened))
            }
            Spacer()
            Text(brew.brewPath ?? "").foregroundStyle(.white.opacity(0.4))
            Button(T("새로 고침", "Refresh")) { brew.loadLists() }.buttonStyle(FAPillStyle()).disabled(brew.loadingLists)
                .help(T("설치·오래된 목록 다시 읽기", "Re-read installed and outdated lists"))
            Button("brew update") { brew.perform(.update) }.buttonStyle(FAPillStyle()).disabled(brew.job?.running == true)
                .help(T("Homebrew 패키지 목록을 새로 받는다 (인터넷)", "Download the latest package index (internet)"))
        }
        .font(.island(.caption)).foregroundStyle(.white.opacity(0.55))
    }
}

/// 진행 중이거나 끝난 brew 작업과 로그
private struct PkgJobView: View {
    @ObservedObject var brew: PkgBrewStore
    let job: PkgBrewStore.Job

    var body: some View {
        FACard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if job.running {
                        ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: job.status == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(job.status == 0 ? .green : .orange)
                    }
                    Text(job.title).font(.island(.subhead, .semibold))
                    Spacer()
                    if job.running {
                        Button(T("중단", "Stop")) { brew.cancelJob() }.buttonStyle(FAPillStyle(tone: .destructive))
                    } else {
                        if job.status != 0 {
                            Button(T("명령 복사", "Copy command")) { brew.copyCommand() }.buttonStyle(FAPillStyle())
                                .help(T("터미널에 붙여넣어 직접 실행", "Paste into Terminal to run it yourself"))
                        }
                        Button(T("닫기", "Close")) { brew.dismissJob() }.buttonStyle(FAPillStyle())
                    }
                }
                Text(job.command).font(.island(.caption, .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(job.log.suffix(200).enumerated()), id: \.offset) { i, line in
                                Text(line).font(.island(.caption2, .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading).id(i)
                            }
                        }
                    }
                    .onChange(of: job.log.count) { _, _ in proxy.scrollTo(min(199, job.log.count - 1), anchor: .bottom) }
                }
                if let hint = job.hint {
                    Text(hint).font(.island(.caption)).foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: 업데이트

private struct PkgUpdatesView: View {
    let module: PackagesModule
    @ObservedObject var brew: PkgBrewStore
    @ObservedObject var updates: PkgUpdateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(updates.checkedAt == nil ? T("업데이트 확인", "Check for updates") : T("다시 확인", "Check again")) { module.checkUpdates() }
                    .buttonStyle(FAPillStyle(tone: .primary)).disabled(updates.checking)
                if updates.checking { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12) }
                if let at = updates.checkedAt {
                    Text(T("\(updates.items.count)개 · \(at.formatted(date: .omitted, time: .shortened)) 확인",
                           "\(updates.items.count) · checked \(at.formatted(date: .omitted, time: .shortened))"))
                        .font(.island(.caption)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if updates.items.contains(where: { $0.source == .brew }) {
                    Button(T("Homebrew 모두 업그레이드", "Upgrade all Homebrew")) { brew.perform(.upgradeAll) }
                        .buttonStyle(FAPillStyle()).disabled(brew.job?.running == true).help("brew upgrade")
                }
            }
            if let job = brew.job {
                PkgJobView(brew: brew, job: job).frame(maxHeight: 120)
            }
            if updates.checkedAt == nil && !updates.checking {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("누를 때만 확인한다:", "Checks only when you click:")).font(.island(.footnote))
                    Text(T("• Homebrew: 이 Mac의 brew 목록 기준 오래된 항목", "• Homebrew: outdated items from this Mac's brew index"))
                    Text(T("• App Store 앱: 번들 ID를 Apple 조회 API(itunes.apple.com)에 보내 버전 비교", "• App Store apps: bundle IDs sent to Apple's lookup API (itunes.apple.com)"))
                    Text(T("• Sparkle 앱: 각 앱 Info.plist의 업데이트 주소(appcast)를 읽어 비교", "• Sparkle apps: reads each app's own appcast feed"))
                    Text(T("설치는 하지 않는다. Homebrew는 여기서 업그레이드, App Store는 스토어 페이지, Sparkle은 그 앱을 열어 넘긴다.",
                           "Nothing installs automatically: Homebrew upgrades here, App Store opens the store page, Sparkle apps open themselves."))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .font(.island(.caption)).foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if updates.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: updates.checking ? "hourglass" : "checkmark.circle").font(.island(.title2))
                    Text(updates.checking ? T("확인 중", "Checking") : T("모두 최신", "Everything is up to date"))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) { ForEach(updates.items) { row($0) } }
                }
            }
            if !updates.notes.isEmpty {
                Text(updates.notes.joined(separator: " · ")).font(.island(.caption2)).foregroundStyle(.white.opacity(0.45)).lineLimit(2)
            }
        }
    }

    private func row(_ u: PkgUpdate) -> some View {
        HStack(spacing: 6) {
            if let url = u.appURL { FAFileIcon(url: url, size: 18) }
            else { Image(systemName: u.brewItem?.isCask == true ? "macwindow" : "terminal").font(.island(.footnote)).frame(width: 18) }
            VStack(alignment: .leading, spacing: 0) {
                Text(u.name).font(.island(.subhead)).lineLimit(1)
                Text("\(u.installed) → \(u.latest)").font(.island(.caption)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 4)
            Text(u.source.label).font(.island(.caption2)).foregroundStyle(.white.opacity(0.45))
            switch u.source {
            case .brew:
                Button(T("업그레이드", "Upgrade")) { if let b = u.brewItem { brew.perform(.upgrade, b) } }
                    .buttonStyle(FAPillStyle(tone: .primary)).disabled(brew.job?.running == true || u.brewItem?.pinned == true)
            case .appStore:
                Button(T("스토어 열기", "Open Store")) {
                    let target = u.storeID.flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }
                    if let target { NSWorkspace.shared.open(target) }
                }
                .buttonStyle(FAPillStyle()).help(T("App Store에서 업데이트", "Update in the App Store"))
            case .sparkle:
                Button(T("앱 열기", "Open app")) {
                    if let url = u.appURL { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                }
                .buttonStyle(FAPillStyle()).help(T("앱을 열어 그 앱의 업데이트 기능으로 설치", "Open the app and let its updater install"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
    }
}

// MARK: 앱 제거

private struct PkgUninstallView: View {
    @ObservedObject var store: PkgUninstallStore
    @State private var confirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FACard {
                VStack(alignment: .leading, spacing: 5) {
                    TextField(T("앱 찾기", "Find an app"), text: $store.filter)
                        .textFieldStyle(.plain).font(.island(.footnote))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                    if store.loadingApps && store.apps.isEmpty {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                    }
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(store.filtered) { app in
                                Button { confirm = false; store.select(app) } label: {
                                    HStack(spacing: 6) {
                                        FAFileIcon(url: app.url, size: 18)
                                        Text(app.name).font(.island(.footnote)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(store.selected?.id == app.id ? 0.16 : 0)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 200)
            FACard { detail }
        }
        .onAppear { if store.apps.isEmpty { store.loadApps() } }
    }

    @ViewBuilder private var detail: some View {
        if let app = store.selected {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    FAFileIcon(url: app.url, size: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name).font(.island(.subhead, .semibold)).lineLimit(1)
                        Text("\(app.shortVersion) · \(app.bundleID)").font(.island(.caption)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer()
                }
                if let r = store.running {
                    Label(T("\(r) 실행 중: 먼저 끝내야 지울 수 있음", "\(r) is running: quit it first"), systemImage: "exclamationmark.triangle.fill")
                        .font(.island(.caption)).foregroundStyle(.orange)
                }
                if store.scanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                        Text(T("관련 파일 찾는 중", "Finding related files")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(store.leftovers) { item in
                                HStack(spacing: 6) {
                                    Toggle("", isOn: Binding(get: { item.selected }, set: { _ in confirm = false; store.toggle(item) }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                    Text(item.category).font(.island(.caption)).frame(width: 74, alignment: .leading)
                                    Text(FAKit.shortPath(item.url)).font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1).truncationMode(.middle)
                                        .help(item.byName ? T("앱 이름으로 찾은 항목 (기본 선택 안 함)", "Matched by app name (not selected by default)") : item.url.path)
                                    if item.byName {
                                        Text(T("이름 일치", "name")).font(.island(.caption2)).foregroundStyle(.yellow.opacity(0.8))
                                    }
                                    Spacer(minLength: 2)
                                    Text(item.size.map { FAKit.bytes($0) } ?? "—").font(.island(.caption)).monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    if let m = store.message {
                        Text(m).font(.island(.caption)).foregroundStyle(store.messageIsError ? .orange : .white.opacity(0.6)).lineLimit(2)
                    } else {
                        Text(T("선택 \(FAKit.bytes(store.selectedBytes)) · 지원 파일 먼저, 앱은 마지막", "\(FAKit.bytes(store.selectedBytes)) selected · support files first, app last"))
                            .font(.island(.caption)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    if store.trashing {
                        ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                    } else if confirm {
                        Button(T("\(store.leftovers.filter(\.selected).count)개 휴지통으로", "Move \(store.leftovers.filter(\.selected).count) to Trash")) {
                            confirm = false
                            store.trashSelected()
                        }
                        .buttonStyle(FAPillStyle(tone: .destructive))
                    } else {
                        Button(T("휴지통으로", "Move to Trash")) { confirm = true }
                            .buttonStyle(FAPillStyle())
                            .disabled(store.scanning || store.running != nil || !store.leftovers.contains(where: \.selected))
                            .help(T("한 번 더 눌러 확인. 휴지통에서 되돌려 놓을 수 있음", "Click again to confirm. Restore with Put Back in the Trash"))
                    }
                }
            }
        } else {
            VStack(spacing: 5) {
                Image(systemName: "trash").font(.island(.title1))
                Text(T("앱을 고르면 함께 지울 파일을 보여 줌", "Pick an app to see the files that go with it")).font(.island(.footnote))
                Text(T("번들 ID가 정확히 같은 지원 파일·캐시·환경설정·컨테이너·저장 상태·로그·런치 에이전트. 모두 휴지통으로 옮기며 영구 삭제하지 않음. Apple 앱과 이 앱은 목록에 없음.",
                       "Support files, caches, preferences, containers, saved state, logs and launch agents with the exact bundle ID. Everything goes to the Trash, never deleted. Apple apps and this app aren't listed."))
                    .font(.island(.caption)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 설정 화면

private struct PkgSettings: View {
    let defaults: ModuleDefaults
    @State private var appStore = true
    @State private var sparkle = true
    private let brew = PkgBrewStore.findBrew()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Homebrew") {
                Text(brew ?? T("없음 (brew.sh에서 설치)", "Not found (install from brew.sh)")).foregroundStyle(.secondary)
            }
            Toggle(T("업데이트 확인에 App Store 앱 포함 (번들 ID를 itunes.apple.com 조회에 보냄)",
                     "Include App Store apps in update checks (sends bundle IDs to itunes.apple.com)"), isOn: $appStore)
                .onChange(of: appStore) { _, v in defaults.set(v, "checkAppStore") }
            Toggle(T("업데이트 확인에 Sparkle 앱 포함 (각 앱의 업데이트 주소에 접속)",
                     "Include Sparkle apps in update checks (contacts each app's update feed)"), isOn: $sparkle)
                .onChange(of: sparkle) { _, v in defaults.set(v, "checkSparkle") }
            Text(T("설치·업그레이드·제거는 탭에서 누를 때만 비대화식으로 실행한다. 관리자 비밀번호가 필요한 cask는 실패하며, 명령을 복사해 터미널에서 실행하면 된다. 앱 제거는 휴지통으로만 옮긴다.",
                   "Install, upgrade and uninstall run only when you click, non-interactively. Casks that need an admin password fail; copy the command and run it in Terminal. Uninstall only moves items to the Trash."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("앱 제거로 다른 앱의 컨테이너 크기를 잴 때 macOS가 '다른 앱의 데이터 접근' 허용을 물을 수 있다. 응용 프로그램 폴더의 앱을 옮길 수 없으면 Finder 방식으로 넘기며 macOS가 비밀번호를 물을 수 있다.",
                   "Measuring another app's container may make macOS ask for access to other apps' data. If an app can't be moved directly, it's handed to Finder, which may ask for your password."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            appStore = defaults.bool("checkAppStore", default: true)
            sparkle = defaults.bool("checkSparkle", default: true)
        }
    }
}

// MARK: - 자체 검사 (읽기만: 설치·제거·휴지통 없음)

enum PkgSelfTest {
    static func run(processes: FAProcessGroup) -> [String] {
        var lines: [String] = []
        if let brew = PkgBrewStore.findBrew() {
            let v = processes.run(brew, ["--version"], env: PkgBrewStore.queryEnv, timeout: 60)
            lines.append("brew \(brew): \(v?.outText.split(separator: "\n").first ?? "?")")
            if let r = processes.run(brew, ["info", "--json=v2", "--installed"], env: PkgBrewStore.queryEnv, timeout: 180),
               let p = PkgBrewStore.parseInstalled(r.out) {
                let casks = p.leaves.filter(\.isCask).count
                lines.append("installed: \(p.leaves.count - casks) formulae on request, \(p.deps.count) dependencies, \(casks) casks, cask apps \(p.caskApps.sorted().prefix(5))")
            } else { lines.append("FAIL brew info --installed") }
            if let r = processes.run(brew, ["outdated", "--json=v2", "--greedy-auto-updates"], env: PkgBrewStore.queryEnv, timeout: 180),
               let o = PkgBrewStore.parseOutdated(r.out) {
                lines.append("outdated: \(o.filter { !$0.isCask }.count) formulae, \(o.filter(\.isCask).count) casks; e.g. \(o.prefix(2).map { "\($0.name) \($0.version ?? "?")→\($0.latest ?? "?")" })")
            } else { lines.append("FAIL brew outdated") }
            // 설치·업그레이드와 같은 줄 단위 실행 경로를 읽기 전용 명령으로 확인
            var streamed: [String] = []
            var exitCode: Int32?
            let group = FAProcessGroup()
            group.stream(brew, ["info", "--formula", "jq"], env: PkgBrewStore.queryEnv,
                         onLine: { streamed.append($0) }, onExit: { exitCode = $0 })
            let deadline = Date().addingTimeInterval(60)
            while exitCode == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            lines.append("stream 'brew info --formula jq': exit \(exitCode.map(String.init) ?? "timeout"), \(streamed.count) lines, first '\(streamed.first ?? "")'")
            if let r = processes.run(brew, ["desc", "--search", "jq"], env: PkgBrewStore.queryEnv, timeout: 120) {
                let items = PkgBrewStore.parseDesc(r.outText)
                let jq = items.first { $0.name == "jq" }
                lines.append("search 'jq': \(items.count) results (\(items.filter(\.isCask).count) casks), jq desc='\(jq?.desc ?? "missing")'")
            } else { lines.append("FAIL brew desc --search") }
        } else {
            lines.append("brew not found → tab shows unsupported state with brew.sh link")
        }
        var shLines: [String] = []
        var shExit: Int32?
        let shGroup = FAProcessGroup()
        shGroup.stream("/bin/sh", ["-c", "echo one; echo two 1>&2; printf three; exit 3"],
                                onLine: { shLines.append($0) }, onExit: { shExit = $0 })
        let shDeadline = Date().addingTimeInterval(10)
        while shExit == nil && Date() < shDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        lines.append("stream runner: exit \(shExit.map(String.init) ?? "timeout") lines \(shLines) (expect 3, [one, two, three])")
        lines.append("name guard: jq=\(PkgBrewStore.validName("jq")) font-sf-pro=\(PkgBrewStore.validName("font-sf-pro")) '--force'=\(PkgBrewStore.validName("--force")) 'a b'=\(PkgBrewStore.validName("a b"))")
        lines.append("cask desc parse: \(PkgBrewStore.parseDesc("==> Casks\nfirefox: (Mozilla Firefox) Web browser").map { "\($0.name)|\($0.displayName ?? "")|\($0.desc)" })")

        let apps = PkgLocalApp.scan()
        let mas = apps.filter(\.isAppStore)
        let feeds = apps.filter { $0.feedURL != nil }
        lines.append("apps: \(apps.count), App Store receipts: \(mas.count) \(mas.prefix(4).map(\.name)), Sparkle feeds: \(feeds.count) (https \(feeds.filter { $0.feedURL?.scheme == "https" }.count))")
        lines.append("version compare: 1.10>1.9=\(PkgUpdateStore.isNewer("1.10", than: "1.9")) 2.0>2.0=\(PkgUpdateStore.isNewer("2.0", than: "2.0")) 4.53.276>4.53.3=\(PkgUpdateStore.isNewer("4.53.276", than: "4.53.3"))")
        let sample = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><title>2.1</title><sparkle:version>210</sparkle:version><sparkle:shortVersionString>2.1</sparkle:shortVersionString></item>
        <item><title>3.0b</title><sparkle:channel>beta</sparkle:channel><enclosure sparkle:version="300" sparkle:shortVersionString="3.0b" url="https://x"/></item>
        <item><title>2.5</title><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion><enclosure sparkle:version="250" url="https://x"/></item>
        <item><title>2.2</title><enclosure sparkle:version="220" sparkle:shortVersionString="2.2" url="https://x"/></item>
        </channel></rss>
        """
        let e = PkgAppcast.latest(Data(sample.utf8))
        lines.append("appcast parse: latest=\(e?.shortVersion ?? "nil") (\(e?.version ?? "nil")) expect 2.2 (220); beta and newer-macOS items skipped")

        // 앱 제거 후보 찾기 (읽기만, 다른 앱 컨테이너는 보지 않음)
        let candidates = apps.filter { !PkgUninstaller.isProtected($0) }
        lines.append("uninstall list: \(candidates.count) apps (Apple apps and this app hidden: \(apps.count - candidates.count))")
        if let sample = candidates.first(where: { $0.name == "Slack" }) ?? candidates.first {
            let rel = PkgUninstaller.related(to: sample, includeContainers: false, computeSizes: true)
            lines.append("related to \(sample.name) (\(sample.bundleID)): \(rel.map { "\($0.category)\($0.byName ? "(name)" : "") \(FAKit.shortPath($0.url)) \($0.size.map(FAKit.bytes) ?? "?")" })")
            lines.append("running check for \(sample.name): \(PkgUninstaller.runningProcess(for: sample) ?? "not running")")
        }

        // 네트워크 확인은 DMN_SELFTEST_NETWORK=1 일 때만
        if ProcessInfo.processInfo.environment["DMN_SELFTEST_NETWORK"] == "1" {
            let session = URLSession(configuration: .ephemeral)
            let sema = DispatchSemaphore(value: 0)
            var out: [String] = []
            Task.detached {
                do {
                    let r = try await PkgUpdateStore.appStoreUpdates(Array(mas.prefix(10)), session: session)
                    out.append("App Store lookup (\(min(10, mas.count)) apps): \(r.count) updates \(r.map { "\($0.name) \($0.installed)→\($0.latest)" })")
                } catch { out.append("App Store lookup failed: \(error.localizedDescription)") }
                let (s, skipped, failed) = await PkgUpdateStore.sparkleUpdates(Array(feeds.prefix(5)), session: session)
                out.append("Sparkle (\(min(5, feeds.count)) feeds): \(s.count) updates \(s.map { "\($0.name) \($0.installed)→\($0.latest)" }), skipped \(skipped), failed \(failed)")
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 60)
            lines += out
        } else {
            lines.append("network checks skipped (set DMN_SELFTEST_NETWORK=1)")
        }
        lines.append("no install, upgrade, uninstall or trash performed")
        return lines
    }
}
