import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 발표 도구 (M-G-011 키 입력 HUD, M-G-012 커서 강조, M-G-014 멈춘 포인터 숨기기).
/// 각 기능은 탭에서 직접 켜야 동작하고 기본은 모두 꺼짐. 포인터 테마(M-G-013)는 보류.
final class PresenterModule: NotchModule {
    let id = "presenter"
    var title: String { T("발표 도구", "Presenter") }
    let symbol = "cursorarrow.rays"
    /// 이벤트 탭·전역 감시·오버레이를 쓰므로 기본 꺼짐
    var enabledByDefault: Bool { false }

    final class State: ObservableObject {
        private let d = ModuleDefaults(module: "presenter")
        var onChange: (() -> Void)?
        @Published var keystrokes: Bool { didSet { d.set(keystrokes, "keystrokes"); onChange?() } }
        @Published var combosOnly: Bool { didSet { d.set(combosOnly, "combosOnly") } }
        @Published var inNotch: Bool { didSet { d.set(inNotch, "inNotch") } }
        @Published var ripples: Bool { didSet { d.set(ripples, "ripples"); onChange?() } }
        @Published var halo: Bool { didSet { d.set(halo, "halo"); onChange?() } }
        @Published var spotlight: Bool { didSet { d.set(spotlight, "spotlight"); onChange?() } }
        @Published var idleHide: Bool { didSet { d.set(idleHide, "idleHide"); onChange?() } }
        @Published var idleSeconds: Double { didSet { d.set(idleSeconds, "idleSeconds"); onChange?() } }
        @Published var message: String?
        @Published var inputGranted = CPPermission.inputMonitoring.granted
        @Published var axGranted = CPPermission.accessibility.granted

        init() {
            keystrokes = d.bool("keystrokes", default: false)
            combosOnly = d.bool("combosOnly", default: true)
            inNotch = d.bool("inNotch", default: false)
            ripples = d.bool("ripples", default: false)
            halo = d.bool("halo", default: false)
            spotlight = d.bool("spotlight", default: false)
            idleHide = d.bool("idleHide", default: false)
            idleSeconds = d.double("idleSeconds", default: 3)
        }

        func refreshPermissions() {
            inputGranted = CPPermission.inputMonitoring.granted
            axGranted = CPPermission.accessibility.granted
        }
    }

    let state = State()
    private var context: ModuleContext?
    private let tap = CPKeystrokeTap()
    private let hud = CPKeystrokeHUD()
    private let cursor = CPCursorEffects()
    private let idle = CPIdleCursorHider()
    private var running = false

    func start(context: ModuleContext) {
        self.context = context
        running = true
        state.onChange = { [weak self] in self?.apply() }
        tap.onKey = { [weak self] e in self?.key(e) }
        apply()
    }

    func stop() {
        running = false
        state.onChange = nil
        tap.stop()
        tap.onKey = nil
        hud.close()
        cursor.stop()
        idle.stop()
        context = nil
    }

    func settingsChanged() {
        // 설정 도우미에서 바뀐 값은 다음 시작 때 반영되므로 지금 상태만 맞춘다
        apply()
    }

    /// 켜짐 상태와 실제 탭·오버레이를 맞춘다
    private func apply() {
        guard running else { return }
        state.refreshPermissions()
        var msg: [String] = []
        if state.keystrokes {
            if !tap.start() {
                msg.append(T("키 입력 표시: 입력 모니터링 권한이 필요함 (허용 후 앱 다시 시작)", "Keystrokes: Input Monitoring needed (relaunch after allowing)"))
            }
        } else {
            tap.stop()
            hud.close()
        }
        cursor.update(ripples: state.ripples, halo: state.halo, spotlight: state.spotlight && state.axGranted)
        if state.spotlight && !state.axGranted {
            msg.append(T("스포트라이트: 손쉬운 사용 권한이 필요함", "Spotlight: Accessibility needed"))
        }
        idle.idleSeconds = state.idleSeconds
        if state.idleHide {
            if !idle.start() { msg.append(T("포인터 숨기기: 이 macOS에서 필요한 비공개 함수를 찾지 못함", "Pointer hiding: required private functions not found on this macOS")) }
        } else {
            idle.stop()
        }
        state.message = msg.isEmpty ? nil : msg.joined(separator: "\n")
    }

    private func key(_ e: CGEvent) {
        guard let label = CPKeystrokeTap.label(for: e, combosOnly: state.combosOnly) else { return }
        if state.inNotch, let center = context?.center {
            center.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .compact, duration: 1.2,
                                      symbol: "keyboard", value: .text(label), wing: NotchActivity.compactWing))
        } else {
            hud.show(label)
        }
    }

    func tabView() -> AnyView? { AnyView(PresenterTab(module: self, state: state)) }
    var tabContentSize: CGSize { CGSize(width: 600, height: 280) }

    func paletteActions() -> [PaletteAction] {
        [
            PaletteAction(id: "presenter.keys", title: state.keystrokes ? T("키 입력 표시 끄기", "Turn Off Keystroke HUD") : T("키 입력 표시 켜기", "Turn On Keystroke HUD"),
                          symbol: "keyboard", keywords: ["keystroke", "키 입력", "hud"]) { [weak self] in self?.state.keystrokes.toggle() },
            PaletteAction(id: "presenter.ripples", title: state.ripples ? T("클릭 물결 끄기", "Turn Off Click Ripples") : T("클릭 물결 켜기", "Turn On Click Ripples"),
                          symbol: "cursorarrow.click", keywords: ["cursor", "커서", "click", "클릭"]) { [weak self] in self?.state.ripples.toggle() },
        ]
    }

    func selfTest() -> [String] {
        [
            "input monitoring (preflight): \(CPPermission.inputMonitoring.granted)",
            "accessibility (no prompt): \(CPPermission.accessibility.granted)",
            "idle cursor private functions found: \(CPIdleCursorHider.available)",
            "secure input on now: \(IsSecureEventInputEnabled())",
            "screens for cursor overlays: \(NSScreen.screens.count)",
            "reduce motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)",
            "label sample (keycode 40 + cmd): \(Self.sampleLabel())",
        ] + Self.renderHUD()
    }

    /// 키캡 화면 그리기 확인 (패널을 띄우지 않음)
    private static func renderHUD() -> [String] {
        let hud = CPKeystrokeHUD()
        hud.entries = ["⇧⌘K", "⌘C", "esc"].map { CPKeystrokeHUD.Entry(text: $0) }
        return CPTestImages.renderView(CPKeystrokeHUDView(hud: hud), size: CGSize(width: 640, height: 90), name: "keystroke-hud.png")
            .map { ["wrote \($0)"] } ?? []
    }

    /// 실제 입력 없이 만든 이벤트로 표시 글자를 확인한다 (게시하지 않음)
    private static func sampleLabel() -> String {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: true) else { return "?" }
        e.flags = [.maskCommand, .maskShift]
        let a = CPKeystrokeTap.label(for: e, combosOnly: true) ?? "nil"
        e.flags = []
        let b = CPKeystrokeTap.label(for: e, combosOnly: true) ?? "hidden"
        return "\(a), plain → \(b)"
    }
}

private struct PresenterTab: View {
    let module: PresenterModule
    @ObservedObject var state: PresenterModule.State

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    CPToggleRow(symbol: "keyboard", title: T("키 입력 표시", "Keystroke HUD"),
                                detail: T("누른 단축키를 키캡으로. 비밀번호 칸은 안 보임", "Shows shortcuts as keycaps. Password fields stay hidden"),
                                isOn: $state.keystrokes)
                    HStack(spacing: 10) {
                        Toggle(T("수정키 조합만", "Shortcuts only"), isOn: $state.combosOnly)
                            .help(T("⌘·⌃·⌥ 조합과 특수 키만 보여 주고 일반 글자는 숨긴다", "Show only ⌘/⌃/⌥ combos and special keys"))
                        Toggle(T("노치에 표시", "Show in notch"), isOn: $state.inNotch)
                    }
                    .toggleStyle(.checkbox).font(.system(size: 10.5)).padding(.leading, 8)
                    CPPermissionLine(permission: .inputMonitoring, granted: state.inputGranted).padding(.leading, 8)
                    CPToggleRow(symbol: "cursorarrow.motionlines", title: T("멈춘 포인터 숨기기", "Hide idle pointer"),
                                detail: CPIdleCursorHider.available ? T("\(Int(state.idleSeconds))초 동안 안 움직이면 숨김 · 비공개 API", "Hides after \(Int(state.idleSeconds)) s · private API")
                                    : T("지원 안 됨: 비공개 함수를 찾지 못함", "Unsupported: private functions missing"),
                                isOn: $state.idleHide)
                    Stepper(T("숨기기까지 \(Int(state.idleSeconds))초", "Hide after \(Int(state.idleSeconds)) s"), value: $state.idleSeconds, in: 1...30)
                        .font(.system(size: 10.5)).controlSize(.mini).padding(.leading, 8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    CPToggleRow(symbol: "cursorarrow.click", title: T("클릭 물결", "Click ripples"),
                                detail: T("오른쪽 클릭은 이중 원 · 권한 불필요", "Right click shows two rings · no permission"), isOn: $state.ripples)
                    CPToggleRow(symbol: "circle.dashed", title: T("포인터 후광", "Pointer halo"),
                                detail: T("커서를 따라다니고 누르면 줄어듦", "Follows the pointer, shrinks on press"), isOn: $state.halo)
                    CPToggleRow(symbol: "flashlight.on.fill", title: T("스포트라이트", "Spotlight"),
                                detail: T("⌃⌥를 누르고 있는 동안 커서 주변만 밝게", "Hold ⌃⌥ to dim all but the pointer"), isOn: $state.spotlight)
                    CPPermissionLine(permission: .accessibility, granted: state.axGranted).padding(.leading, 8)
                }
            }
            if let m = state.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            CPUnsupported(title: T("포인터 테마·크기 보류", "Pointer themes deferred"),
                          reason: T("다른 앱 위의 시스템 커서를 다시 칠하는 공개 API가 없어 비공개 커서 API가 필요하고, macOS 업데이트마다 깨질 위험이 크다.",
                                    "No public API recolors the system cursor over other apps; private cursor APIs would break across macOS updates."),
                          alternative: T("시스템 설정 › 손쉬운 사용 › 디스플레이 › 포인터에서 크기·색을 바꾼다.", "System Settings › Accessibility › Display › Pointer changes size and color."))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { state.refreshPermissions() }
    }
}
