import AVFoundation
import AppKit
import SwiftUI

/// 집중 배경음 합성기: 빗소리·브라운 노이즈·바람·파도를 파일 없이 실시간으로 만든다.
/// 오디오 스레드에서 돌므로 할당·잠금 없이 단순 값만 쓴다.
final class FocusNoiseGenerator {
    enum Kind: Int { case rain, brown, wind, waves }

    var kind: Kind = .rain
    var targetGain: Float = 0
    var sampleRate: Double = 48000
    private(set) var gain: Float = 0

    private var rng: UInt32 = 0x9E37_79B9
    private var brown: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var y1: Float = 0, y2: Float = 0, hpPrev: Float = 0, hpOut: Float = 0
    private var dropEnv: Float = 0, dropAmp: Float = 0
    private var windLevel: Float = 0.5, windTarget: Float = 0.6, windCounter = 0
    private var t: Double = 0

    @inline(__always) private func white() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng) / Float(UInt32.max) * 2 - 1
    }

    @inline(__always) private func pink(_ w: Float) -> Float {
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let p = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return p * 0.11
    }

    @inline(__always) private func lowpass(_ x: Float, _ a: Float) -> Float {
        y1 += a * (x - y1)
        y2 += a * (y1 - y2)
        return y2
    }

    /// mono 샘플 n개를 채운다
    func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        let sr = Float(sampleRate)
        let fadeIn = 1 / (sr * 3)      // 3초에 걸쳐 서서히 커짐
        let fadeOut = 1 / (sr * 0.4)
        let dropDecay = expf(-1 / (0.004 * sr))
        let dt = 1 / sampleRate
        for i in 0..<n {
            if gain < targetGain { gain = min(targetGain, gain + fadeIn) } else if gain > targetGain { gain = max(targetGain, gain - fadeOut) }
            let w = white()
            var x: Float
            switch kind {
            case .brown:
                brown = (brown + 0.02 * w) / 1.02
                x = brown * 3.2
            case .rain:
                // 잔잔한 빗소리 바탕 + 간간이 떨어지는 빗방울
                let bed = lowpass(pink(w), 0.55) * 0.9
                hpOut = 0.97 * (hpOut + w - hpPrev)
                hpPrev = w
                if Float(rng & 0xFFFF) / 65535 < 28 / sr * 4, dropEnv < 0.05 {
                    dropEnv = 1
                    dropAmp = 0.15 + 0.45 * abs(white())
                }
                dropEnv *= dropDecay
                x = bed + hpOut * 0.06 + white() * dropEnv * dropAmp
            case .wind:
                // 느리게 바뀌는 세기와 음색
                windCounter += 1
                if windCounter >= Int(sr * 1.7) {
                    windCounter = 0
                    windTarget = 0.25 + 0.75 * abs(white())
                }
                windLevel += (windTarget - windLevel) / (sr * 1.4)
                let fc = 140 + 700 * windLevel
                let a = 1 - expf(-2 * .pi * fc / sr)
                x = lowpass(w, a) * (0.6 + 1.6 * windLevel) * 2.4
            case .waves:
                // 9초 주기로 밀려왔다 빠지는 파도
                let phase = Float(t.truncatingRemainder(dividingBy: 9) / 9)
                let s = sinf(.pi * phase)
                let env = 0.12 + 0.88 * s * s * s
                let fc = 250 + 2600 * env
                let a = 1 - expf(-2 * .pi * fc / sr)
                x = lowpass(pink(w) * 0.7 + w * 0.3, a) * env * 2.2
            }
            out[i] = max(-1, min(1, x * gain))
            t += dt
        }
    }
}

/// 집중 배경음 재생기. 한 번에 하나만, 음량 조절, 서서히 시작, 잠자기·출력 장치 변경 시 멈춤.
final class FocusSoundPlayer: ObservableObject {
    static let shared = FocusSoundPlayer()
    static let module = "focussounds"

    enum Sound: String, CaseIterable, Identifiable {
        case rain, brown, wind, waves
        var id: String { rawValue }
        var label: String {
            switch self {
            case .rain: return T("빗소리", "Rain")
            case .brown: return T("브라운 노이즈", "Brown Noise")
            case .wind: return T("바람", "Wind")
            case .waves: return T("파도", "Waves")
            }
        }
        var symbol: String {
            switch self {
            case .rain: return "cloud.rain.fill"
            case .brown: return "waveform"
            case .wind: return "wind"
            case .waves: return "water.waves"
            }
        }
        var kind: FocusNoiseGenerator.Kind {
            switch self {
            case .rain: return .rain
            case .brown: return .brown
            case .wind: return .wind
            case .waves: return .waves
            }
        }
    }

    @Published private(set) var current: Sound?
    @Published var volume: Float = 0.5 {
        didSet { if current != nil { generator.targetGain = volume } }
    }
    private(set) var lastError: String?

    private let generator = FocusNoiseGenerator()
    private var engine: AVAudioEngine?
    private var sleepObserver: NSObjectProtocol?
    private var configObserver: NSObjectProtocol?
    private var stopWork: DispatchWorkItem?

    func play(_ sound: Sound) {
        stopWork?.cancel()
        generator.kind = sound.kind
        if engine == nil {
            guard build() else { current = nil; return }
        }
        generator.targetGain = volume
        current = sound
    }

    func toggle(_ sound: Sound) { current == sound ? stop() : play(sound) }

    /// 멈춤. fade면 0.4초 동안 줄인 뒤 오디오 엔진을 끈다.
    func stop(fade: Bool = true) {
        current = nil
        generator.targetGain = 0
        stopWork?.cancel()
        guard engine != nil else { return }
        if fade {
            let work = DispatchWorkItem { [weak self] in self?.teardown() }
            stopWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else {
            teardown()
        }
    }

    private func build() -> Bool {
        let e = AVAudioEngine()
        let outFormat = e.outputNode.outputFormat(forBus: 0)
        let sr = outFormat.sampleRate > 0 ? outFormat.sampleRate : 48000
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { return false }
        generator.sampleRate = sr
        let gen = generator
        let node = AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            gen.render(data, Int(frameCount))
            for b in buffers.dropFirst() { if let d = b.mData { memcpy(d, data, Int(frameCount) * MemoryLayout<Float>.size) } }
            return noErr
        }
        e.attach(node)
        e.connect(node, to: e.mainMixerNode, format: fmt)
        e.prepare()
        do {
            try e.start()
        } catch {
            lastError = error.localizedDescription
            return false
        }
        engine = e
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.stop(fade: false) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { [weak self] _ in self?.stop(fade: false) }
        return true
    }

    private func teardown() {
        engine?.stop()
        engine = nil
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        sleepObserver = nil
        configObserver = nil
    }

    /// 자체 검사: 장치로 내보내지 않고 합성기만 돌려 소리 크기(RMS)를 잰다.
    static func measure(_ sound: Sound, seconds: Double = 1) -> Float {
        let g = FocusNoiseGenerator()
        g.kind = sound.kind
        g.sampleRate = 48000
        g.targetGain = 1
        let n = Int(48000 * seconds)
        var buf = [Float](repeating: 0, count: n)
        // 서서히 커지는 3초를 건너뛴다
        for _ in 0..<4 { buf.withUnsafeMutableBufferPointer { g.render($0.baseAddress!, n) } }
        let sum = buf.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrtf(sum / Float(n))
    }
}

/// 집중 배경음 탭·설정. 오디오를 쓰므로 기본은 꺼짐.
final class FocusSoundsModule: NotchModule {
    let id = FocusSoundPlayer.module
    var title: String { T("집중 배경음", "Focus Sounds") }
    let symbol = "waveform"
    var enabledByDefault: Bool { false }

    private let player = FocusSoundPlayer.shared
    private var observer: NSObjectProtocol?
    private var lastPhase: String?
    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }

    func start(context: ModuleContext) {
        player.volume = Float(defaults.double("volume", default: 0.5))
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: TFEvents.pomodoroChanged, object: nil, queue: .main) { [weak self] note in
            self?.pomodoroChanged(note.userInfo ?? [:])
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        player.stop(fade: false)
    }

    func settingsChanged() {
        player.volume = Float(defaults.double("volume", default: 0.5))
    }

    /// 포모도로와 연결: 집중이 시작되면 자동 재생(선택), 집중이 끝나거나 멈추면 정지(선택). 일시정지 중에는 계속 재생.
    private func pomodoroChanged(_ info: [AnyHashable: Any]) {
        let phase = info["phase"] as? String
        let running = info["running"] as? Bool ?? false
        let waiting = info["waiting"] as? Bool ?? false
        // 집중으로 들어설 때만 (일시정지 뒤 계속은 해당 없음)
        if phase == "focus", running, !waiting, lastPhase != "focus", player.current == nil,
           defaults.bool("autoPlay", default: false),
           let s = FocusSoundPlayer.Sound(rawValue: defaults.string("autoSound", default: "rain")) {
            player.play(s)
        }
        let leftFocus = lastPhase == "focus" && (phase != "focus" || waiting)
        if leftFocus, defaults.bool("stopWhenFocusEnds", default: true) { player.stop() }
        lastPhase = waiting ? nil : phase
    }

    func tabView() -> AnyView? { AnyView(FocusSoundsTab(player: player)) }
    var tabContentSize: CGSize { CGSize(width: 460, height: 150) }

    func paletteActions() -> [PaletteAction] {
        var list = FocusSoundPlayer.Sound.allCases.map { s in
            PaletteAction(id: "focussounds.\(s.rawValue)", title: T("배경음: \(s.label)", "Focus sound: \(s.label)"),
                          symbol: s.symbol, keywords: ["sound", "noise", "배경음", "소리", "집중"]) { [weak self] in self?.player.play(s) }
        }
        if player.current != nil {
            list.insert(PaletteAction(id: "focussounds.stop", title: T("배경음 끄기", "Stop Focus Sound"), symbol: "speaker.slash",
                                      keywords: ["sound", "배경음"]) { [weak self] in self?.player.stop() }, at: 0)
        }
        return list
    }

    func settingsView() -> AnyView? { AnyView(FocusSoundsSettings()) }

    func selfTest() -> [String] {
        var lines = FocusSoundPlayer.Sound.allCases.map { s in
            String(format: "%@ rms %.3f", s.rawValue, FocusSoundPlayer.measure(s))
        }
        let probe = AVAudioEngine()
        let f = probe.outputNode.outputFormat(forBus: 0)
        lines.append("output format: \(Int(f.sampleRate)) Hz, \(f.channelCount) ch (not started)")
        return lines
    }
}

/// 포모도로 탭 오른쪽 위 작은 배경음 메뉴
struct FocusSoundQuickMenu: View {
    @ObservedObject var player: FocusSoundPlayer

    var body: some View {
        Menu {
            ForEach(FocusSoundPlayer.Sound.allCases) { s in
                Button { player.toggle(s) } label: { Label(s.label, systemImage: player.current == s ? "checkmark" : s.symbol) }
            }
            if player.current != nil {
                Divider()
                Button(T("끄기", "Stop")) { player.stop() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: player.current?.symbol ?? "speaker.wave.2")
                Text(player.current?.label ?? T("배경음", "Sounds"))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("집중 배경음", "Focus sounds"))
    }
}

private struct FocusSoundsTab: View {
    @ObservedObject var player: FocusSoundPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(FocusSoundPlayer.Sound.allCases) { s in
                    Button { player.toggle(s) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: s.symbol).font(.system(size: 20))
                            Text(s.label).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(player.current == s ? Color.black : Color.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(player.current == s ? Color.white.opacity(0.9) : Color.white.opacity(0.08)))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .help(player.current == s ? T("끄기", "Stop") : T("\(s.label) 재생", "Play \(s.label)"))
                    .accessibilityLabel(s.label)
                    .accessibilityAddTraits(player.current == s ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Slider(value: Binding(get: { Double(player.volume) }, set: {
                    player.volume = Float($0)
                    // 같은 프로세스라 알림 없이 바로 저장 (끄는 동안 매번 다른 기능을 깨우지 않게)
                    UserDefaults.standard.set($0, forKey: "module.\(FocusSoundPlayer.module).volume")
                }), in: 0...1)
                .controlSize(.small)
                .accessibilityLabel(T("음량", "Volume"))
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Text(player.current == nil ? T("파일 없이 실시간 합성 · 오프라인", "Generated live · offline")
                                           : T("재생 중 · 잠자기나 출력 변경 시 멈춤", "Playing · stops on sleep or output change"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(.white)
    }
}

private struct FocusSoundsSettings: View {
    @StateObject private var prefs = TFPrefs(module: FocusSoundPlayer.module)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("음량", "Volume"))
                Slider(value: prefs.double("volume", 0.5), in: 0...1)
            }
            Toggle(T("포모도로 집중이 끝나거나 멈추면 끄기", "Stop sounds when focus ends"), isOn: prefs.bool("stopWhenFocusEnds", true))
            TFSettingsNote(text: T("일시정지 중에는 계속 재생해요.", "Sounds keep playing while paused."))
            Toggle(T("포모도로 집중을 시작하면 자동 재생", "Play automatically when focus starts"), isOn: prefs.bool("autoPlay", false))
            Picker(T("자동 재생할 소리", "Sound to play"), selection: prefs.string("autoSound", "rain")) {
                ForEach(FocusSoundPlayer.Sound.allCases) { Text($0.label).tag($0.rawValue) }
            }
            TFSettingsNote(text: T("소리는 파일이 아니라 실시간으로 합성해 인터넷 없이 동작해요. 한 번에 하나만 재생하고, Mac이 잠들거나 출력 장치가 바뀌면 멈춰요.",
                                   "Sounds are generated live, not looped files, and work offline. One at a time; they stop when the Mac sleeps or the output device changes."))
        }
    }
}
