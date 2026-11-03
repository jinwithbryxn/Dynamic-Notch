import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 명령 팔레트 전역 단축키 저장 (기본 ⌃⌥K)
enum PaletteHotKey {
    static let defaultShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
    private static var defaults: ModuleDefaults { ModuleDefaults(module: "palette") }

    static var current: HotKeyCenter.Shortcut {
        if let data = defaults.data("hotkey"), let s = try? JSONDecoder().decode(HotKeyCenter.Shortcut.self, from: data) { return s }
        return defaultShortcut
    }

    static func set(_ shortcut: HotKeyCenter.Shortcut?) {
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) }, "hotkey")
    }
}

/// 명령 팔레트 입력 해석
enum PaletteParser {
    /// "10분 타이머", "타이머 1시간 30분", "timer 10m", "25 min", "90초" → 초. 시간 표현만 있을 때만 해석한다.
    static func timerSeconds(_ query: String) -> Int? {
        var q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let hasKeyword = q.contains("타이머") || q.contains("timer")
        for word in ["타이머", "timer", "시작", "start"] { q = q.replacingOccurrences(of: word, with: " ") }
        q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        // 숫자만 있으면 '타이머'라는 말이 있을 때 분으로 본다
        if let n = Int(q) { return hasKeyword && n > 0 && n <= 1440 ? n * 60 : nil }
        let pattern = #"(\d+)\s*(시간|hours?|hrs?|h|분|minutes?|mins?|m|초|seconds?|secs?|s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = q as NSString
        let matches = regex.matches(in: q, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        // 시간 표현 말고 다른 글자가 섞여 있으면 타이머가 아니다 (예: "5 usd in eur")
        let rest = regex.stringByReplacingMatches(in: q, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var total = 0
        for m in matches {
            let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let unit = ns.substring(with: m.range(at: 2))
            switch unit {
            case "시간", "h", "hr", "hrs", "hour", "hours": total += n * 3600
            case "초", "s", "sec", "secs", "second", "seconds": total += n
            default: total += n * 60
            }
        }
        return total > 0 && total <= 86_400 ? total : nil
    }
}

/// 단축키 기록 버튼 (설정 창). 누른 뒤 수정키와 함께 키를 누르면 저장된다. Esc는 취소.
struct HotKeyRecorder: View {
    var shortcut: HotKeyCenter.Shortcut
    var onChange: (HotKeyCenter.Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? T("키를 누르세요…", "Press keys…") : shortcut.display) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stop() }
            if event.keyCode == UInt16(kVK_Escape) { return nil }
            let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: UInt32 = 0
            if f.contains(.command) { mods |= UInt32(cmdKey) }
            if f.contains(.option) { mods |= UInt32(optionKey) }
            if f.contains(.control) { mods |= UInt32(controlKey) }
            if f.contains(.shift) { mods |= UInt32(shiftKey) }
            // 수정키 없는 단축키는 글자 입력을 막으므로 받지 않는다
            guard mods & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
            onChange(HotKeyCenter.Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods))
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// 설정 → 확장 기능: 명령 팔레트 단축키, 기능별 켜기·독 고정·세부 설정
struct ModulesSettingsPage: View {
    @ObservedObject private var registry = ModuleRegistry.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var hotkeyOn = ModuleDefaults(module: "palette").bool("hotkeyEnabled", default: true)
    @State private var hotkey = PaletteHotKey.current
    @State private var query = ""

    private var modules: [NotchModule] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return registry.modules }
        return registry.modules.filter { $0.title.lowercased().contains(q) || $0.id.contains(q) }
    }

    var body: some View {
        Form {
            if permissions.walkthroughCurrent != nil || permissions.walkthroughGranted.contains(where: \.needsRelaunch) {
                Section { PermissionWalkthroughBar() }
            }
            IslandSettingsSection()
            Section {
                Toggle(T("전역 단축키로 명령 팔레트 열기", "Open the command palette with a global shortcut"), isOn: $hotkeyOn)
                    .onChange(of: hotkeyOn) { _, on in ModuleDefaults(module: "palette").set(on, "hotkeyEnabled") }
                HStack {
                    Text(T("단축키", "Shortcut"))
                    Spacer()
                    HotKeyRecorder(shortcut: hotkey) { new in
                        hotkey = new
                        PaletteHotKey.set(new)
                    }
                    Button(T("기본값", "Default")) {
                        hotkey = PaletteHotKey.defaultShortcut
                        PaletteHotKey.set(nil)
                    }
                }
                .disabled(!hotkeyOn)
            } header: {
                Text(T("명령 팔레트", "Command Palette"))
            } footer: {
                Text(T("펼친 노치에서 ⌘1–9로 칸을 옮기고 Esc로 닫습니다. 다른 앱이 이미 쓰는 조합이면 등록되지 않습니다.",
                       "In the open notch, ⌘1–9 switches pages and Esc closes it. A combination another app already uses cannot be registered."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField(T("기능 검색", "Search features"), text: $query)
                ForEach(modules, id: \.id) { m in
                    ModuleSettingsRow(module: m)
                }
            } header: {
                Text(T("기능", "Features"))
            } footer: {
                Text(T("끈 기능은 타이머·감시·오디오 캡처·네트워크 요청을 모두 멈춥니다. 권한이 필요한 기능은 처음부터 꺼져 있고, 켜면 필요한 권한을 차례로 묻습니다.",
                       "Turned-off features stop their timers, watchers, audio capture and network requests. Features that need permissions start turned off and ask for them in turn when you turn them on."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.startAutoRefresh() }
        .onDisappear { permissions.stopAutoRefresh() }
    }
}

private struct ModuleSettingsRow: View {
    let module: NotchModule
    @ObservedObject private var registry = ModuleRegistry.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var open = false

    var body: some View {
        let enabled = registry.isEnabled(module)
        // 자동화는 대상 앱이 켜져 있어야 알 수 있어 빼고 보여 준다
        let missing = (PermissionNeeds.modules[module.id] ?? []).filter { ![.granted, .needsAppRunning].contains(permissions.status($0)) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                Text(module.title)
                Spacer()
                if enabled, module.tabView() != nil {
                    Toggle(T("독", "Dock"), isOn: Binding(
                        get: { registry.isDocked(module.id) },
                        set: { registry.setDocked(module.id, $0) }))
                        .toggleStyle(.checkbox)
                        .help(T("펼친 노치 아래 독에 이 탭을 고정합니다", "Pin this tab to the dock under the open notch"))
                }
                if enabled, module.settingsView() != nil {
                    Button { withAnimation(.snappy(duration: 0.2)) { open.toggle() } } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(T("세부 설정", "Details"))
                }
                Toggle("", isOn: Binding(get: { enabled }, set: { on in
                    registry.setEnabled(module, on)
                    // 켜는 순간 이 기능에 필요한 권한을 차례로 묻는다
                    if on { permissions.startWalkthrough(PermissionNeeds.modules[module.id] ?? []) }
                }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(module.title)
            }
            if enabled, !missing.isEmpty {
                HStack(spacing: 8) {
                    Text(T("필요한 권한: \(missing.map(\.title).joined(separator: ", "))", "Needs: \(missing.map(\.title).joined(separator: ", "))"))
                        .font(.caption).foregroundStyle(.orange)
                    Button(T("허용", "Allow")) { permissions.startWalkthrough(missing) }
                        .controlSize(.small)
                        .disabled(permissions.walkthroughCurrent != nil)
                }
                .padding(.leading, 30)
            }
            if open, enabled, let view = module.settingsView() {
                view.padding(.leading, 30)
            }
        }
    }
}
