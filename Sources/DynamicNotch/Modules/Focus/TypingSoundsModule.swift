import AVFoundation
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 타이핑 소리 합성: 키마다 짧은 클릭음을 만든다 (파일 없이). 음높이를 조금씩 달리한 변형을 미리 만들어 둔다.
enum TypingSoundSynth {
    enum Style: String, CaseIterable, Identifiable {
        case mechanical, soft, typewriter, blip, beep, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mechanical: return T("기계식", "Mechanical")
            case .soft: return T("부드럽게", "Soft")
            case .typewriter: return T("타자기", "Typewriter")
            case .blip: return T("블립", "Blip")
            case .beep: return T("삑", "Beep")
            case .custom: return T("내 소리", "My Sound")
            }
        }
    }

    static let sampleRate: Double = 44100

    /// [보통 키 변형 4개, 큰 키(스페이스·리턴·지우기) 변형 2개]
    static func samples(_ style: Style) -> [[Float]] {
        var seed: UInt32 = 0x1234_5678
        func rnd() -> Float {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Float(seed) / Float(UInt32.max) * 2 - 1
        }
        let pitches: [Float] = [1.0, 0.96, 1.05, 0.92, 0.78, 0.74]
        return pitches.map { p in
            let dur: Double
            switch style {
            case .typewriter: dur = 0.09
            case .beep: dur = 0.07
            default: dur = 0.055
            }
            let n = Int(sampleRate * dur)
            var out = [Float](repeating: 0, count: n)
            var lp: Float = 0
            var hpPrev: Float = 0, hp: Float = 0
            for i in 0..<n {
                let t = Float(Double(i) / sampleRate)
                let w = rnd()
                lp += 0.35 * (w - lp)
                hp = 0.9 * (hp + w - hpPrev); hpPrev = w
                var x: Float = 0
                switch style {
                case .mechanical, .custom:
                    x += hp * expf(-t / 0.0022) * 0.9
                    x += sinf(2 * .pi * 2300 * p * t) * expf(-t / 0.006) * 0.35
                    x += sinf(2 * .pi * 170 * p * t) * expf(-t / 0.012) * 0.45
                    let t2 = t - 0.02
                    if t2 > 0 { x += hp * expf(-t2 / 0.0015) * 0.35 }
                case .soft:
                    x += lp * expf(-t / 0.004) * 0.7
                    x += sinf(2 * .pi * 130 * p * t) * expf(-t / 0.011) * 0.5
                case .typewriter:
                    x += w * expf(-t / 0.0014) * 1.0
                    x += sinf(2 * .pi * 1850 * p * t) * expf(-t / 0.02) * 0.3
                    x += sinf(2 * .pi * 3650 * p * t) * expf(-t / 0.014) * 0.2
                    x += sinf(2 * .pi * 95 * p * t) * expf(-t / 0.022) * 0.45
                case .blip:
                    let env = min(1, t / 0.002) * expf(-t / 0.012)
                    x = sinf(2 * .pi * 1050 * p * t) * env * 0.8
                case .beep:
                    let env = min(1, t / 0.002) * expf(-t / 0.022)
                    x = (sinf(2 * .pi * 680 * p * t) >= 0 ? 1 : -1) * env * 0.3
                }
                out[i] = x
            }
            let peak = out.map(abs).max() ?? 1
            return peak > 0 ? out.map { $0 / peak * 0.8 } : out
        }
    }

    static func buffers(_ style: Style, customPath: String) -> [AVAudioPCMBuffer] {
        if style == .custom, !customPath.isEmpty, let file = try? AVAudioFile(forReading: URL(fileURLWithPath: customPath)) {
            let frames = AVAudioFrameCount(min(file.length, Int64(file.processingFormat.sampleRate * 1.5)))
            if let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames), (try? file.read(into: buf, frameCount: frames)) != nil {
                return [buf]
            }
        }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return [] }
        return samples(style == .custom ? .mechanical : style).compactMap { s in
            guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(s.count)) else { return nil }
            b.frameLength = AVAudioFrameCount(s.count)
            s.withUnsafeBufferPointer { src in b.floatChannelData![0].update(from: src.baseAddress!, count: s.count) }
            return b
        }
    }
}

/// 클릭음 재생기 (플레이어 노드 여러 개를 돌아가며 써서 빠른 입력도 겹쳐 난다)
final class TypingSoundPlayer {
    private var engine: AVAudioEngine?
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var next = 0
    private var configObserver: NSObjectProtocol?

    var isReady: Bool { engine != nil }

    func prepare(style: TypingSoundSynth.Style, customPath: String, volume: Float) -> Bool {
        teardown()
        buffers = TypingSoundSynth.buffers(style, customPath: customPath)
        guard let fmt = buffers.first?.format else { return false }
        let e = AVAudioEngine()
        for _ in 0..<6 {
            let n = AVAudioPlayerNode()
            e.attach(n)
            e.connect(n, to: e.mainMixerNode, format: fmt)
            nodes.append(n)
        }
        e.mainMixerNode.outputVolume = volume
        e.prepare()
        do { try e.start() } catch { nodes = []; return false }
        engine = e
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in
            // 출력 장치가 바뀌면 다시 시작
            guard let self, let e = self.engine else { return }
            try? e.start()
        }
        return true
    }

    func setVolume(_ v: Float) { engine?.mainMixerNode.outputVolume = v }

    func play(big: Bool) {
        guard engine != nil, !buffers.isEmpty, !nodes.isEmpty else { return }
        let pool = buffers.count >= 6 ? (big ? Array(buffers[4...5]) : Array(buffers[0...3])) : buffers
        let b = pool[Int.random(in: 0..<pool.count)]
        let n = nodes[next % nodes.count]
        next += 1
        n.scheduleBuffer(b, at: nil, options: .interrupts)
        if !n.isPlaying { n.play() }
    }

    func teardown() {
        for n in nodes { n.stop() }
        engine?.stop()
        engine = nil
        nodes = []
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
    }

    /// 미리 듣기: 짧은 문장을 치는 것처럼 몇 번 울린다
    func preview() {
        let pattern: [(Double, Bool)] = [(0, false), (0.11, false), (0.2, false), (0.33, true), (0.45, false), (0.53, false), (0.66, false), (0.8, true)]
        for (t, big) in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in self?.play(big: big) }
        }
    }
}

/// 타이핑 소리: 키마다 합성 클릭음. 키 입력을 들으려면 입력 모니터링 권한이 필요하고, 없으면 지원 안 됨 상태를 보여 준다.
/// 비밀번호 칸(보안 입력)에서는 macOS가 키를 넘기지 않아 소리가 나지 않는다. 키 내용은 읽지도 저장하지도 않는다.
final class TypingSoundsModule: NotchModule, ObservableObject {
    let id = "typingsounds"
    var title: String { T("타이핑 소리", "Typing Sounds") }
    let symbol = "keyboard"
    var enabledByDefault: Bool { false }

    static let hotkeys: [(id: String, label: String, shortcut: HotKeyCenter.Shortcut?)] = [
        ("none", T("없음", "None"), nil),
        ("ctrlOptT", "⌃⌥T", .init(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))),
        ("ctrlOptCmdT", "⌃⌥⌘T", .init(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey | cmdKey))),
    ]

    @Published private(set) var subscribed = false
    @Published var paused = false
    private let player = TypingSoundPlayer()
    private var retryTimer: Timer?
    private var activateObserver: NSObjectProtocol?
    private var frontBundle: String?
    private var started = false
    /// 지금 재생기에 올린 소리 (음량만 바뀌면 다시 만들지 않음)
    private var prepared: (style: TypingSoundSynth.Style, path: String)?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    var style: TypingSoundSynth.Style { TypingSoundSynth.Style(rawValue: defaults.string("style", default: "mechanical")) ?? .mechanical }
    var volume: Float { Float(defaults.double("volume", default: 0.5)) }
    var scope: String { defaults.string("scope", default: "all") }
    var apps: [String] { defaults.strings("apps", default: []) }

    func start(context: ModuleContext) {
        guard !started, !AppSettings.isHelper else { return }
        started = true
        frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.frontBundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        }
        trySubscribe()
        if !subscribed {
            // 권한을 나중에 주면 30초 안에 알아서 시작
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.trySubscribe() }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            retryTimer = t
        }
        registerHotkey()
    }

    func stop() {
        started = false
        retryTimer?.invalidate()
        retryTimer = nil
        TFKeyTap.shared.remove("typingsounds")
        subscribed = false
        player.teardown()
        prepared = nil
        if let o = activateObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activateObserver = nil
        HotKeyCenter.shared.unregister("typingsounds.pause")
    }

    func settingsChanged() {
        guard started else { return }
        if subscribed {
            let path = defaults.string("customPath", default: "")
            if prepared?.style != style || prepared?.path != path {
                if player.prepare(style: style, customPath: path, volume: volume) { prepared = (style, path) }
            } else {
                player.setVolume(volume)
            }
        }
        registerHotkey()
    }

    private func registerHotkey() {
        let choice = defaults.string("hotkey", default: "none")
        guard started, let sc = Self.hotkeys.first(where: { $0.id == choice })?.shortcut else {
            HotKeyCenter.shared.unregister("typingsounds.pause"); return
        }
        HotKeyCenter.shared.register("typingsounds.pause", sc) { [weak self] in self?.paused.toggle() }
    }

    private func trySubscribe() {
        guard started, !subscribed, TFKeyTap.hasPermission else { return }
        let path = defaults.string("customPath", default: "")
        guard player.prepare(style: style, customPath: path, volume: volume) else { return }
        prepared = (style, path)
        subscribed = TFKeyTap.shared.add("typingsounds") { [weak self] code in self?.key(code) }
        if subscribed { retryTimer?.invalidate(); retryTimer = nil } else { player.teardown() }
    }

    private func key(_ code: Int64) {
        guard !paused, !IsSecureEventInputEnabled() else { return }
        let front = frontBundle ?? ""
        switch scope {
        case "only": guard apps.contains(front) else { return }
        case "except": guard !apps.contains(front) else { return }
        default: break
        }
        let big = [kVK_Space, kVK_Return, kVK_Delete, kVK_Tab, kVK_ANSI_KeypadEnter].contains(Int(code))
        player.play(big: big)
    }

    func tabView() -> AnyView? { AnyView(TypingSoundsTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 480, height: 150) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "typingsounds.pause", title: paused ? T("타이핑 소리 다시 켜기", "Resume Typing Sounds") : T("타이핑 소리 잠시 멈춤", "Pause Typing Sounds"),
                       symbol: paused ? "speaker.wave.2" : "speaker.slash", keywords: ["typing", "타이핑", "keyboard", "키보드"]) { [weak self] in self?.paused.toggle() }]
    }

    func settingsView() -> AnyView? { AnyView(TypingSoundsSettings()) }

    func selfTest() -> [String] {
        var lines = TypingSoundSynth.Style.allCases.filter { $0 != .custom }.map { s -> String in
            let v = TypingSoundSynth.samples(s)
            return "\(s.rawValue): \(v.count) variants, \(v.first?.count ?? 0) samples, peak \(String(format: "%.2f", v.first?.map(abs).max() ?? 0))"
        }
        lines.append("input monitoring: \(TFKeyTap.hasPermission ? "granted" : "not granted -> unsupported state shown")")
        lines.append("secure input active now: \(IsSecureEventInputEnabled())")
        return lines
    }
}

private struct TypingSoundsTab: View {
    @ObservedObject var module: TypingSoundsModule
    @StateObject private var prefs = TFPrefs(module: "typingsounds")
    @State private var previewer = TypingSoundPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !TFKeyTap.hasPermission {
                TFUnsupportedBox(title: T("입력 모니터링 권한이 필요해요", "Input Monitoring is required"),
                                 reason: T("키를 누를 때 소리를 내려면 키 입력을 들어야 해요. 키 내용은 읽거나 저장하지 않아요.",
                                           "Playing a sound per key needs to hear key presses. Key contents are never read or stored."),
                                 alternative: T("권한 없이도 아래 미리 듣기는 돼요.", "Preview below works without it."),
                                 buttonTitle: T("허용", "Allow")) {
                    TFKeyTap.requestPermission()
                    TFKeyTap.openPrivacySettings()
                }
            } else {
                HStack {
                    Image(systemName: module.paused ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(module.paused ? .yellow : .green)
                    Text(module.paused ? T("잠시 멈춤", "Paused") : (module.subscribed ? T("키를 누르면 소리가 나요", "Sounds play as you type") : T("준비 중", "Starting")))
                        .font(.island(.subhead, .semibold))
                    Spacer()
                    TFPillButton(title: module.paused ? T("다시 켜기", "Resume") : T("멈춤", "Pause")) { module.paused.toggle() }
                }
            }
            HStack(spacing: 5) {
                ForEach(TypingSoundSynth.Style.allCases.filter { $0 != .custom }) { s in
                    TFPillButton(title: s.label, prominent: prefs.string("style", "mechanical").wrappedValue == s.rawValue) {
                        prefs.string("style", "mechanical").wrappedValue = s.rawValue
                        if previewer.prepare(style: s, customPath: "", volume: Float(prefs.double("volume", 0.5).wrappedValue)) { previewer.preview() }
                    }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.island(.caption)).foregroundStyle(.white.opacity(0.6))
                Slider(value: prefs.double("volume", 0.5), in: 0...1).controlSize(.small).accessibilityLabel(T("음량", "Volume"))
                TFPillButton(title: T("미리 듣기", "Preview"), symbol: "play.fill") {
                    let s = TypingSoundSynth.Style(rawValue: prefs.string("style", "mechanical").wrappedValue) ?? .mechanical
                    if previewer.prepare(style: s, customPath: prefs.string("customPath", "").wrappedValue, volume: Float(prefs.double("volume", 0.5).wrappedValue)) { previewer.preview() }
                }
            }
        }
        .foregroundStyle(.white)
        .onDisappear { previewer.teardown() }
    }
}

private struct TypingSoundsSettings: View {
    @StateObject private var prefs = TFPrefs(module: "typingsounds")
    @State private var previewer = TypingSoundPlayer()
    @State private var hasPermission = TFKeyTap.hasPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(hasPermission ? .green : .yellow)
                Text(hasPermission ? T("입력 모니터링 허용됨", "Input Monitoring allowed") : T("입력 모니터링 없음: 소리를 낼 수 없어요", "No Input Monitoring: sounds can't play"))
                Spacer()
                if !hasPermission {
                    Button(T("권한 요청", "Request")) { TFKeyTap.requestPermission(); hasPermission = TFKeyTap.hasPermission }
                    Button(T("설정 열기", "Open Settings")) { TFKeyTap.openPrivacySettings() }
                }
            }
            Picker(T("소리", "Sound"), selection: prefs.string("style", "mechanical")) {
                ForEach(TypingSoundSynth.Style.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if prefs.string("style", "mechanical").wrappedValue == "custom" {
                HStack {
                    Text(prefs.string("customPath", "").wrappedValue.isEmpty ? T("파일을 고르기 전엔 기계식 소리가 나요", "Mechanical plays until you pick a file")
                                                                            : (prefs.string("customPath", "").wrappedValue as NSString).lastPathComponent)
                        .font(.caption)
                    Spacer()
                    Button(T("파일 고르기…", "Choose File…")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.audio]
                        if panel.runModal() == .OK, let url = panel.url { prefs.string("customPath", "").wrappedValue = url.path }
                    }
                }
            }
            HStack {
                Text(T("음량", "Volume"))
                Slider(value: prefs.double("volume", 0.5), in: 0...1)
                Button(T("미리 듣기", "Preview")) {
                    let s = TypingSoundSynth.Style(rawValue: prefs.string("style", "mechanical").wrappedValue) ?? .mechanical
                    if previewer.prepare(style: s, customPath: prefs.string("customPath", "").wrappedValue, volume: Float(prefs.double("volume", 0.5).wrappedValue)) { previewer.preview() }
                }
            }
            Picker(T("소리 낼 곳", "Play In"), selection: prefs.string("scope", "all")) {
                Text(T("모든 앱", "All apps")).tag("all")
                Text(T("고른 앱에서만", "Only selected apps")).tag("only")
                Text(T("고른 앱 빼고", "All except selected")).tag("except")
            }
            if prefs.string("scope", "all").wrappedValue != "all" {
                TFAppListEditor(prefs: prefs, key: "apps",
                                emptyText: prefs.string("scope", "all").wrappedValue == "only" ? T("아직 고른 앱이 없어 어디서도 소리가 나지 않아요.", "No apps yet, so no sounds play anywhere.")
                                                                                              : T("아직 뺀 앱이 없어요.", "No apps excluded yet."))
            }
            Picker(T("잠시 멈춤 단축키", "Pause Shortcut"), selection: prefs.string("hotkey", "none")) {
                ForEach(TypingSoundsModule.hotkeys, id: \.id) { Text($0.label).tag($0.id) }
            }
            TFSettingsNote(text: T("비밀번호 칸처럼 보안 입력이 켜진 곳에서는 macOS가 키를 넘기지 않아 소리가 나지 않아요. 키 내용은 읽거나 저장하지 않아요.",
                                   "In password fields (secure input) macOS doesn't pass keys, so no sound plays. Key contents are never read or stored."))
        }
        .onDisappear { previewer.teardown() }
    }
}
