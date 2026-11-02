import AppKit
import SwiftUI

/// 캡처·개인정보 모듈 알림에 붙는 소리 종류
enum CPSoundEvent: String, CaseIterable, Identifiable {
    case cameraGuard, micOn, meetingStart, meetingEnd, cleaningDone, windowChanged, captureDone
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cameraGuard: return T("Camera Guard 경고", "Camera Guard warning")
        case .micOn: return T("마이크 켜짐", "Microphone turned on")
        case .meetingStart: return T("회의 통화 시작", "Meeting call started")
        case .meetingEnd: return T("회의 통화 끝", "Meeting call ended")
        case .cleaningDone: return T("키보드 청소 잠금 해제", "Keyboard cleaning unlocked")
        case .windowChanged: return T("지켜보는 창이 바뀜", "Watched window changed")
        case .captureDone: return T("캡처·글자 인식 완료", "Capture or OCR done")
        }
    }

    /// 기본 소리 ("" = 무음)
    var defaultChoice: String {
        switch self {
        case .cameraGuard: return "system:Funk"
        case .cleaningDone: return "system:Glass"
        case .windowChanged: return "system:Tink"
        default: return ""
        }
    }
}

/// 소리 재생. 선택값: "" 무음, "system:<이름>" (/System/Library/Sounds), "file:<경로>" (사용자 파일)
enum CPSounds {
    private static var defaults: ModuleDefaults { ModuleDefaults(module: NoticeSoundsModule.moduleID) }
    private static var current: NSSound?

    static func choice(for event: CPSoundEvent) -> String {
        defaults.string(event.rawValue, default: event.defaultChoice)
    }

    static func setChoice(_ value: String, for event: CPSoundEvent) { defaults.set(value, event.rawValue) }

    /// 알림 소리 기능이 켜져 있을 때만 재생
    static func play(_ event: CPSoundEvent) {
        guard defaults.bool("enabled", default: true) else { return }
        preview(choice(for: event))
    }

    static func preview(_ choice: String) {
        guard let sound = sound(for: choice) else { return }
        current?.stop()
        current = sound
        sound.play()
    }

    static func sound(for choice: String) -> NSSound? {
        if choice.hasPrefix("system:") { return NSSound(named: NSSound.Name(String(choice.dropFirst(7)))) }
        if choice.hasPrefix("file:") {
            let path = String(choice.dropFirst(5))
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return NSSound(contentsOfFile: path, byReference: true)
        }
        return nil
    }

    /// 시스템 소리 이름 목록
    static func systemSounds() -> [String] {
        let folders = ["/System/Library/Sounds", NSHomeDirectory() + "/Library/Sounds"]
        var names = Set<String>()
        for f in folders {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: f)) ?? [] {
                let url = URL(fileURLWithPath: file)
                if ["aiff", "aif", "wav", "caf", "mp3", "m4a"].contains(url.pathExtension.lowercased()) {
                    names.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return names.sorted()
    }

    static func label(for choice: String) -> String {
        if choice.isEmpty { return T("무음", "None") }
        if choice.hasPrefix("system:") { return String(choice.dropFirst(7)) }
        if choice.hasPrefix("file:") { return URL(fileURLWithPath: String(choice.dropFirst(5))).lastPathComponent }
        return choice
    }
}

/// 알림 소리 (M-J-007 중 이 모듈 묶음의 알림): 종류별로 시스템 소리·내 파일·무음을 고른다.
/// 탭은 없고 설정 화면만 있다. 권한·백그라운드 작업이 없다.
final class NoticeSoundsModule: NotchModule {
    static let moduleID = "noticesounds"
    let id = NoticeSoundsModule.moduleID
    var title: String { T("알림 소리", "Notice Sounds") }
    let symbol = "speaker.wave.2"
    var enabledByDefault: Bool { true }

    func start(context: ModuleContext) {}
    func stop() { }

    func settingsView() -> AnyView? { AnyView(NoticeSoundsSettings()) }

    func selfTest() -> [String] {
        let names = CPSounds.systemSounds()
        var lines = ["system sounds \(names.count): \(names.prefix(6).joined(separator: ", "))"]
        for e in CPSoundEvent.allCases {
            let c = CPSounds.choice(for: e)
            lines.append("\(e.rawValue): \(c.isEmpty ? "none" : c) loadable=\(c.isEmpty ? true : CPSounds.sound(for: c) != nil)")
        }
        return lines
    }
}

private struct NoticeSoundsSettings: View {
    @State private var choices: [String: String] = [:]
    private let names = CPSounds.systemSounds()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("캡처·개인정보·청소·회의 알림에 붙는 소리. 미리 듣기는 고를 때 바로 재생된다.",
                   "Sounds for capture, privacy, cleaning and meeting notices. Picking one plays a preview."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(CPSoundEvent.allCases) { e in
                HStack {
                    Text(e.title)
                    Spacer()
                    Menu(CPSounds.label(for: choices[e.rawValue] ?? CPSounds.choice(for: e))) {
                        Button(T("무음", "None")) { set("", e) }
                        Divider()
                        ForEach(names, id: \.self) { n in Button(n) { set("system:" + n, e) } }
                        Divider()
                        Button(T("내 파일…", "Choose File…")) {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.audio]
                            if panel.runModal() == .OK, let url = panel.url { set("file:" + url.path, e) }
                        }
                    }
                    .frame(width: 160)
                    Button { CPSounds.preview(choices[e.rawValue] ?? CPSounds.choice(for: e)) } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(T("미리 듣기", "Preview"))
                    .accessibilityLabel(T("미리 듣기", "Preview"))
                }
            }
        }
        .onAppear {
            for e in CPSoundEvent.allCases { choices[e.rawValue] = CPSounds.choice(for: e) }
        }
    }

    private func set(_ value: String, _ e: CPSoundEvent) {
        choices[e.rawValue] = value
        CPSounds.setChoice(value, for: e)
        CPSounds.preview(value)
    }
}
