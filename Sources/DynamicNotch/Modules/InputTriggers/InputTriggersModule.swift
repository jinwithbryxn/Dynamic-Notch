import AppKit
import SwiftUI

/// 수정키만 짧게 1–3번 누른 것을 센다. 다른 키·수정키와 함께 누르거나 길게 누르면 세지 않는다.
/// 시각을 받아 계산만 하므로 자체 검사에서 실제 키 입력 없이 시험할 수 있다.
struct ModifierTapDetector {
    var window: TimeInterval = 0.35       // 탭 사이 최대 간격 (감도)
    var maxHold: TimeInterval = 0.3       // 한 번 누른 시간 최대
    var typingGuard: TimeInterval = 0.5   // 직전 글자 입력 뒤 무시할 시간

    private(set) var count = 0
    private var downAt: TimeInterval?
    private var firstTapAt: TimeInterval?
    private var lastKeyAt: TimeInterval = -100
    private(set) var lastTapUpAt: TimeInterval = 0

    /// 대상 수정키 상태 변화. others = 다른 수정키가 함께 눌렸는지.
    mutating func flags(pressed: Bool, others: Bool, at t: TimeInterval) {
        if others { reset(); return }
        if pressed {
            if count > 0, t - lastTapUpAt > window { reset() }
            downAt = t
        } else if let d = downAt {
            downAt = nil
            guard t - d <= maxHold else { reset(); return }
            if count == 0 { firstTapAt = d }
            count = min(count + 1, 3)
            lastTapUpAt = t
        }
    }

    /// 일반 키 입력: 진행 중인 탭을 취소하고 타이핑 시각을 기록한다
    mutating func keyDown(at t: TimeInterval) {
        lastKeyAt = t
        reset()
    }

    /// 마지막 탭 뒤 window가 지났을 때 부른다. 확정된 횟수(타이핑 직후면 0)를 돌려주고 초기화.
    mutating func settle(at t: TimeInterval) -> Int {
        guard count > 0, t - lastTapUpAt >= window - 0.001 else { return 0 }
        let n = count
        let typedJustBefore = (firstTapAt ?? t) - lastKeyAt < typingGuard
        reset()
        return typedJustBefore ? 0 : n
    }

    mutating func reset() {
        count = 0
        downAt = nil
        firstTapAt = nil
    }
}

/// 수정키 탭: Control 등 수정키를 단독으로 1·2·3번 누르면 고른 동작(런처 휠·탭 열기·단축어·링크·창 배치)을 실행한다.
/// 전역 키 감시에 손쉬운 사용 권한이 필요해 기본 꺼짐. 트랙패드 탭·본체 노크는 지원 안 됨(이유는 설정에 표시).
final class InputTriggersModule: NotchModule {
    let id = "inputtriggers"
    var title: String { T("수정키 탭", "Modifier Taps") }
    let symbol = "command"
    var enabledByDefault: Bool { false }

    enum Modifier: String, CaseIterable, Identifiable {
        case control, option, command, shift, fn
        var id: String { rawValue }
        var flag: NSEvent.ModifierFlags {
            switch self {
            case .control: return .control
            case .option: return .option
            case .command: return .command
            case .shift: return .shift
            case .fn: return .function
            }
        }
        var title: String {
            switch self {
            case .control: return "Control ⌃"
            case .option: return "Option ⌥"
            case .command: return "Command ⌘"
            case .shift: return "Shift ⇧"
            case .fn: return "Fn"
            }
        }
    }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?
    private var monitors: [Any] = []
    private var detector = ModifierTapDetector()
    private var settleWork: DispatchWorkItem?
    private var axWait: Timer?

    var modifier: Modifier { Modifier(rawValue: defaults.string("modifier", default: "control")) ?? .control }
    /// 0 약(0.25초) · 1 중(0.35초) · 2 강(0.45초)
    var sensitivity: Int { defaults.int("sensitivity", default: 1) }
    var typingGuard: Bool { defaults.bool("typingGuard", default: true) }
    var actions: [String: LaunchAction] {
        guard let d = defaults.data("actions"), let m = try? JSONDecoder().decode([String: LaunchAction].self, from: d) else { return [:] }
        return m
    }
    func setAction(_ a: LaunchAction?, taps: Int) {
        var m = actions
        m[String(taps)] = a
        defaults.set(try? JSONEncoder().encode(m), "actions")
    }

    var monitoring: Bool { !monitors.isEmpty }

    func start(context: ModuleContext) {
        self.context = context
        install()
    }

    func stop() {
        uninstall()
        context = nil
    }

    func settingsChanged() {
        guard context != nil else { return }
        install()
    }

    private func install() {
        uninstall()
        detector.window = [0.25, 0.35, 0.45][max(0, min(2, sensitivity))]
        detector.typingGuard = typingGuard ? 0.5 : 0
        // 권한이 없으면 감시하지 않는다 (요청은 설정 화면 버튼으로만)
        guard !actions.isEmpty else { return }
        guard LaunchSystem.axTrusted else {
            // 권한이 허용되면 시작한다 (10초마다 확인만, 요청 창은 띄우지 않음)
            if axWait == nil {
                axWait = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] t in
                    guard LaunchSystem.axTrusted else { return }
                    t.invalidate()
                    self?.axWait = nil
                    self?.install()
                }
            }
            return
        }
        let handler: (NSEvent) -> Void = { [weak self] e in self?.handle(e) }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { e in handler(e); return e }) { monitors.append(l) }
    }

    private func uninstall() {
        axWait?.invalidate()
        axWait = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        settleWork?.cancel()
        settleWork = nil
        detector.reset()
    }

    private func handle(_ e: NSEvent) {
        let t = e.timestamp
        if e.type == .keyDown {
            detector.keyDown(at: t)
            settleWork?.cancel()
            return
        }
        let target = modifier.flag
        let all = e.modifierFlags.intersection([.control, .option, .command, .shift, .function])
        let pressed = all.contains(target)
        let others = !all.subtracting(target).isEmpty
        detector.flags(pressed: pressed, others: others, at: t)
        if !pressed, detector.count > 0 {
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let n = self.detector.settle(at: ProcessInfo.processInfo.systemUptime)
                if n > 0, let a = self.actions[String(n)] { a.perform(context: self.context) }
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + detector.window, execute: work)
        }
    }

    func settingsView() -> AnyView? { AnyView(InputTriggersSettings(module: self)) }

    func paletteActions() -> [PaletteAction] { [] }

    func selfTest() -> [String] {
        var out = ["accessibility trusted: \(LaunchSystem.axTrusted) (monitors installed only while enabled, trusted and mapped)"]
        func run(_ name: String, _ steps: [(String, Double)], settleAt: Double, expect: Int) {
            var d = ModifierTapDetector()
            for (s, t) in steps {
                switch s {
                case "down": d.flags(pressed: true, others: false, at: t)
                case "up": d.flags(pressed: false, others: false, at: t)
                case "combo": d.flags(pressed: true, others: true, at: t)
                case "key": d.keyDown(at: t)
                default: break
                }
            }
            let n = d.settle(at: settleAt)
            out.append("\(n == expect ? "ok  " : "FAIL") \(name): \(n) (expected \(expect))")
        }
        run("single tap", [("down", 10.0), ("up", 10.08)], settleAt: 10.5, expect: 1)
        run("double tap", [("down", 10.0), ("up", 10.08), ("down", 10.2), ("up", 10.27)], settleAt: 10.7, expect: 2)
        run("triple tap", [("down", 10.0), ("up", 10.05), ("down", 10.15), ("up", 10.2), ("down", 10.3), ("up", 10.35)], settleAt: 10.8, expect: 3)
        run("long press", [("down", 10.0), ("up", 10.6)], settleAt: 11.0, expect: 0)
        run("with another modifier", [("down", 10.0), ("combo", 10.05), ("up", 10.1)], settleAt: 10.6, expect: 0)
        run("typing just before", [("key", 9.8), ("down", 10.0), ("up", 10.05)], settleAt: 10.5, expect: 0)
        run("key during taps", [("down", 10.0), ("up", 10.05), ("key", 10.1)], settleAt: 10.6, expect: 0)
        run("slow second tap", [("down", 10.0), ("up", 10.05), ("down", 10.8), ("up", 10.85)], settleAt: 11.3, expect: 1)
        out.append("mapped taps: \(actions.keys.sorted().joined(separator: ",")) · modifier \(modifier.rawValue) · sensitivity \(sensitivity)")
        out.append("trackpad tap (M-H-020): unsupported — public APIs give no pressure for light taps without a click")
        out.append("knock (M-H-021): unsupported — accelerometer is a private IOKit HID device")
        return out
    }
}

private struct InputTriggersSettings: View {
    let module: InputTriggersModule
    @State private var modifier: InputTriggersModule.Modifier = .control
    @State private var sensitivity = 1
    @State private var typingGuard = true
    @State private var actions: [String: LaunchAction] = [:]
    @State private var trusted = LaunchSystem.axTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !trusted {
                HStack {
                    Text(T("손쉬운 사용 권한이 있어야 전역 수정키를 감시할 수 있습니다.", "Watching modifier keys system-wide needs Accessibility access."))
                    Button(T("권한 요청", "Request access")) { LaunchSystem.requestAX() }
                }
            }
            Picker(T("수정키", "Modifier"), selection: $modifier) {
                ForEach(InputTriggersModule.Modifier.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: modifier) { _, v in ModuleDefaults(module: module.id).set(v.rawValue, "modifier") }
            Picker(T("감도 (탭 사이 간격)", "Sensitivity (time between taps)"), selection: $sensitivity) {
                Text(T("약 0.25초", "Low 0.25s")).tag(0)
                Text(T("중 0.35초", "Medium 0.35s")).tag(1)
                Text(T("강 0.45초", "High 0.45s")).tag(2)
            }
            .onChange(of: sensitivity) { _, v in ModuleDefaults(module: module.id).set(v, "sensitivity") }
            Toggle(T("타이핑 직후 0.5초는 무시 (오작동 방지)", "Ignore taps within 0.5s of typing"), isOn: $typingGuard)
                .onChange(of: typingGuard) { _, v in ModuleDefaults(module: module.id).set(v, "typingGuard") }
            ForEach(1...3, id: \.self) { n in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(T("\(n)번 누르기", "\(n)× tap")).bold()
                        if let a = actions[String(n)] {
                            Image(systemName: a.symbol)
                            Text("\(LaunchAction.kindName(a.kind)): \(a.label)")
                            Button(T("지우기", "Clear")) { module.setAction(nil, taps: n); actions = module.actions }
                        } else {
                            Text(T("없음", "None")).foregroundStyle(.secondary)
                        }
                    }
                    LaunchActionForm(buttonTitle: T("지정", "Set")) { a in module.setAction(a, taps: n); actions = module.actions }
                }
            }
            Text(T("트랙패드 탭: 지원 안 됨 — 공개 API로는 클릭 없는 가벼운 탭의 압력을 읽을 수 없음 (비공개 MultitouchSupport 필요). 대안: 수정키 탭.",
                   "Trackpad tap: unsupported — public APIs expose no pressure for light taps without a click (needs private MultitouchSupport). Alternative: modifier taps."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("본체 노크: 지원 안 됨 — 가속도계는 비공개 IOKit HID 장치라 격리된 도우미 없이는 읽지 않음. 대안: 수정키 탭.",
                   "Knock: unsupported — the accelerometer is a private IOKit HID device, not read without an isolated helper. Alternative: modifier taps."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("앱별 프로필은 아직 지원하지 않습니다.", "Per-app profiles are not supported yet."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            modifier = module.modifier
            sensitivity = module.sensitivity
            typingGuard = module.typingGuard
            actions = module.actions
            trusted = LaunchSystem.axTrusted
        }
    }
}
