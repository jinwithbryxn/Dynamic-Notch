import AppKit
import CoreAudio
import SwiftUI

/// 앱별 사운드 (프로토타입): 소리를 내는 앱마다 음량(0–150%)·음소거·3밴드 EQ·출력 기기.
/// 기본값(100%, EQ 평탄, 기본 출력)인 앱은 건드리지 않고, 바꾼 앱만 Core Audio 프로세스 탭으로 소리를 받아
/// 처리한 뒤 비공개 집계 장치로 출력한다. 끄거나 앱을 끝내면 탭·집계 장치를 지워 원래 소리로 돌아간다.
/// 비정상 종료 때는 private 탭·집계 장치가 프로세스와 함께 사라지고, 다음 실행에서 남은 것을 한 번 더 정리한다.
final class SoundMixerModule: NotchModule {
    let id = "soundmixer"
    var title: String { T("앱별 사운드", "Sound Mixer") }
    let symbol = "slider.vertical.3"
    let enabledByDefault = false

    let engine = MBMixerEngine(module: "soundmixer")

    func start(context: ModuleContext) { engine.start(context: context) }
    func stop() { engine.stop() }

    func tabView() -> AnyView? { AnyView(SoundMixerTab(engine: engine)) }
    var tabContentSize: CGSize { CGSize(width: 520, height: 290) }

    func settingsView() -> AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            Text(T("앱별 음량·음소거·EQ·출력 기기를 바꾸면 그 앱의 소리를 Core Audio 프로세스 탭으로 받아 처리합니다. 탭이 있는 동안 메뉴 막대에 보라색 녹음 표시가 뜹니다. 소리를 녹음·저장·전송하지 않습니다.",
                   "Changing an app's volume, mute, EQ or output routes that app through a Core Audio process tap. The purple recording indicator shows while a tap exists. Audio is never recorded, stored or sent."))
            Text(T("필요: macOS 14.2 이상(API 기준, Notchy는 14.4 이상 요구), 시스템 오디오 녹음 권한, 앱 Info.plist의 NSAudioCaptureUsageDescription.",
                   "Requires macOS 14.2+ (API; Notchy asks for 14.4+), System Audio Recording permission and NSAudioCaptureUsageDescription in the app's Info.plist."))
                .foregroundStyle(.secondary)
            Button(T("모든 앱 설정 초기화", "Reset all app settings")) { ModuleDefaults(module: "soundmixer").set(nil, "apps") }
        }.font(.caption))
    }

    func selfTest() -> [String] {
        var lines: [String] = []
        lines.append("macOS \(MBAudio.osVersionText); process tap API (14.2+): \(MBMixerEngine.apiAvailable)")
        lines.append("NSAudioCaptureUsageDescription in Info.plist: \(MBAudio.hasCaptureUsageDescription)")
        lines.append("system audio recording permission (TCC preflight, read only): \(MBAudio.capturePermission().rawValue)")
        let left = MBTapLedger.leftovers()
        lines.append("leftover taps \(left.taps.count), leftover aggregate devices \(left.aggregates.count), ledger \(MBTapLedger.recorded.count)")
        let procs = MBAudio.processes()
        let apps = MBMixerEngine.groupApps(procs, settings: [:], includeIdle: true)
        lines.append("\(procs.count) audio client processes grouped into \(apps.count) apps (\(apps.filter(\.playing).count) playing):")
        for a in apps.prefix(12) {
            lines.append("  \(a.name) [\(a.id)] objects=\(a.objects.count) playing=\(a.playing)")
        }
        lines.append(contentsOf: MBMixerEngine.dspSelfTest())
        return lines
    }
}

final class MBMixerEngine: ObservableObject {
    struct AppSetting: Codable, Equatable {
        var volume: Float = 1
        var muted = false
        var low: Float = 0, mid: Float = 0, high: Float = 0   // dB
        var outputUID: String? = nil

        var isDefault: Bool { abs(volume - 1) < 0.005 && !muted && abs(low) < 0.1 && abs(mid) < 0.1 && abs(high) < 0.1 && outputUID == nil }
        var eqOn: Bool { abs(low) >= 0.1 || abs(mid) >= 0.1 || abs(high) >= 0.1 }
    }

    struct AppRow: Identifiable, Equatable {
        let id: String          // 묶음 기준 번들 ID
        let name: String
        let pid: pid_t
        var objects: [AudioObjectID]
        var playing: Bool
        static func == (a: AppRow, b: AppRow) -> Bool { a.id == b.id && a.objects == b.objects && a.playing == b.playing && a.name == b.name }
    }

    /// 환경 조건 (탭 생성 실패는 lastError로 따로 보여 주고 다른 앱은 계속 처리한다)
    enum Status: Equatable { case ready, unsupportedOS, missingUsageDescription, denied }

    @Published private(set) var apps: [AppRow] = []
    @Published private(set) var settings: [String: AppSetting] = [:]
    @Published private(set) var status: Status = .ready
    @Published private(set) var tappedCount = 0
    @Published private(set) var lastError: String?
    @Published var expanded: String?

    static var apiAvailable: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    private let defaults: ModuleDefaults
    private let watch = MBPropertyWatch()
    private var running = false
    private var sessions: [String: AnyObject] = [:]       // MBMixerSession (14.2+)
    private var reconcileWork: DispatchWorkItem?
    private var visibleTimer: Timer?
    private var visibleCount = 0
    private var context: ModuleContext?
    private let ioQueue = DispatchQueue(label: "dmn.soundmixer.io", qos: .userInteractive)

    init(module: String) {
        defaults = ModuleDefaults(module: module)
        settings = (defaults.data("apps").flatMap { try? JSONDecoder().decode([String: AppSetting].self, from: $0) }) ?? [:]
    }

    // MARK: 시작·정지

    func start(context: ModuleContext) {
        guard !running else { return }
        running = true
        self.context = context
        settings = (defaults.data("apps").flatMap { try? JSONDecoder().decode([String: AppSetting].self, from: $0) }) ?? [:]
        checkStatus()
        if #available(macOS 14.2, *), !MBAudio.isDevTool {
            let swept = MBTapLedger.sweep()
            if swept > 0 {
                context.notice(T("남은 오디오 탭을 정리했어요", "Cleaned up leftover audio taps"), "\(swept)", symbol: "slider.vertical.3", tab: "soundmixer")
            }
        }
        // 프로세스 목록·기본 출력 변화 (읽기 전용 감시)
        watch.add(MBAudio.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.scheduleReconcile() }
        watch.add(MBAudio.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.scheduleReconcile(rebuildAll: true) }
        watch.add(MBAudio.system, kAudioHardwarePropertyDevices) { [weak self] in self?.scheduleReconcile() }
        refreshApps()
        reconcile()
    }

    func stop() {
        guard running else { return }
        running = false
        watch.removeAll()
        reconcileWork?.cancel()
        visibleTimer?.invalidate()
        visibleTimer = nil
        destroyAll()
        context = nil
    }

    private func destroyAll() {
        if #available(macOS 14.2, *) {
            for s in sessions.values { (s as? MBMixerSession)?.tap.invalidate() }
        }
        sessions.removeAll()
        tappedCount = 0
    }

    private func checkStatus() {
        let s: Status
        if !Self.apiAvailable { s = .unsupportedOS }
        else if !MBAudio.hasCaptureUsageDescription { s = .missingUsageDescription }
        else if MBAudio.capturePermission() == .denied { s = .denied }
        else { s = .ready }
        if s != status { status = s }
    }

    // MARK: 앱 목록

    func tabVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        visibleTimer?.invalidate()
        visibleTimer = nil
        guard visibleCount > 0, running else { return }
        checkStatus()
        refreshApps()
        // 재생 여부는 프로세스별 속성이라, 탭이 보이는 동안만 1.5초마다 다시 읽는다
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refreshApps() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        visibleTimer = t
    }

    private func refreshApps() {
        let rows = Self.groupApps(MBAudio.processes(), settings: settings)
        if rows != apps { apps = rows }
    }

    /// 프로세스 객체를 앱 단위로 묶는다: 책임 프로세스(responsible pid) → 번들 ID 접두사 순.
    static func groupApps(_ list: [MBAudio.Process], settings: [String: AppSetting], includeIdle: Bool = false) -> [AppRow] {
        let me = ProcessInfo.processInfo.processIdentifier
        var groups: [String: AppRow] = [:]
        let running = NSWorkspace.shared.runningApplications
        for p in list where p.pid > 0 && p.pid != me {
            guard let app = owningApp(pid: p.pid, bundleID: p.bundleID, running: running),
                  let bid = app.bundleIdentifier, app.processIdentifier != me else { continue }
            var row = groups[bid] ?? AppRow(id: bid, name: app.localizedName ?? bid, pid: app.processIdentifier, objects: [], playing: false)
            row.objects.append(p.object)
            row.playing = row.playing || p.runningOutput
            groups[bid] = row
        }
        // 소리를 내는 앱 + 설정을 바꿔 둔 앱만
        return groups.values
            .filter { includeIdle || $0.playing || !(settings[$0.id]?.isDefault ?? true) }
            .map { var r = $0; r.objects.sort(); return r }
            .sorted { ($0.playing ? 0 : 1, $0.name) < ($1.playing ? 0 : 1, $1.name) }
    }

    private static func owningApp(pid: pid_t, bundleID: String, running: [NSRunningApplication]) -> NSRunningApplication? {
        typealias Responsible = @convention(c) (pid_t) -> pid_t
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") {
            let rp = unsafeBitCast(sym, to: Responsible.self)(pid)
            if rp > 0, let app = NSRunningApplication(processIdentifier: rp), app.activationPolicy != .prohibited { return app }
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited { return app }
        // "com.google.Chrome.helper" → "com.google.Chrome"
        let candidates = running.filter { a in
            guard let b = a.bundleIdentifier, a.activationPolicy == .regular else { return false }
            return bundleID.hasPrefix(b + ".")
        }
        return candidates.max { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    // MARK: 설정 바꾸기

    func setting(_ bundleID: String) -> AppSetting { settings[bundleID] ?? AppSetting() }

    func update(_ bundleID: String, _ change: (inout AppSetting) -> Void) {
        var s = setting(bundleID)
        change(&s)
        if s.isDefault { settings[bundleID] = nil } else { settings[bundleID] = s }
        defaults.set(try? JSONEncoder().encode(settings), "apps")
        // 이미 탭 중인 앱은 실시간 값만 바꾸고, 새로 필요하면 탭을 만든다
        if #available(macOS 14.2, *), let session = sessions[bundleID] as? MBMixerSession, session.tap.outputUID == resolvedOutputUID(s) {
            session.apply(s)
            if s.isDefault { scheduleReconcile() }
        } else {
            scheduleReconcile()
        }
    }

    func reset(_ bundleID: String) { update(bundleID) { $0 = AppSetting() } }

    private func resolvedOutputUID(_ s: AppSetting) -> String? {
        if let uid = s.outputUID, MBAudio.device(uid: uid) != nil { return uid }
        return AudioOutput.uid(MBAudio.defaultOutput())
    }

    // MARK: 탭 맞추기

    private func scheduleReconcile(rebuildAll: Bool = false) {
        reconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            if rebuildAll { self.destroyAll() }
            self.refreshApps()
            self.reconcile()
        }
        reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 기본값이 아닌 앱마다 탭을 하나씩 둔다. 프로세스 묶음·출력 기기가 바뀌면 다시 만든다.
    private func reconcile() {
        guard running, !MBAudio.isDevTool else { return }
        guard #available(macOS 14.2, *) else { return }
        checkStatus()
        guard status == .ready else { destroyAll(); return }
        let all = Self.groupApps(MBAudio.processes(), settings: settings)
        var wanted: [String: (AppRow, AppSetting, String)] = [:]
        for row in all {
            guard let s = settings[row.id], !s.isDefault, let uid = resolvedOutputUID(s) else { continue }
            wanted[row.id] = (row, s, uid)
        }
        // 필요 없거나 바뀐 탭 지우기
        for (bid, obj) in sessions {
            guard let session = obj as? MBMixerSession else { continue }
            if let w = wanted[bid], w.0.objects == session.tap.processes, w.2 == session.tap.outputUID { continue }
            session.tap.invalidate()
            sessions[bid] = nil
        }
        // 새로 만들기 (실패한 앱은 원래 소리 그대로 두고 이유를 보여 준다)
        var failure: String?
        for (bid, w) in wanted where sessions[bid] == nil {
            do {
                let session = try MBMixerSession(objects: w.0.objects, outputUID: w.2, name: "DMN Mixer \(w.0.name)", queue: ioQueue)
                session.apply(w.1)
                sessions[bid] = session
            } catch {
                failure = "\(w.0.name): \(error)"
            }
        }
        if lastError != failure { lastError = failure }
        tappedCount = sessions.count
    }

    // MARK: 검사 (실제 장치를 쓰지 않는 계산 검사)

    static func dspSelfTest() -> [String] {
        let rate = 48_000.0
        func sine(_ freq: Double, _ n: Int) -> [Float] { (0..<n).map { Float(0.5 * sin(2 * Double.pi * freq * Double($0) / rate)) } }
        func run(_ input: [Float], _ v: MBTapParams.Values) -> Float {
            var asbd = AudioStreamBasicDescription()
            asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            asbd.mChannelsPerFrame = 1
            let p = MBTapProcessor(format: asbd)
            p.params.set(v)
            var outBuf = [Float](repeating: 0, count: input.count)
            var src = input
            src.withUnsafeMutableBytes { inRaw in
                outBuf.withUnsafeMutableBytes { outRaw in
                    var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(inRaw.count), mData: inRaw.baseAddress))
                    var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(outRaw.count), mData: outRaw.baseAddress))
                    p.render(input: &inList, output: &outList)
                }
            }
            return outBuf.suffix(input.count / 2).map(abs).max() ?? 0
        }
        let n = 9600
        var half = MBTapParams.Values(); half.gain = 0.5
        var muted = MBTapParams.Values(); muted.muted = true
        var boost = MBTapParams.Values(); boost.eqOn = true; boost.low = .lowShelf(freq: 200, gainDB: 12, rate: rate)
        var cut = MBTapParams.Values(); cut.eqOn = true; cut.high = .highShelf(freq: 4000, gainDB: -12, rate: rate)
        return [
            String(format: "dsp: gain 0.5 on 0.5 sine -> peak %.3f (expect 0.250)", run(sine(440, n), half)),
            String(format: "dsp: muted -> peak %.3f (expect 0)", run(sine(440, n), muted)),
            String(format: "dsp: low shelf +12 dB on 60 Hz -> peak %.3f (expect ~1.0, clipped)", run(sine(60, n), boost)),
            String(format: "dsp: high shelf -12 dB on 10 kHz -> peak %.3f (expect ~0.126)", run(sine(10_000, n), cut)),
        ]
    }
}

/// 앱 하나의 탭 + 처리기
@available(macOS 14.2, *)
final class MBMixerSession {
    let tap: MBTapSession
    let processor: MBTapProcessor

    init(objects: [AudioObjectID], outputUID: String, name: String, queue: DispatchQueue) throws {
        var holder: MBTapProcessor?
        tap = try MBTapSession(processes: objects, mute: .mutedWhenTapped, outputUID: outputUID, outputs: true, name: name, queue: queue) {
            _, input, _, output, _ in
            if let h = holder {
                h.render(input: input, output: output)
            } else {
                // 처리기가 붙기 전 몇 프레임은 무음
                for b in UnsafeMutableAudioBufferListPointer(output) { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            }
        }
        let p = MBTapProcessor(format: tap.format)
        processor = p
        // IOProc가 처리기를 쓰기 시작하는 시점은 이 대입 이후 (그 전 몇 프레임은 무음)
        queue.sync { holder = p }
    }

    func apply(_ s: MBMixerEngine.AppSetting) {
        let rate = tap.format.mSampleRate > 0 ? tap.format.mSampleRate : 48_000
        var v = MBTapParams.Values()
        v.gain = s.volume
        v.muted = s.muted
        v.eqOn = s.eqOn
        v.low = .lowShelf(freq: 200, gainDB: Double(s.low), rate: rate)
        v.mid = .peak(freq: 1_000, gainDB: Double(s.mid), q: 0.9, rate: rate)
        v.high = .highShelf(freq: 4_000, gainDB: Double(s.high), rate: rate)
        processor.params.set(v)
    }
}

// MARK: - 화면

private struct SoundMixerTab: View {
    @ObservedObject var engine: MBMixerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(T("앱별 사운드", "Sound Mixer")).font(.system(size: 12, weight: .semibold))
                Text(T("프로토타입", "Prototype")).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.8))).foregroundStyle(.black)
                Spacer()
                if engine.tappedCount > 0 {
                    Label(T("탭 \(engine.tappedCount)개 · 보라색 표시", "\(engine.tappedCount) tapped · purple dot"), systemImage: "record.circle")
                        .font(.system(size: 10)).foregroundStyle(.purple)
                        .help(T("소리를 바꾼 앱마다 시스템 오디오 탭이 하나씩 있습니다. 모두 100%로 되돌리면 사라집니다.",
                                "One system audio tap per changed app. Resetting them to 100% removes it."))
                }
            }
            statusBox
            if engine.apps.isEmpty {
                Spacer()
                Text(T("지금 소리를 내는 앱이 없습니다", "No app is playing audio right now"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(engine.apps) { app in MixerRow(engine: engine, app: app) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { engine.tabVisible(true) }
        .onDisappear { engine.tabVisible(false) }
    }

    @ViewBuilder private var statusBox: some View {
        switch engine.status {
        case .ready: EmptyView()
        case .unsupportedOS:
            MBUnsupportedBox(title: T("이 macOS에서는 지원 안 됨", "Not supported on this macOS"),
                             reason: T("앱별 사운드는 Core Audio 프로세스 탭(macOS 14.2 이상)이 필요합니다. 지금: \(MBAudio.osVersionText)",
                                       "Per-app audio needs Core Audio process taps (macOS 14.2+). This Mac: \(MBAudio.osVersionText)"),
                             alternative: T("대안: 앱 자체 음량 조절", "Alternative: each app's own volume control"))
        case .missingUsageDescription:
            MBUnsupportedBox(title: T("시스템 오디오 녹음 설명 없음", "Missing audio capture description"),
                             reason: T("앱 Info.plist에 NSAudioCaptureUsageDescription이 없어 권한을 요청할 수 없습니다. 통합 빌드에서 추가되면 동작합니다. 목록은 읽기만 합니다.",
                                       "The app's Info.plist lacks NSAudioCaptureUsageDescription, so the permission can't be requested. The list below is read-only until it is added."),
                             alternative: T("대안: 앱 자체 음량 조절", "Alternative: each app's own volume control"))
        case .denied:
            MBUnsupportedBox(title: T("시스템 오디오 녹음 권한 거부됨", "System audio recording denied"),
                             reason: T("시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음 화면 아래쪽 '시스템 오디오 녹음만' 목록에서 허용하세요. 위쪽 목록과는 따로입니다.",
                                       "Allow it in the 'System Audio Recording Only' list at the bottom of System Settings → Privacy & Security → Screen & System Audio Recording. It is separate from the list above it."))
                .onTapGesture { MBAudio.openPrivacySettings("Privacy_ScreenCapture") }
        }
        if let msg = engine.lastError {
            MBUnsupportedBox(title: T("탭을 만들지 못함", "Couldn't create a tap"), reason: msg,
                             alternative: T("그 앱은 원래 소리로 재생됩니다", "That app keeps playing normally"))
        }
    }
}

private struct MixerRow: View {
    @ObservedObject var engine: MBMixerEngine
    let app: MBMixerEngine.AppRow
    @State private var dragVolume: Float?

    var body: some View {
        let s = engine.setting(app.id)
        let open = engine.expanded == app.id
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: MBMixerEngine.icon(for: app.id)).resizable().frame(width: 20, height: 20)
                Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).frame(width: 96, alignment: .leading)
                Button { engine.update(app.id) { $0.muted.toggle() } } label: {
                    Image(systemName: s.muted ? "speaker.slash.fill" : (app.playing ? "speaker.wave.2.fill" : "speaker.fill"))
                        .font(.system(size: 10)).frame(width: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(s.muted ? .red : .white.opacity(0.7))
                .help(T("이 앱 음소거", "Mute this app"))
                .accessibilityLabel(T("\(app.name) 음소거", "Mute \(app.name)"))
                ScrubBar(fraction: Double((dragVolume ?? s.volume) / 1.5), enabled: engine.status == .ready, spacing: 6, thickness: 4,
                         onScrub: { f in
                             let v = Float(f) * 1.5
                             // 100% 근처는 딱 맞춘다
                             let snapped = abs(v - 1) < 0.04 ? 1 : v
                             dragVolume = snapped
                             engine.update(app.id) { $0.volume = snapped }
                         }, onEnd: { dragVolume = nil },
                         leading: { EmptyView() },
                         trailing: {
                             Text("\(Int(((dragVolume ?? s.volume) * 100).rounded()))%")
                                 .font(.system(size: 10, design: .rounded)).monospacedDigit()
                                 .foregroundStyle((dragVolume ?? s.volume) > 1.001 ? .orange : .white.opacity(0.6))
                                 .frame(width: 36, alignment: .trailing)
                         })
                    .help(T("앱 음량 (최대 150%)", "App volume (up to 150%)"))
                Button { engine.expanded = open ? nil : app.id } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(s.eqOn || s.outputUID != nil ? .green : .white.opacity(0.6))
                .help(T("EQ·출력 기기", "EQ and output"))
            }
            if open {
                HStack(spacing: 10) {
                    eqSlider(T("저음", "Low"), s.low) { v in engine.update(app.id) { $0.low = v } }
                    eqSlider(T("중음", "Mid"), s.mid) { v in engine.update(app.id) { $0.mid = v } }
                    eqSlider(T("고음", "High"), s.high) { v in engine.update(app.id) { $0.high = v } }
                }
                HStack(spacing: 8) {
                    Menu {
                        Button(T("시스템 기본 출력", "System default output")) { engine.update(app.id) { $0.outputUID = nil } }
                        Divider()
                        ForEach(AudioOutput.outputDevices(), id: \.self) { d in
                            Button(AudioOutput.displayName(d)) { engine.update(app.id) { $0.outputUID = AudioOutput.uid(d) } }
                        }
                    } label: {
                        Text(s.outputUID.flatMap { MBAudio.device(uid: $0) }.map { AudioOutput.displayName($0) } ?? T("시스템 기본 출력", "System default output"))
                            .font(.system(size: 10.5))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(T("이 앱만 다른 출력 기기로 보내기", "Send only this app to another output"))
                    Spacer()
                    MBPillButton(title: T("초기화", "Reset"), symbol: "arrow.counterclockwise") { engine.reset(app.id) }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
    }

    private func eqSlider(_ label: String, _ value: Float, _ set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.6)).frame(width: 24, alignment: .leading)
            ScrubBar(fraction: Double((value + 12) / 24), enabled: engine.status == .ready, spacing: 4, thickness: 3,
                     onScrub: { f in
                         let db = Float(f) * 24 - 12
                         set(abs(db) < 0.6 ? 0 : (db * 2).rounded() / 2)
                     }, onEnd: {}, leading: { EmptyView() },
                     trailing: { Text(String(format: "%+.0f", value)).font(.system(size: 9, design: .rounded)).monospacedDigit()
                         .foregroundStyle(.white.opacity(0.6)).frame(width: 22, alignment: .trailing) })
        }
        .help(T("\(label) ±12 dB", "\(label) ±12 dB"))
    }
}
