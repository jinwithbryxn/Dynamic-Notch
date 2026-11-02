import Accelerate
import AppKit
import CoreAudio
import SwiftUI

/// 실제 오디오 스펙트럼: 이 앱을 뺀 시스템 출력 전체를 Core Audio 탭으로 받아(소리는 그대로) FFT 막대로 그린다.
/// 사용자가 켜 두고 탭이 보이는 동안에만 탭을 만들고, 숨거나 끄면 바로 지운다. 소리를 저장·전송하지 않는다.
final class AudioSpectrumModule: NotchModule {
    let id = "spectrum"
    var title: String { T("오디오 스펙트럼", "Audio Spectrum") }
    let symbol = "waveform"
    let enabledByDefault = false

    let analyzer = MBSpectrumAnalyzer(module: "spectrum")

    func start(context: ModuleContext) { analyzer.running = true }
    func stop() {
        analyzer.running = false
        analyzer.stopCapture()
    }

    func tabView() -> AnyView? { AnyView(SpectrumTab(analyzer: analyzer)) }
    var tabContentSize: CGSize { CGSize(width: 440, height: 200) }

    func selfTest() -> [String] {
        var lines = [
            "macOS \(MBAudio.osVersionText); process tap API (14.2+): \(MBMixerEngine.apiAvailable)",
            "NSAudioCaptureUsageDescription in Info.plist: \(MBAudio.hasCaptureUsageDescription)",
            "system audio recording permission (TCC preflight, read only): \(MBAudio.capturePermission().rawValue)",
            "own process object: \(MBAudio.ownProcessObject().map { "\($0)" } ?? "none")",
        ]
        // FFT 계산 검사: 1 kHz 사인파의 가장 큰 막대
        let fft = MBSpectrumFFT(size: 1024)
        let rate: Float = 48_000
        let samples = (0..<1024).map { Float(sin(2 * Double.pi * 1000 * Double($0) / Double(rate))) * 0.5 }
        let bands = fft.bands(samples, sampleRate: rate, count: 24)
        let peak = bands.enumerated().max { $0.element < $1.element }!
        lines.append(String(format: "fft: 1 kHz sine -> loudest band %d of 24 (%.0f–%.0f Hz), level %.2f",
                            peak.offset, MBSpectrumFFT.edge(peak.offset, 24), MBSpectrumFFT.edge(peak.offset + 1, 24), peak.element))
        let silent = fft.bands([Float](repeating: 0, count: 1024), sampleRate: rate, count: 24)
        lines.append(String(format: "fft: silence -> max level %.2f", silent.max() ?? 0))
        return lines
    }
}

/// 실수 FFT → 로그 간격 막대 (vDSP)
final class MBSpectrumFFT {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var real: [Float], imag: [Float], mags: [Float]

    init(size: Int) {
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
        mags = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// 막대 경계 주파수 (40 Hz ~ 16 kHz 로그 간격)
    static func edge(_ i: Int, _ count: Int) -> Float {
        40 * pow(16_000 / 40, Float(i) / Float(count))
    }

    /// 0~1 막대 값 (-70 dB ~ -10 dB)
    func bands(_ samples: [Float], sampleRate: Float, count: Int) -> [Float] {
        guard samples.count >= size else { return [Float](repeating: 0, count: count) }
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(size))
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(size / 2))
            }
        }
        let binHz = sampleRate / Float(size)
        let scale = 2 / Float(size)
        return (0..<count).map { b in
            let lo = max(1, Int(Self.edge(b, count) / binHz))
            let hi = min(size / 2 - 1, max(lo, Int(Self.edge(b + 1, count) / binHz)))
            var peak: Float = 0
            for i in lo...hi { peak = max(peak, mags[i] * scale) }
            let db = 20 * log10(max(peak, 1e-7))
            return min(max((db + 70) / 60, 0), 1)
        }
    }
}

final class MBSpectrumAnalyzer: ObservableObject {
    enum Status: Equatable { case off, capturing, unsupportedOS, missingUsageDescription, denied, error(String) }

    @Published private(set) var levels = [Float](repeating: 0, count: 24)
    @Published private(set) var status: Status = .off
    var running = false

    private let defaults: ModuleDefaults
    private var session: AnyObject?          // MBTapSession (14.2+)
    private var timer: Timer?
    private var visibleCount = 0
    private let fft = MBSpectrumFFT(size: 1024)
    private let ring = MBSampleRing(capacity: 4096)
    private var sampleRate: Float = 48_000
    private let watch = MBPropertyWatch()
    private let queue = DispatchQueue(label: "dmn.spectrum.io", qos: .userInteractive)

    init(module: String) { defaults = ModuleDefaults(module: module) }

    var wanted: Bool { defaults.bool("reactive", default: false) }

    func setWanted(_ on: Bool) {
        objectWillChange.send()
        defaults.set(on, "reactive")
        on ? startCapture() : stopCapture()
    }

    func tabVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        if visibleCount > 0 { checkSupport(); startCapture() } else { stopCapture() }
    }

    /// 켜기 전에도 지원 여부를 보여 준다 (권한은 묻지 않음)
    private func checkSupport() {
        guard session == nil else { return }
        if !MBMixerEngine.apiAvailable { status = .unsupportedOS }
        else if !MBAudio.hasCaptureUsageDescription { status = .missingUsageDescription }
        else if MBAudio.capturePermission() == .denied { status = .denied }
        else if case .error = status {} else { status = .off }
    }

    var supported: Bool { status == .off || status == .capturing || { if case .error = status { return true }; return false }() }

    func startCapture() {
        guard running, wanted, visibleCount > 0, session == nil, !MBAudio.isDevTool else { return }
        guard #available(macOS 14.2, *) else { status = .unsupportedOS; return }
        guard MBAudio.hasCaptureUsageDescription else { status = .missingUsageDescription; return }
        if MBAudio.capturePermission() == .denied { status = .denied; return }
        guard let uid = AudioOutput.uid(MBAudio.defaultOutput()) else { status = .error("no output device"); return }
        let ring = self.ring
        do {
            let tap = try MBTapSession(processes: [], mute: .unmuted, outputUID: uid, outputs: false, name: "DMN Spectrum", queue: queue) {
                _, input, _, output, _ in
                // 탭(맨 뒤 버퍼)을 모노로 모은다. 출력은 쓰지 않으므로 0으로 둔다.
                let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                for out in UnsafeMutableAudioBufferListPointer(output) { if let d = out.mData { memset(d, 0, Int(out.mDataByteSize)) } }
                guard let last = inList.last, let raw = last.mData else { return }
                let ch = max(1, Int(last.mNumberChannels))
                let frames = Int(last.mDataByteSize) / (4 * ch)
                ring.append(raw.assumingMemoryBound(to: Float.self), frames: frames, channels: ch)
            }
            session = tap
            sampleRate = Float(tap.format.mSampleRate > 0 ? tap.format.mSampleRate : 48_000)
            status = .capturing
        } catch {
            status = .error("\(error)")
            return
        }
        // 기본 출력이 바뀌면 다시 만든다
        watch.add(MBAudio.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.stopCapture()
            self?.startCapture()
        }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopCapture() {
        timer?.invalidate()
        timer = nil
        watch.removeAll()
        if #available(macOS 14.2, *) { (session as? MBTapSession)?.invalidate() }
        session = nil
        if status == .capturing { status = .off }
        levels = [Float](repeating: 0, count: levels.count)
    }

    private func tick() {
        let samples = ring.latest(fft.size)
        let target = fft.bands(samples, sampleRate: sampleRate, count: levels.count)
        // 올라갈 땐 바로, 내려갈 땐 천천히
        levels = zip(levels, target).map { old, new in new > old ? new : old * 0.82 + new * 0.18 }
    }
}

/// IOProc가 쓰고 메인 타이머가 읽는 고리 버퍼 (그림용이라 읽는 중 덮어써져도 괜찮다)
final class MBSampleRing {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var write = 0

    init(capacity: Int) {
        self.capacity = capacity
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }

    deinit { buffer.deallocate() }

    func append(_ src: UnsafePointer<Float>, frames: Int, channels: Int) {
        var w = write
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += src[f * channels + c] }
            buffer[w] = sum / Float(channels)
            w = (w + 1) % capacity
        }
        write = w
    }

    func latest(_ n: Int) -> [Float] {
        let end = write
        return (0..<n).map { buffer[(end - n + $0 + capacity) % capacity] }
    }
}

private struct SpectrumTab: View {
    @ObservedObject var analyzer: MBSpectrumAnalyzer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("오디오 반응 막대", "Audio-reactive bars")).font(.system(size: 12, weight: .semibold))
                Spacer()
                MBPillButton(title: analyzer.wanted ? T("켜짐", "On") : T("꺼짐", "Off"), symbol: "waveform",
                             active: analyzer.wanted, tint: .purple) { analyzer.setWanted(!analyzer.wanted) }
                    .disabled(!analyzer.supported)
                    .help(T("이 탭이 보이는 동안 시스템 출력을 탭해 막대를 움직입니다", "Taps system output while this tab is visible"))
            }
            bars
            statusLine
        }
        .foregroundStyle(.white)
        .onAppear { analyzer.tabVisible(true) }
        .onDisappear { analyzer.tabVisible(false) }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(analyzer.levels.indices, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .bottom, endPoint: .top))
                    .frame(height: max(3, CGFloat(analyzer.levels[i]) * 90))
            }
        }
        .frame(height: 92, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .opacity(analyzer.status == .capturing ? 1 : 0.3)
        .accessibilityLabel(T("오디오 스펙트럼", "Audio spectrum"))
    }

    @ViewBuilder private var statusLine: some View {
        switch analyzer.status {
        case .capturing:
            Text(T("시스템 오디오 탭 사용 중 · 메뉴 막대에 보라색 녹음 표시가 뜹니다. 소리는 저장하지 않습니다.",
                   "Using a system audio tap · the purple recording dot shows. Nothing is recorded."))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        case .off:
            Text(T("켜면 이 탭이 보이는 동안만 탭을 만들고, 닫으면 바로 지웁니다. 필요: macOS 14.2+(API), 시스템 오디오 녹음 권한.",
                   "When on, a tap exists only while this tab is visible. Needs macOS 14.2+ (API) and System Audio Recording permission."))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
        case .unsupportedOS:
            MBUnsupportedBox(title: T("지원 안 됨", "Unsupported"), reason: T("macOS 14.2 이상이 필요합니다", "Needs macOS 14.2 or later"),
                             alternative: T("대안: 노치의 기본 파형 표시", "Alternative: the notch's built-in waveform"))
        case .missingUsageDescription:
            MBUnsupportedBox(title: T("지원 안 됨", "Unsupported"),
                             reason: T("Info.plist에 NSAudioCaptureUsageDescription이 없어 시스템 오디오 탭을 만들 수 없습니다.",
                                       "Info.plist lacks NSAudioCaptureUsageDescription, so a system audio tap can't be created."),
                             alternative: T("대안: 노치의 기본 파형 표시", "Alternative: the notch's built-in waveform"))
        case .denied:
            MBUnsupportedBox(title: T("권한 거부됨", "Permission denied"),
                             reason: T("시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 허용하세요.",
                                       "Allow it under Privacy & Security → Screen & System Audio Recording."))
                .onTapGesture { MBAudio.openPrivacySettings("Privacy_ScreenCapture") }
        case .error(let msg):
            MBUnsupportedBox(title: T("탭을 만들지 못함", "Couldn't create the tap"), reason: msg)
        }
    }
}
