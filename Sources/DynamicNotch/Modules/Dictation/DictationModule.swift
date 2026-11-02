import AVFoundation
import AppKit
import Carbon.HIToolbox
import Speech
import SwiftUI

/// 로컬 받아쓰기: 단축키(기본 ⌃⌥D)로 시작·종료, 기기 안 음성 인식만 쓰고 결과를 노치를 열기 전 앱에 붙여넣는다.
/// 2.5초 침묵이나 2분이 지나면 끝난다. 마이크·음성 인식 권한은 처음 시작할 때만 요청. 기본 꺼짐.
final class DictationModule: NotchModule, ObservableObject {
    let id = "dictation"
    var title: String { T("받아쓰기", "Dictation") }
    let symbol = "mic"
    var enabledByDefault: Bool { false }

    static let defaultShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey))
    static let silenceLimit: TimeInterval = 2.5
    static let maxLength: TimeInterval = 120
    static let languages = ["ko-KR", "en-US", "ja-JP", "zh-CN", "es-ES", "fr-FR", "de-DE"]

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    var shortcut: HotKeyCenter.Shortcut { defaults.launchShortcut("shortcut", default: Self.defaultShortcut) }
    var language: String { defaults.string("language", default: L10n.isEnglish ? "en-US" : "ko-KR") }

    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    @Published private(set) var lastResult = ""
    @Published private(set) var message = ""

    fileprivate var context: ModuleContext?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var ticker: Timer?
    private var startedAt = Date()
    private var lastChange = Date()

    /// Info.plist에 마이크·음성 인식 문구가 있어야 요청할 수 있다 (없이 요청하면 macOS가 앱을 끝낸다)
    static var plistReady: Bool {
        LaunchSystem.hasUsageKey("NSMicrophoneUsageDescription") && LaunchSystem.hasUsageKey("NSSpeechRecognitionUsageDescription")
    }

    func start(context: ModuleContext) {
        self.context = context
        HotKeyCenter.shared.register("dictation.toggle", shortcut) { [weak self] in self?.toggle() }
    }

    func stop() {
        HotKeyCenter.shared.unregister("dictation.toggle")
        finish(paste: false)
        context = nil
    }

    func settingsChanged() {
        guard context != nil else { return }
        HotKeyCenter.shared.register("dictation.toggle", shortcut) { [weak self] in self?.toggle() }
    }

    func tabView() -> AnyView? { AnyView(DictationTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 440, height: 180) }
    func settingsView() -> AnyView? { AnyView(DictationSettings(module: self)) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "dictation.toggle", title: listening ? T("받아쓰기 끝내기", "Stop dictation") : T("받아쓰기 시작", "Start dictation"),
                       subtitle: shortcut.display, symbol: symbol, keywords: ["dictation", "voice", "받아쓰기", "음성"]) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.toggle() }
        }]
    }

    func toggle() { listening ? finish(paste: true) : begin() }

    // MARK: 시작

    func begin() {
        guard Self.plistReady else {
            message = T("지원 안 됨: 앱 정보(Info.plist)에 마이크·음성 인식 권한 문구가 없음", "Unsupported: the app's Info.plist lacks microphone/speech usage text")
            context?.notice(T("받아쓰기 지원 안 됨", "Dictation unavailable"), T("앱에 마이크·음성 인식 권한 문구가 없음 · 대안: macOS 받아쓰기(Fn 두 번)", "Missing usage text · Alternative: macOS Dictation (press Fn twice)"),
                            symbol: "mic.slash")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            message = T("이 언어는 음성 인식을 지원하지 않음", "Speech recognition does not support this language")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            message = T("기기 안 음성 모델 없음 · 시스템 설정 > 키보드 > 받아쓰기에서 언어를 추가", "No on-device model · add the language in System Settings > Keyboard > Dictation")
            context?.notice(T("기기 안 음성 모델 없음", "No on-device speech model"), language, symbol: "mic.slash")
            return
        }
        authorize { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.message = T("마이크 또는 음성 인식 권한이 없음 · 시스템 설정 > 개인정보 보호에서 허용", "Microphone or speech access denied · allow it in System Settings > Privacy")
                return
            }
            self.run(recognizer)
        }
    }

    /// 정해지지 않았을 때만 요청한다 (사용자가 시작했을 때)
    private func authorize(_ done: @escaping (Bool) -> Void) {
        func mic(_ next: @escaping (Bool) -> Void) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: next(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { next(ok) } }
            default: next(false)
            }
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: mic(done)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { s in DispatchQueue.main.async { s == .authorized ? mic(done) : done(false) } }
        default: done(false)
        }
    }

    private func run(_ recognizer: SFSpeechRecognizer) {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            message = T("마이크를 열 수 없음: ", "Could not open the microphone: ") + error.localizedDescription
            return
        }
        self.engine = engine
        self.request = request
        transcript = ""
        startedAt = Date()
        lastChange = Date()
        listening = true
        message = ""
        showChip()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.transcript { self.transcript = text; self.lastChange = Date(); self.showChip() }
                    if result.isFinal { self.complete() }
                }
                if error != nil, self.listening { self.finish(paste: true) }
            }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.listening else { return }
            let now = Date()
            let quiet = now.timeIntervalSince(self.lastChange)
            if (!self.transcript.isEmpty && quiet >= Self.silenceLimit) || quiet >= 8 || now.timeIntervalSince(self.startedAt) >= Self.maxLength {
                self.finish(paste: true)
            }
        }
    }

    /// 노치에 단어 수와 최근 단어를 보여 준다
    private func showChip() {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        let tail = words.suffix(5).joined(separator: " ")
        context?.notice(T("받아쓰는 중 · \(words.count)단어", "Listening · \(words.count) words"), tail.isEmpty ? T("말해 보세요", "Start speaking") : tail,
                        symbol: "mic.fill", tint: .red, duration: Self.maxLength + 5)
    }

    // MARK: 끝

    private var pasteOnComplete = false

    func finish(paste: Bool) {
        guard listening else { return }
        listening = false
        pasteOnComplete = paste
        ticker?.invalidate()
        ticker = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // 마지막 결과를 잠깐 기다린다
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.complete() }
    }

    private func complete() {
        guard engine != nil else { return }
        listening = false
        ticker?.invalidate()
        ticker = nil
        task?.cancel()
        task = nil
        request = nil
        engine = nil
        context?.center.dismissTransient(kind: .notice)
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastResult = text
        guard pasteOnComplete, !text.isEmpty else { return }
        if !ModuleServices.paste(text) {
            context?.notice(T("클립보드에 복사함", "Copied to clipboard"), T("손쉬운 사용 권한이 있으면 바로 붙여넣음", "With Accessibility access it pastes directly"), symbol: "doc.on.clipboard")
        }
    }

    func selfTest() -> [String] {
        var out = ["Info.plist NSMicrophoneUsageDescription: \(LaunchSystem.hasUsageKey("NSMicrophoneUsageDescription") ? "present" : "missing")",
                   "Info.plist NSSpeechRecognitionUsageDescription: \(LaunchSystem.hasUsageKey("NSSpeechRecognitionUsageDescription") ? "present" : "missing")",
                   "-> \(Self.plistReady ? "can request permission on first start" : "tab shows unsupported until the integrator adds both keys")"]
        let speech: String = {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "not determined"
            @unknown default: return "other"
            }
        }()
        out.append("speech auth: \(speech) · mic auth raw: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        for l in ["ko-KR", "en-US"] {
            let r = SFSpeechRecognizer(locale: Locale(identifier: l))
            out.append("\(l): recognizer \(r != nil ? "ok" : "none"), on-device \(r?.supportsOnDeviceRecognition == true ? "yes" : "no")")
        }
        out.append("shortcut: \(shortcut.display) · silence \(Self.silenceLimit)s · max \(Int(Self.maxLength))s")
        out.append("microphone opened in self test: no")
        return out
    }
}

private struct DictationTab: View {
    @ObservedObject var module: DictationModule

    var body: some View {
        if !DictationModule.plistReady {
            LaunchUnsupportedView(title: T("받아쓰기 지원 안 됨", "Dictation unavailable"),
                                  reason: T("앱 정보(Info.plist)에 마이크·음성 인식 권한 문구가 없어 권한을 요청할 수 없음", "The app's Info.plist lacks microphone and speech-recognition usage text, so access can't be requested"),
                                  alternative: T("대안: macOS 기본 받아쓰기 (Fn 두 번 또는 🎤 키)", "Alternative: macOS Dictation (press Fn twice or the 🎤 key)"),
                                  symbol: "mic.slash")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { module.toggle() } label: {
                        Image(systemName: module.listening ? "stop.fill" : "mic.fill").font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(module.listening ? Color.red.opacity(0.8) : LaunchUI.fill))
                    }
                    .buttonStyle(.plain)
                    .help(module.listening ? T("끝내기", "Stop") : T("시작", "Start"))
                    .accessibilityLabel(module.listening ? T("받아쓰기 끝내기", "Stop dictation") : T("받아쓰기 시작", "Start dictation"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.listening ? T("듣는 중 · 2.5초 조용하면 끝남", "Listening · stops after 2.5s of silence") : T("기기 안 음성 인식 · \(module.shortcut.display)", "On-device recognition · \(module.shortcut.display)"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(TranslateModule.name(module.language)).font(.system(size: 11)).foregroundStyle(LaunchUI.secondary)
                    }
                    Spacer()
                }
                ScrollView {
                    Text(module.listening ? module.transcript : (module.lastResult.isEmpty ? T("결과는 노치를 열기 전 앱에 붙여넣음", "The result is pasted into the app you were using") : module.lastResult))
                        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                if !module.message.isEmpty {
                    Text(module.message).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

private struct DictationSettings: View {
    let module: DictationModule
    @State private var shortcut = DictationModule.defaultShortcut
    @State private var language = "ko-KR"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("시작·종료 단축키", "Start/stop shortcut"))
                LaunchShortcutRecorder(current: shortcut) { s in
                    shortcut = s
                    ModuleDefaults(module: module.id).setLaunchShortcut(s, "shortcut")
                }
            }
            Picker(T("언어", "Language"), selection: $language) {
                ForEach(DictationModule.languages, id: \.self) { Text(TranslateModule.name($0)).tag($0) }
            }
            .onChange(of: language) { _, v in ModuleDefaults(module: module.id).set(v, "language") }
            Text(T("기기 안 음성 모델만 씁니다. 모델이 없으면 시스템 설정 > 키보드 > 받아쓰기에서 언어를 추가하세요. Fn 키로 시작하는 기능은 아직 없습니다.",
                   "Only the on-device speech model is used. If it's missing, add the language in System Settings > Keyboard > Dictation. Starting with the Fn key is not supported yet."))
                .font(.caption).foregroundStyle(.secondary)
            if !DictationModule.plistReady {
                Text(T("지금 빌드에는 마이크·음성 인식 권한 문구가 없어 받아쓰기를 시작할 수 없습니다.", "This build lacks the microphone/speech usage text, so dictation can't start."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { shortcut = module.shortcut; language = module.language }
    }
}
