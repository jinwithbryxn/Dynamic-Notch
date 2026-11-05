import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import SwiftUI

/// 오디오 장치: 출력 음량·음소거(기존 음량 줄), 입력 기기 고르기, 입력 레벨, 시스템 마이크 음소거.
/// 입력 레벨은 탭이 보이고 사용자가 '레벨 보기'를 켰을 때만 AVAudioEngine 입력 탭으로 잰다.
/// 마이크 음소거는 기기 음소거 속성을 쓰고, 없으면 입력 음량을 0으로 내렸다가 끌 때·다음 실행 때 되돌린다.
final class AudioDevicesModule: NotchModule {
    let id = "audiodevices"
    var title: String { T("오디오 장치", "Audio Devices") }
    let symbol = "hifispeaker.2.fill"
    /// 입력 레벨이 마이크를 쓰므로 기본 꺼짐
    let enabledByDefault = false

    let state: MBAudioDevicesState
    init() { state = MBAudioDevicesState(module: "audiodevices") }

    func start(context: ModuleContext) { state.start(context: context) }
    func stop() { state.stop() }
    func settingsChanged() { state.applyHotKey() }

    func tabView() -> AnyView? { AnyView(AudioDevicesTab(state: state)) }
    var tabContentSize: CGSize { CGSize(width: 470, height: 280) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "audiodevices.micmute",
                       title: state.micMuted ? T("마이크 음소거 풀기", "Unmute Microphone") : T("마이크 음소거", "Mute Microphone"),
                       subtitle: MBAudio.name(MBAudio.defaultInput()),
                       symbol: state.micMuted ? "mic.fill" : "mic.slash.fill",
                       keywords: ["mic", "microphone", "mute", "마이크", "음소거"], run: { [weak self] in self?.state.toggleMicMute() })]
    }

    func settingsView() -> AnyView? { AnyView(AudioDevicesSettings(module: id)) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let out = MBAudio.defaultOutput()
        lines.append("default output: \(MBAudio.name(out)) volume=\(AudioOutput.volume(out).map { String(format: "%.2f", $0) } ?? "n/a") muted=\(AudioOutput.isMuted(out))")
        let def = MBAudio.defaultInput()
        for d in MBAudio.inputDevices() {
            let vol = MBAudio.inputVolume(d).map { String(format: "%.2f", $0) } ?? "n/a"
            lines.append("input \(d == def ? "*" : " ") \(MBAudio.name(d)) [\(MBAudio.inputSymbol(d))] volume=\(vol) settable=\(MBAudio.inputVolumeSettable(d)) muteSettable=\(MBAudio.inputMuteSettable(d)) muted=\(MBAudio.inputMuted(d).map { "\($0)" } ?? "n/a")")
        }
        lines.append("mic usage description in Info.plist: \(MBAudio.hasMicrophoneUsageDescription)")
        lines.append("mic permission (read only): \(Self.statusText(AVCaptureDevice.authorizationStatus(for: .audio)))")
        lines.append("pending mic restore record: \(state.pendingRestoreText ?? "none")")
        return lines
    }

    private static func statusText(_ s: AVAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }
}

/// 입력 기기 한 줄
struct MBInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
}

final class MBAudioDevicesState: ObservableObject {
    enum MeterState: Equatable { case off, running, needsPermission, denied, missingUsageDescription, failed(String) }

    @Published private(set) var inputs: [MBInputDevice] = []
    @Published private(set) var defaultInput: AudioDeviceID = 0
    @Published private(set) var inputVolume: Float?
    @Published private(set) var inputVolumeSettable = false
    @Published private(set) var micMuted = false
    @Published private(set) var micMuteSupported = true
    @Published private(set) var level: Float = 0
    @Published private(set) var meterState: MeterState = .off

    private let defaults: ModuleDefaults
    private var context: ModuleContext?
    private let systemWatch = MBPropertyWatch()
    private let inputWatch = MBPropertyWatch()
    private var watchedInput: AudioDeviceID = 0
    private var visibleCount = 0
    private var engine: AVAudioEngine?
    private var engineObserver: NSObjectProtocol?
    private var running = false

    /// 이 모듈이 바꾼 마이크 상태 (끌 때·비정상 종료 뒤 다음 실행 때 되돌린다)
    private struct Restore: Codable {
        var uid: String
        var method: String          // "mute" | "volume"
        var previousVolume: Float?
    }

    init(module: String) { defaults = ModuleDefaults(module: module) }

    var meterWanted: Bool { defaults.bool("meter", default: false) }

    private var restore: Restore? {
        get { defaults.data("micRestore").flatMap { try? JSONDecoder().decode(Restore.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, "micRestore") }
    }

    var pendingRestoreText: String? { restore.map { "\($0.method) on \($0.uid)" } }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        guard !running else { return }
        running = true
        self.context = context
        // 지난번에 음소거한 채 비정상 종료됐으면 먼저 되돌린다
        if restore != nil, !MBAudio.isDevTool {
            applyRestore()
            context.notice(T("마이크 음소거를 되돌렸어요", "Microphone mute restored"),
                           T("지난번 종료 때 남은 음소거를 풀었습니다", "Cleared a mute left over from the last session"),
                           symbol: "mic.fill", tab: "audiodevices")
        }
        systemWatch.add(MBAudio.system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.defaultInputChanged() }
        systemWatch.add(MBAudio.system, kAudioHardwarePropertyDevices) { [weak self] in self?.refresh() }
        refresh()
        applyHotKey()
    }

    func stop() {
        guard running else { return }
        running = false
        stopMeter()
        systemWatch.removeAll()
        inputWatch.removeAll()
        watchedInput = 0
        HotKeyCenter.shared.unregister("audiodevices.micmute")
        // 이 모듈이 건 마이크 음소거를 푼다
        if restore != nil { applyRestore() }
        context = nil
    }

    func applyHotKey() {
        if running, defaults.bool("hotkey", default: false) {
            let shortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey | cmdKey))
            HotKeyCenter.shared.register("audiodevices.micmute", shortcut) { [weak self] in self?.toggleMicMute() }
        } else {
            HotKeyCenter.shared.unregister("audiodevices.micmute")
        }
    }

    // MARK: 상태 읽기

    func refresh() {
        let def = MBAudio.defaultInput()
        let list = MBAudio.inputDevices().map { MBInputDevice(id: $0, name: MBAudio.name($0), symbol: MBAudio.inputSymbol($0)) }
        if list != inputs { inputs = list }
        if def != defaultInput { defaultInput = def }
        watchInput(def)
        readInput()
    }

    private func watchInput(_ device: AudioDeviceID) {
        guard device != watchedInput else { return }
        inputWatch.removeAll()
        watchedInput = device
        guard device != 0 else { return }
        for selector in [kAudioDevicePropertyMute, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            inputWatch.add(device, selector, scope: kAudioDevicePropertyScopeInput) { [weak self] in self?.readInput() }
        }
    }

    private func readInput() {
        let d = defaultInput
        let vol = MBAudio.inputVolume(d)
        let settable = MBAudio.inputVolumeSettable(d)
        let muteSettable = MBAudio.inputMuteSettable(d)
        var muted = MBAudio.inputMuted(d) ?? false
        // 음량 0 방식으로 음소거한 기기
        if let r = restore, r.method == "volume", AudioOutput.uid(d) == r.uid { muted = true }
        // 사용자가 시스템 설정에서 직접 음소거를 풀면 기록도 지운다
        if let r = restore, r.method == "mute", AudioOutput.uid(d) == r.uid, MBAudio.inputMuted(d) == false { restore = nil }
        if inputVolume != vol { inputVolume = vol }
        if inputVolumeSettable != settable { inputVolumeSettable = settable }
        if micMuted != muted { micMuted = muted }
        let supported = muteSettable || settable
        if micMuteSupported != supported { micMuteSupported = supported }
    }

    /// 기본 입력이 바뀌면: 음소거 중이었으면 이전 기기를 되돌리고 새 기기를 음소거한다
    private func defaultInputChanged() {
        let wasMuted = restore != nil
        if wasMuted { applyRestore() }
        refresh()
        if wasMuted { _ = muteCurrent() }
        if meterState == .running { restartMeter() }
    }

    // MARK: 동작

    func selectInput(_ device: AudioDeviceID) {
        MBAudio.setDefaultInput(device)
        refresh()
    }

    func setInputVolume(_ value: Float) {
        // 음량 0 방식으로 음소거 중이면 음소거를 먼저 푼다 (사용자가 직접 음량을 정함)
        if restore?.method == "volume" { restore = nil }
        MBAudio.setInputVolume(defaultInput, value)
        readInput()
    }

    func toggleMicMute() {
        if micMuted {
            if restore != nil { applyRestore() } else { MBAudio.setInputMuted(defaultInput, false) }
            context?.notice(T("마이크 켜짐", "Microphone on"), MBAudio.name(defaultInput), symbol: "mic.fill", tab: "audiodevices", duration: 1.5)
        } else {
            guard muteCurrent() else {
                context?.notice(T("이 입력 기기는 음소거할 수 없어요", "This input can't be muted"), MBAudio.name(defaultInput),
                                symbol: "mic.badge.xmark", tint: .yellow, tab: "audiodevices")
                return
            }
            context?.notice(T("마이크 음소거", "Microphone muted"), MBAudio.name(defaultInput), symbol: "mic.slash.fill", tint: .red,
                            tab: "audiodevices", duration: 1.5)
        }
        readInput()
    }

    /// 현재 기본 입력을 음소거한다. 음소거 속성이 없으면 입력 음량을 0으로.
    private func muteCurrent() -> Bool {
        let d = MBAudio.defaultInput()
        guard d != 0, let uid = AudioOutput.uid(d) else { return false }
        if MBAudio.inputMuteSettable(d) {
            // 이미 음소거돼 있으면 기록하지 않는다 (사용자가 건 음소거는 끌 때 풀지 않음)
            guard MBAudio.inputMuted(d) != true else { return true }
            restore = Restore(uid: uid, method: "mute", previousVolume: nil)
            return MBAudio.setInputMuted(d, true)
        }
        if MBAudio.inputVolumeSettable(d), let v = MBAudio.inputVolume(d) {
            restore = Restore(uid: uid, method: "volume", previousVolume: v)
            return MBAudio.setInputVolume(d, 0)
        }
        return false
    }

    private func applyRestore() {
        guard let r = restore else { return }
        if let d = MBAudio.device(uid: r.uid) {
            if r.method == "mute" { MBAudio.setInputMuted(d, false) }
            else if let v = r.previousVolume { MBAudio.setInputVolume(d, v) }
        }
        // 기기가 없으면(연결 해제) 되돌릴 대상도 없다. 기기 쪽 상태는 그대로 남는다.
        restore = nil
    }

    // MARK: 입력 레벨 (탭이 보일 때만)

    func tabVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        if visibleCount > 0 { refresh(); startMeter() } else { stopMeter() }
    }

    /// 사용자가 '레벨 보기'를 눌렀을 때. 처음이면 여기서만 마이크 권한을 묻는다.
    func setMeterWanted(_ on: Bool) {
        objectWillChange.send()
        defaults.set(on, "meter")
        if !on { stopMeter(); meterState = .off; return }
        guard MBAudio.hasMicrophoneUsageDescription else { meterState = .missingUsageDescription; return }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { [weak self] in self?.startMeter() }
            }
        } else {
            startMeter()
        }
    }

    private func startMeter() {
        guard engine == nil, visibleCount > 0, meterWanted, !MBAudio.isDevTool else {
            if !meterWanted { meterState = .off }
            return
        }
        // 설명 문구 없이 마이크에 접근하면 macOS가 앱을 끝내므로 먼저 확인한다
        guard MBAudio.hasMicrophoneUsageDescription else { meterState = .missingUsageDescription; return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined: meterState = .needsPermission; return
        default: meterState = .denied; return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { meterState = .failed(T("입력 형식을 읽지 못함", "No input format")); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var peak: Float = 0
            for ch in 0..<Int(buffer.format.channelCount) {
                var sum: Float = 0
                let p = data[ch]
                for i in 0..<frames { sum += p[i] * p[i] }
                peak = max(peak, frames > 0 ? (sum / Float(frames)).squareRoot() : 0)
            }
            // -60 dB ~ 0 dB를 0~1로
            let db = 20 * log10(max(peak, 1e-6))
            let norm = min(max((db + 60) / 60, 0), 1)
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = norm > self.level ? norm : self.level * 0.8 + norm * 0.2
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            meterState = .failed(error.localizedDescription)
            return
        }
        self.engine = engine
        meterState = .running
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                queue: .main) { [weak self] _ in self?.restartMeter() }
    }

    private func restartMeter() {
        stopMeter()
        startMeter()
    }

    private func stopMeter() {
        if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
        engineObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        level = 0
        if meterState == .running { meterState = .off }
    }
}

// MARK: - 화면

private struct AudioDevicesTab: View {
    @ObservedObject var state: MBAudioDevicesState
    @ObservedObject private var route = OutputRoute.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 출력: 기존 음량 줄 (누르면 음소거)
            HStack(spacing: 6) {
                Image(systemName: route.symbol).font(.island(.footnote)).frame(width: 16)
                Text(route.name).font(.island(.footnote, .semibold)).lineLimit(1)
                Spacer()
                Text(T("출력", "Output")).font(.island(.caption)).foregroundStyle(.white.opacity(0.5))
            }
            VolumeRow(thickness: 5)
            Divider().overlay(Color.white.opacity(0.08))
            // 입력
            HStack(spacing: 8) {
                Text(T("입력", "Input")).font(.island(.footnote, .semibold))
                Spacer()
                meterButton
                MBPillButton(title: state.micMuted ? T("마이크 꺼짐", "Mic Off") : T("마이크 켜짐", "Mic On"),
                             symbol: state.micMuted ? "mic.slash.fill" : "mic.fill",
                             active: state.micMuted, tint: .red) { state.toggleMicMute() }
                    .disabled(!state.micMuteSupported)
                    .help(state.micMuteSupported
                          ? T("기본 입력 기기를 음소거합니다 (모든 앱에 적용, 끌 때 되돌림)", "Mutes the default input for every app (restored when turned off)")
                          : T("이 기기는 음소거·입력 음량 속성이 없습니다", "This device has no mute or input volume control"))
            }
            levelRow
            meterNotice
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(state.inputs) { d in
                        Button { state.selectInput(d.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: d.symbol).font(.island(.footnote)).frame(width: 18)
                                Text(d.name).font(.island(.footnote)).lineLimit(1)
                                Spacer()
                                if d.id == state.defaultInput {
                                    Image(systemName: "checkmark").font(.island(.caption, .bold))
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(d.id == state.defaultInput ? 0.12 : 0.05)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(d.name)
                        .help(T("기본 입력으로 고르기", "Use as default input"))
                    }
                    if state.inputs.isEmpty {
                        Text(T("입력 기기가 없습니다", "No input devices")).font(.island(.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { state.tabVisible(true) }
        .onDisappear { state.tabVisible(false) }
    }

    private var meterButton: some View {
        MBPillButton(title: T("레벨", "Level"), symbol: "waveform", active: state.meterWanted && state.meterState == .running, tint: .green) {
            state.setMeterWanted(!state.meterWanted)
        }
        .help(T("입력 레벨 보기 (이 탭이 보이는 동안만 마이크를 엽니다)", "Show input level (opens the mic only while this tab is visible)"))
    }

    private var levelRow: some View {
        HStack(spacing: 8) {
            // 입력 레벨 막대
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(state.level))
                        .mask(Capsule())
                }
            }
            .frame(width: 90, height: 5)
            .opacity(state.meterState == .running ? 1 : 0.35)
            .accessibilityLabel(T("입력 레벨", "Input level"))
            // 입력 음량
            if let v = state.inputVolume, state.inputVolumeSettable {
                ScrubBar(fraction: Double(state.micMuted ? 0 : v), enabled: true, spacing: 6, thickness: 4,
                         onScrub: { state.setInputVolume(Float($0)) }, onEnd: {},
                         leading: { Image(systemName: "mic").font(.island(.caption2)).foregroundStyle(.white.opacity(0.6)) },
                         trailing: { Text("\(Int((state.micMuted ? 0 : v) * 100))%").font(.island(.caption)).monospacedDigit()
                             .foregroundStyle(.white.opacity(0.6)).frame(width: 32, alignment: .trailing) })
                    .help(T("입력 음량", "Input volume"))
            } else {
                Text(T("이 기기는 입력 음량을 조절할 수 없음", "Input volume not adjustable")).font(.island(.caption)).foregroundStyle(.white.opacity(0.45))
                Spacer()
            }
        }
    }

    @ViewBuilder private var meterNotice: some View {
        switch state.meterState {
        case .missingUsageDescription:
            MBUnsupportedBox(title: T("입력 레벨 지원 안 됨", "Input level unsupported"),
                             reason: T("앱 Info.plist에 마이크 사용 설명(NSMicrophoneUsageDescription)이 없어 마이크를 열 수 없습니다.",
                                       "The app's Info.plist has no NSMicrophoneUsageDescription, so the microphone can't be opened."),
                             alternative: T("대안: 시스템 설정 → 사운드 → 입력의 레벨 표시", "Alternative: System Settings → Sound → Input level"))
        case .denied:
            MBUnsupportedBox(title: T("마이크 권한 없음", "No microphone permission"),
                             reason: T("시스템 설정 → 개인정보 보호 → 마이크에서 이 앱을 허용하면 레벨이 보입니다.",
                                       "Allow this app under System Settings → Privacy → Microphone to see the level."))
                .onTapGesture { MBAudio.openPrivacySettings("Privacy_Microphone") }
        case .failed(let msg):
            MBUnsupportedBox(title: T("입력 레벨을 열지 못함", "Couldn't open input level"), reason: msg)
        default:
            EmptyView()
        }
    }
}

private struct AudioDevicesSettings: View {
    let module: String
    @State private var hotkey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("⌃⌥⌘M으로 마이크 음소거 전환", "Toggle microphone mute with ⌃⌥⌘M"), isOn: $hotkey)
                .onChange(of: hotkey) { _, newValue in ModuleDefaults(module: module).set(newValue, "hotkey") }
            Text(T("음소거는 기본 입력 기기에 걸리며 모든 앱에 적용됩니다. 음소거 속성이 없는 기기는 입력 음량을 0으로 내렸다가, 기능을 끄거나 앱을 다시 켤 때 원래 값으로 되돌립니다.",
                   "Mute applies to the default input for every app. Devices without a mute control get input volume 0, restored when the feature is turned off or the app restarts."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { hotkey = ModuleDefaults(module: module).bool("hotkey", default: false) }
    }
}
