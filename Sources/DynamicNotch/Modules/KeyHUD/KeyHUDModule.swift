import AppKit
import SwiftUI

/// 키 HUD: 키보드 백라이트 슬라이더·팔레트 조절(비공개 CoreBrightness, 기존 Brightness 어댑터 재사용),
/// Caps Lock HUD(수정키 플래그만 읽음, 켜 둔 동안 초당 4번), 이 모듈 HUD의 모양 설정.
final class KeyHUDModule: NotchModule {
    let id = "keyhud"
    var title: String { T("키 HUD", "Key HUD") }
    let symbol = "light.max"
    var enabledByDefault: Bool { false }

    enum Style: String, CaseIterable { case app, number, bar, ring }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    private var context: ModuleContext?
    private var capsTimer: Timer?
    private var capsState: Bool?

    var capsEnabled: Bool { defaults.bool("capsLock", default: true) }
    var style: Style { Style(rawValue: defaults.string("style", default: Style.app.rawValue)) ?? .app }
    /// 0이면 앱 HUD 표시 시간을 따른다
    var duration: Double { defaults.double("duration", default: 0) }

    func start(context: ModuleContext) {
        self.context = context
        applySettings()
    }

    func stop() {
        capsTimer?.invalidate(); capsTimer = nil
        capsState = nil
        context = nil
    }

    func settingsChanged() { applySettings() }

    private func applySettings() {
        if capsEnabled, context != nil {
            guard capsTimer == nil else { return }
            capsState = Self.capsLockOn()
            // 입력 모니터링 권한 없이 수정키 상태만 읽는다 (CGEventSource 플래그, 초당 4번)
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollCaps() }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            capsTimer = t
        } else {
            capsTimer?.invalidate(); capsTimer = nil
            capsState = nil
        }
    }

    static func capsLockOn() -> Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) }

    private func pollCaps() {
        let on = Self.capsLockOn()
        defer { capsState = on }
        guard let old = capsState, old != on else { return }
        context?.center.post(NotchActivity(
            kind: .hud, priority: ActivityPriority.hud, duration: hudDuration,
            symbol: on ? "capslock.fill" : "capslock", tint: on ? .green : .white,
            value: .text(on ? T("켬", "On") : T("끔", "Off")), wing: 54, valueTint: on ? .green : .white.opacity(0.7)))
    }

    private var hudDuration: Double { duration > 0 ? duration : AppSettings.shared.hudDuration }

    // MARK: 키보드 백라이트

    var keyboardAvailable: Bool { Brightness.keyboardAvailable && Brightness.keyboard() != nil }

    func setKeyboard(_ value: Float, showHUD: Bool) {
        guard Brightness.keyboardAvailable else { return }
        let v = min(1, max(0, value))
        Brightness.setKeyboard(v)
        if showHUD { postKeyboardHUD(v) }
    }

    func stepKeyboard(up: Bool) {
        let cur = Brightness.keyboard() ?? 0
        let unit: Float = 1 / 16
        setKeyboard(((cur / unit).rounded() + (up ? 1 : -1)) * unit, showHUD: true)
    }

    private func postKeyboardHUD(_ v: Float) {
        let value: ActivityValue
        let s = style == .app ? AppSettings.shared.hudStyle.rawValue : style.rawValue
        switch s {
        case "bar": value = .bar(Double(v))
        case "ring": value = .ring(Double(v))
        default: value = .bigNumber(Double(v))
        }
        context?.center.post(NotchActivity(
            kind: .hud, priority: ActivityPriority.hud, duration: hudDuration,
            symbol: v < 0.01 ? "light.min" : "light.max", tint: .white, value: value, wing: s == "bar" ? 66 : 54))
    }

    // MARK: 화면

    func tabView() -> AnyView? { AnyView(KeyHUDTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 440, height: 146) }

    func paletteActions() -> [PaletteAction] {
        guard Brightness.keyboardAvailable else { return [] }
        return [
            PaletteAction(id: "keyhud.kbup", title: T("키보드 백라이트 밝게", "Keyboard Backlight Up"), symbol: "light.max",
                          keywords: ["keyboard", "backlight", "키보드", "백라이트"]) { [weak self] in self?.stepKeyboard(up: true) },
            PaletteAction(id: "keyhud.kbdown", title: T("키보드 백라이트 어둡게", "Keyboard Backlight Down"), symbol: "light.min",
                          keywords: ["keyboard", "backlight", "키보드", "백라이트"]) { [weak self] in self?.stepKeyboard(up: false) },
            PaletteAction(id: "keyhud.kboff", title: T("키보드 백라이트 끄기", "Keyboard Backlight Off"), symbol: "lightbulb.slash",
                          keywords: ["keyboard", "backlight", "키보드", "백라이트", "off"]) { [weak self] in self?.setKeyboard(0, showHUD: true) },
        ]
    }

    func settingsView() -> AnyView? { AnyView(KeyHUDSettings(module: self)) }

    func selfTest() -> [String] {
        [
            "keyboard backlight client available \(Brightness.keyboardAvailable)",
            "keyboard backlight level " + (Brightness.keyboard().map { String(format: "%.3f", $0) } ?? "unreadable"),
            "caps lock currently \(Self.capsLockOn() ? "on" : "off") (CGEventSource flags, no permission)",
            "app hud style \(AppSettings.shared.hudStyle.rawValue) duration \(AppSettings.shared.hudDuration)",
        ]
    }

    func set(_ value: Any?, _ name: String) { defaults.set(value, name); applySettings() }
}

private struct KeyHUDTab: View {
    let module: KeyHUDModule
    @State private var level: Double = 0
    @State private var available = false
    @State private var caps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SysCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "light.max")
                        Text(T("키보드 백라이트", "Keyboard backlight")).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if available {
                            Text(SysFmt.percent(level)).font(.system(size: 13, design: .rounded)).monospacedDigit()
                        }
                    }
                    if available {
                        HStack(spacing: 8) {
                            Image(systemName: "light.min").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                            // 사용자가 끌 때만 값을 쓴다 (화면이 열릴 때는 읽기만)
                            Slider(value: Binding(get: { level }, set: { level = $0; module.setKeyboard(Float($0), showHUD: false) }), in: 0...1)
                            .controlSize(.small)
                            .accessibilityLabel(T("키보드 밝기", "Keyboard brightness"))
                            Image(systemName: "light.max").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                            SysPillButton(title: T("끄기", "Off"), symbol: "lightbulb.slash") { level = 0; module.setKeyboard(0, showHUD: false) }
                        }
                    } else {
                        SysUnsupported(title: T("지원 안 됨", "Unsupported"),
                                       reason: T("백라이트 키보드가 없거나 CoreBrightness 클라이언트를 찾지 못했습니다.",
                                                 "No backlit keyboard, or the CoreBrightness client is unavailable."),
                                       alternative: T("대안: 제어 센터 › 키보드 밝기", "Alternative: Control Center › Keyboard Brightness"))
                    }
                }
            }
            .frame(height: 78)
            SysCard {
                HStack(spacing: 10) {
                    Image(systemName: caps ? "capslock.fill" : "capslock").font(.system(size: 18))
                        .foregroundStyle(caps ? .green : .white.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Caps Lock HUD").font(.system(size: 12, weight: .semibold))
                        Text(module.capsEnabled
                             ? T("켜고 끌 때 노치에 잠깐 표시 · 지금 \(caps ? "켬" : "끔")", "Shows briefly when toggled · now \(caps ? "on" : "off")")
                             : T("설정에서 꺼져 있음", "Turned off in settings"))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            available = module.keyboardAvailable
            level = Double(Brightness.keyboard() ?? 0)
            caps = KeyHUDModule.capsLockOn()
        }
    }
}

private struct KeyHUDSettings: View {
    let module: KeyHUDModule
    @State private var caps = true
    @State private var style = KeyHUDModule.Style.app
    @State private var duration = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("Caps Lock HUD (수정키 상태만 초당 4번 읽음, 권한 불필요)", "Caps Lock HUD (reads modifier flags 4× per second, no permission)"), isOn: $caps)
                .onChange(of: caps) { module.set($0, "capsLock") }
            Picker(T("이 모듈 HUD 모양", "HUD style for this module"), selection: $style) {
                Text(T("앱 HUD 설정 따름", "Follow app HUD style")).tag(KeyHUDModule.Style.app)
                Text(T("숫자", "Number")).tag(KeyHUDModule.Style.number)
                Text(T("가로 막대", "Bar")).tag(KeyHUDModule.Style.bar)
                Text(T("원형", "Ring")).tag(KeyHUDModule.Style.ring)
            }
            .frame(width: 320)
            .onChange(of: style) { module.set($0.rawValue, "style") }
            HStack {
                Text(T("표시 시간", "Duration"))
                Slider(value: $duration, in: 0...4, step: 0.5).frame(width: 160)
                    .onChange(of: duration) { module.set($0, "duration") }
                Text(duration == 0 ? T("앱 설정", "App setting") : String(format: "%.1f s", duration)).monospacedDigit()
            }
            Text(T("키보드 조명 키 HUD는 기존 HUD 기능이 처리합니다. 여기서는 슬라이더와 팔레트(⌘K) 조절을 더합니다. 노치 옆 팝업·색 반전·가장자리 막대는 노치 본체 변경이 필요해 아직 없습니다.",
                   "The illumination-key HUD stays with the built-in HUD feature; this module adds a slider and palette (⌘K) control. Beside-the-notch popups, inverted colours and edge bars need changes to the notch core and are not here yet."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            caps = module.capsEnabled
            style = module.style
            duration = module.duration
        }
    }
}
