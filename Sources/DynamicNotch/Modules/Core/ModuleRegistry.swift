import SwiftUI

/// 모든 확장 기능을 들고, 켜짐 설정에 따라 시작·정지한다.
/// 본 앱에서는 `activate(context:)`로 켜진 기능을 시작하고, 설정 도우미에서는 목록과 설정 화면만 쓴다.
final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    let modules: [NotchModule]
    @Published private(set) var running: Set<String> = []
    private var context: ModuleContext?
    private var observer: NSObjectProtocol?

    private init() {
        modules = ModuleCatalog.makeAll()
    }

    func module(_ id: String) -> NotchModule? { modules.first { $0.id == id } }

    // MARK: 켜짐 설정 (기능 id별 "module.<id>.enabled")

    func isEnabled(_ module: NotchModule) -> Bool {
        ModuleDefaults(module: module.id).bool("enabled", default: module.enabledByDefault)
    }

    func setEnabled(_ module: NotchModule, _ on: Bool) {
        ModuleDefaults(module: module.id).set(on, "enabled")
        if context != nil { sync() }
        objectWillChange.send()
    }

    /// 본 앱에서는 실제로 돌고 있는지, 설정 도우미에서는 켜짐 설정을 본다
    private func isActive(_ m: NotchModule) -> Bool { context != nil ? running.contains(m.id) : isEnabled(m) }

    // MARK: 본 앱

    /// 본 앱 시작 시 한 번. 켜진 기능을 시작하고, 설정 도우미의 변경을 받아 반영한다.
    func activate(context: ModuleContext) {
        self.context = context
        observer = DistributedNotificationCenter.default().addObserver(
            forName: ModuleDefaults.changedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.sync()
            self.objectWillChange.send()   // 독 고정·순서가 바뀌었을 수 있다
            if let id = note.object as? String, self.running.contains(id) { self.module(id)?.settingsChanged() }
        }
        sync()
    }

    /// 켜짐 설정과 실제 실행 상태를 맞춘다.
    func sync() {
        guard let context else { return }
        for m in modules {
            let on = isEnabled(m)
            if on, !running.contains(m.id) {
                m.start(context: context)
                running.insert(m.id)
            } else if !on, running.contains(m.id) {
                m.stop()
                running.remove(m.id)
            }
        }
    }

    /// 진행 중인 작업이 있어 메모리 지킴이가 다시 시작하면 안 되는지 (기능이 `isBusy`로 알린다)
    var isBusy: Bool { modules.contains { running.contains($0.id) && $0.isBusy } }

    func stopAll() {
        for m in modules where running.contains(m.id) { m.stop() }
        running.removeAll()
    }

    /// 확장 패널에 보일 탭 (켜진 기능 중 탭 화면이 있는 것, 설정한 순서대로)
    var tabs: [NotchModule] {
        let order = UserDefaults.standard.stringArray(forKey: "module.tabOrder") ?? []
        func rank(_ m: NotchModule) -> Int { order.firstIndex(of: m.id) ?? (order.count + (modules.firstIndex { $0 === m } ?? 0)) }
        return modules.filter { isActive($0) && $0.tabView() != nil }.sorted { rank($0) < rank($1) }
    }

    /// 독(확장 패널 아래 떠 있는 줄)에 고정한 탭. 고른 적이 없으면 켜진 탭 앞에서 4개.
    var dockTabs: [NotchModule] {
        let all = tabs
        guard let pins = UserDefaults.standard.stringArray(forKey: Self.dockKey) else { return Array(all.prefix(4)) }
        return pins.compactMap { id in all.first { $0.id == id } }
    }

    static let dockKey = "module.dockTabs"

    func isDocked(_ id: String) -> Bool { dockTabs.contains { $0.id == id } }

    func setDocked(_ id: String, _ on: Bool) {
        var pins = dockTabs.map(\.id)
        pins.removeAll { $0 == id }
        if on { pins.append(id) }
        UserDefaults.standard.set(pins, forKey: Self.dockKey)
        DistributedNotificationCenter.default().postNotificationName(
            ModuleDefaults.changedNotification, object: "_registry", userInfo: nil, deliverImmediately: true)
        objectWillChange.send()
    }

    /// 명령 팔레트 결과: 입력이 비면 고정 동작 전체, 아니면 이름·별칭이 맞는 동작과 즉석 결과
    func paletteResults(for query: String) -> [PaletteAction] {
        let active = modules.filter { running.contains($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let fixed = active.flatMap { $0.paletteActions() }
        if q.isEmpty { return fixed }
        let matched = fixed.filter { a in
            ([a.title, a.subtitle ?? ""] + a.keywords).contains { $0.lowercased().contains(q) }
        }
        return active.flatMap { $0.paletteResults(for: query) } + matched
    }
}
