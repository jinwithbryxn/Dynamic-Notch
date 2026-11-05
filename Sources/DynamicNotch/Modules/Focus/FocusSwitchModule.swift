import AppKit
import SwiftUI

/// Focus 전환: macOS가 집중 모드를 직접 바꾸는 공개 API를 주지 않아, 사용자가 만든 단축어를 실행한다.
/// 단축어 이름이 정한 앞글자(기본 "Focus")로 시작하면 모드 버튼으로 보인다. 단축어는 사용자가 누를 때만 실행한다.
final class FocusSwitchModule: NotchModule, ObservableObject {
    let id = "focusswitch"
    var title: String { T("Focus 전환", "Focus Switch") }
    let symbol = "moon.circle"
    var enabledByDefault: Bool { false }

    @Published private(set) var shortcuts: [String]?
    @Published private(set) var loading = false
    @Published private(set) var lastRun: (name: String, ok: Bool, message: String?)?
    private var context: ModuleContext?

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    var prefix: String { defaults.string("prefix", default: "Focus") }

    /// 모드 단축어 (앞글자로 거른 것)
    var modeShortcuts: [String] {
        let p = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        return (shortcuts ?? []).filter { p.isEmpty || $0.lowercased().hasPrefix(p) }
    }

    /// 버튼에 보일 이름 ("Focus 업무" → "업무", "Focus: Off" → "Off")
    func modeName(_ shortcut: String) -> String {
        let p = prefix.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, shortcut.lowercased().hasPrefix(p.lowercased()) else { return shortcut }
        let rest = shortcut.dropFirst(p.count).trimmingCharacters(in: CharacterSet(charactersIn: " :-·–"))
        return rest.isEmpty ? shortcut : rest
    }

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }

    func reload() {
        guard !loading else { return }
        loading = true
        TFShortcuts.list { [weak self] names in
            self?.shortcuts = names
            self?.loading = false
        }
    }

    func run(_ name: String) {
        TFShortcuts.run(name) { [weak self] ok, message in
            guard let self else { return }
            self.lastRun = (name, ok, message)
            self.context?.notice(ok ? T("Focus: \(self.modeName(name))", "Focus: \(self.modeName(name))") : T("단축어 실행 실패", "Shortcut failed"),
                                 ok ? T("단축어를 실행했어요", "Shortcut ran") : (message ?? name),
                                 symbol: ok ? "moon.fill" : "exclamationmark.triangle.fill", tint: ok ? .indigo : .yellow, duration: 3)
        }
    }

    static func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    static func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func tabView() -> AnyView? { AnyView(FocusSwitchTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 190) }

    func paletteActions() -> [PaletteAction] {
        modeShortcuts.map { name in
            PaletteAction(id: "focusswitch.\(name)", title: T("Focus 전환: \(modeName(name))", "Switch Focus: \(modeName(name))"),
                          subtitle: name, symbol: "moon.fill", keywords: ["focus", "집중", "방해 금지", "dnd"]) { [weak self] in self?.run(name) }
        }
    }

    func settingsView() -> AnyView? { AnyView(FocusSwitchSettings()) }

    func selfTest() -> [String] {
        guard TFShortcuts.isAvailable else { return ["shortcuts CLI missing at \(TFShortcuts.tool) -> unsupported"] }
        guard let names = TFShortcuts.listSync() else { return ["shortcuts list failed"] }
        shortcuts = names
        let modes = modeShortcuts
        return ["shortcuts list: \(names.count) shortcuts (not run)",
                "prefix '\(prefix)': \(modes.count) mode shortcuts \(modes.prefix(5).map { modeName($0) })",
                "focus state: \(TFSystem.focusState.map { $0 ? "on" : "off" } ?? "unknown (no Focus Status permission)")"]
    }
}

private struct FocusSwitchTab: View {
    @ObservedObject var module: FocusSwitchModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("Focus 전환", "Switch Focus")).font(.island(.callout, .semibold))
                if let on = TFSystem.focusState {
                    Text(on ? T("지금 켜짐", "On now") : T("지금 꺼짐", "Off now"))
                        .font(.island(.caption)).foregroundStyle(on ? .indigo : .white.opacity(0.5))
                }
                Spacer()
                TFPillButton(title: module.loading ? T("불러오는 중", "Loading") : T("새로 고침", "Refresh"), symbol: "arrow.clockwise",
                             help: T("단축어 목록 새로 고침", "Refresh the shortcut list")) { module.reload() }
                TFPillButton(title: T("Focus 설정", "Focus Settings"), symbol: "gearshape") { FocusSwitchModule.openFocusSettings() }
            }
            if !TFShortcuts.isAvailable {
                TFUnsupportedBox(title: T("단축어 도구가 없어요", "The Shortcuts tool is missing"),
                                 reason: T("/usr/bin/shortcuts 가 없어 단축어를 실행할 수 없어요.", "/usr/bin/shortcuts isn't available, so shortcuts can't run."),
                                 alternative: T("대안: 제어 센터나 Focus 설정에서 직접 바꾸세요.", "Alternative: switch in Control Center or Focus settings."),
                                 buttonTitle: T("Focus 설정", "Focus Settings")) { FocusSwitchModule.openFocusSettings() }
            } else if module.shortcuts == nil {
                Text(module.loading ? T("단축어 목록을 읽는 중…", "Reading shortcuts…") : T("목록을 불러오면 모드 버튼이 보여요.", "Load the list to see mode buttons."))
                    .font(.island(.footnote)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            } else if module.modeShortcuts.isEmpty {
                TFUnsupportedBox(title: T("'\(module.prefix)'로 시작하는 단축어가 없어요", "No shortcuts start with '\(module.prefix)'"),
                                 reason: T("macOS는 Focus를 직접 바꾸는 API를 주지 않아 단축어로 바꿔요. 단축어 앱에서 '집중 모드 설정' 동작을 넣고 이름을 '\(module.prefix) 업무', '\(module.prefix) 끄기'처럼 지으세요.",
                                           "macOS has no API to switch Focus directly, so it goes through Shortcuts. In Shortcuts, add a 'Set Focus' action and name it like '\(module.prefix) Work' or '\(module.prefix) Off'."),
                                 alternative: T("만든 뒤 새로 고침을 누르세요.", "Then press Refresh."),
                                 buttonTitle: T("단축어 열기", "Open Shortcuts")) { FocusSwitchModule.openShortcutsApp() }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(module.modeShortcuts, id: \.self) { name in
                        Button { module.run(name) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: module.modeName(name)))
                                Text(module.modeName(name)).lineLimit(1)
                            }
                            .font(.island(.subhead))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .help(T("단축어 '\(name)' 실행", "Run shortcut '\(name)'"))
                        .accessibilityLabel(module.modeName(name))
                    }
                }
                if let r = module.lastRun {
                    Text(r.ok ? T("'\(r.name)' 실행함", "Ran '\(r.name)'") : T("'\(r.name)' 실패: \(r.message ?? "")", "'\(r.name)' failed: \(r.message ?? "")"))
                        .font(.island(.caption)).foregroundStyle(r.ok ? .white.opacity(0.5) : .yellow).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .onAppear { if module.shortcuts == nil { module.reload() } }
    }

    private func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("off") || n.contains("끄기") || n.contains("해제") { return "moon.zzz" }
        if n.contains("work") || n.contains("업무") || n.contains("일") { return "briefcase.fill" }
        if n.contains("sleep") || n.contains("수면") { return "bed.double.fill" }
        if n.contains("personal") || n.contains("개인") { return "person.fill" }
        if n.contains("dnd") || n.contains("방해") { return "moon.fill" }
        return "moon.circle.fill"
    }
}

private struct FocusSwitchSettings: View {
    @StateObject private var prefs = TFPrefs(module: "focusswitch")
    @State private var names: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(T("단축어 이름 앞글자", "Shortcut name prefix"), text: prefs.string("prefix", "Focus"))
            TFSettingsNote(text: T("이 글자로 시작하는 단축어가 Focus 탭의 모드 버튼이 돼요. 단축어 앱에서 새 단축어 → '집중 모드 설정'(Set Focus) 동작 → 모드와 켜기/끄기를 고르고 이름을 'Focus 업무'처럼 지으세요. 끄는 단축어도 'Focus 끄기'로 하나 만들어 두면 편해요.",
                                   "Shortcuts whose names start with this become mode buttons. In Shortcuts: New Shortcut → 'Set Focus' action → pick the mode and on/off, then name it like 'Focus Work'. An 'Focus Off' shortcut is handy too."))
            HStack {
                Button(T("단축어 열기", "Open Shortcuts")) { FocusSwitchModule.openShortcutsApp() }
                Button(T("Focus 설정 열기", "Open Focus Settings")) { FocusSwitchModule.openFocusSettings() }
                Button(T("목록 확인", "Check List")) { TFShortcuts.list { names = $0 } }
            }
            if let names {
                let p = prefs.string("prefix", "Focus").wrappedValue.lowercased()
                let modes = names.filter { p.isEmpty || $0.lowercased().hasPrefix(p) }
                Text(modes.isEmpty ? T("맞는 단축어 없음 (전체 \(names.count)개)", "No matching shortcuts (\(names.count) total)")
                                   : T("맞는 단축어: ", "Matching: ") + modes.joined(separator: ", "))
                    .font(.caption)
            }
            TFSettingsNote(text: T("단축어는 버튼을 누를 때만 실행해요. 켜진 모드 이름 표시는 기존 Focus 감지 기능(전체 디스크 접근)이 맡아요.",
                                   "Shortcuts run only when you press a button. Showing the active mode name is handled by the existing Focus detection (Full Disk Access)."))
        }
    }
}
