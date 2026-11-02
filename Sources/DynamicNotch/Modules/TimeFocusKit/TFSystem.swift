import AppKit
import CoreAudio
import Intents
import SwiftUI

/// 시간·집중 모듈이 함께 읽는 macOS 상태: 유휴 시간, 화면 잠금·화면 보호기, 마이크 사용(통화 추정), 전체 화면, Focus.
/// 모두 권한 요청 없이 읽는다. 알 수 없는 값은 "아님"으로 본다.
enum TFSystem {
    /// 마지막 키보드·마우스 입력 뒤 흐른 초 (권한 불필요)
    static var idleSeconds: TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    /// 화면이 잠겨 있는지 (세션 사전의 잠금 표시 + 앞 앱이 로그인 창인지)
    static var isScreenLocked: Bool {
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
           let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
    }

    /// 화면 보호기가 도는 중인지
    static var isScreenSaverRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" || $0.bundleIdentifier == "com.apple.ScreenSaver.legacyScreenSaver"
        } && NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.hasPrefix("com.apple.ScreenSaver") == true
    }

    /// 기본 입력 장치(마이크)를 어떤 앱이 쓰는 중인지. 통화·회의 중으로 추정한다 (마이크 권한 불필요).
    static var isMicrophoneInUse: Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// 앞에 있는 앱이 화면 하나를 꽉 채운 창을 띄웠는지 (전체 화면 영상·발표).
    /// 창 위치·크기만 읽으므로 화면 녹화 권한이 필요 없다.
    static var isFrontAppFullScreen: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.bundleIdentifier != "com.apple.finder",
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let sizes = NSScreen.screens.map { $0.frame.size }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { continue }
            if sizes.contains(where: { abs($0.width - width) < 1 && abs($0.height - height) < 1 }) { return true }
        }
        return false
    }

    /// Focus(집중 모드)가 켜져 있는지. 이 앱이 이미 집중 모드 상태 권한을 받은 경우에만 알 수 있다 (요청하지 않음).
    static var focusState: Bool? {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return nil }
        return center.focusStatus.isFocused
    }
}

/// 키 입력 횟수만 듣는 이벤트 탭 (듣기 전용, 입력 모니터링 권한).
/// 키 내용(글자)은 읽지 않고 키 코드만 넘긴다. 구독자가 하나라도 있을 때만 탭을 켠다.
final class TFKeyTap {
    static let shared = TFKeyTap()

    /// 입력 모니터링 권한이 있는지 (확인만, 요청 창 없음)
    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// 사용자가 버튼을 눌렀을 때만 부른다. 시스템이 권한 창 또는 설정 안내를 띄운다.
    static func requestPermission() {
        _ = CGRequestListenEventAccess()
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private var handlers: [String: (Int64) -> Void] = [:]
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// 구독. 권한이 없거나 탭을 만들 수 없으면 false.
    @discardableResult
    func add(_ id: String, _ handler: @escaping (Int64) -> Void) -> Bool {
        guard Self.hasPermission else { return false }
        handlers[id] = handler
        if tap == nil { install() }
        if tap == nil { handlers[id] = nil; return false }
        return true
    }

    func remove(_ id: String) {
        handlers[id] = nil
        if handlers.isEmpty { uninstall() }
    }

    fileprivate func deliver(_ keyCode: Int64) {
        for h in handlers.values { h(keyCode) }
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func install() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<TFKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                me.reenable()
            } else if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                me.deliver(event.getIntegerValueField(.keyboardEventKeycode))
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}

/// 타이머 종료 알람. 시스템 소리를 정한 시간 동안 되풀이할 수 있다.
final class TFAlarm {
    static let shared = TFAlarm()

    /// 알람이 언제 멈출지
    enum Repeat: String, CaseIterable, Identifiable {
        case once, s10, s30, m1, untilDismissed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .once: return T("한 번", "Once")
            case .s10: return T("10초 동안", "For 10 seconds")
            case .s30: return T("30초 동안", "For 30 seconds")
            case .m1: return T("1분 동안", "For 1 minute")
            case .untilDismissed: return T("끌 때까지 (최대 5분)", "Until dismissed (max 5 min)")
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .once: return 0
            case .s10: return 10
            case .s30: return 30
            case .m1: return 60
            case .untilDismissed: return 300
            }
        }
    }

    /// /System/Library/Sounds 의 소리 이름
    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let names = files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return names.isEmpty ? ["Glass"] : names
    }()

    private var timer: Timer?
    private var sound: NSSound?
    private(set) var isRinging = false

    func ring(_ name: String, repeat mode: Repeat) {
        stop()
        guard name != "none", let s = NSSound(named: NSSound.Name(name)) else { return }
        sound = s
        s.play()
        guard mode != .once else { return }
        isRinging = true
        let until = Date().addingTimeInterval(mode.seconds)
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date() >= until { self.stop(); return }
            self.sound?.stop()
            self.sound?.play()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sound?.stop()
        isRinging = false
    }
}

/// 사용자 단축어(Shortcuts) 목록·실행. `/usr/bin/shortcuts` 를 백그라운드에서 부른다.
enum TFShortcuts {
    static let tool = "/usr/bin/shortcuts"
    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: tool) }

    /// 이름 목록. 실패하면 nil.
    static func list(_ completion: @escaping ([String]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = run(["list"], timeout: 10)
            let names = out.map { $0.0 == 0 ? $0.1.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : nil } ?? nil
            DispatchQueue.main.async { completion(names) }
        }
    }

    /// 동기 목록 (자체 검사용)
    static func listSync() -> [String]? {
        guard let out = run(["list"], timeout: 10), out.0 == 0 else { return nil }
        return out.1.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// 단축어 실행 (사용자가 누른 경우에만). 성공 여부와 오류 문구.
    static func run(_ name: String, _ completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = run(["run", name], timeout: 60)
            DispatchQueue.main.async {
                guard let out else { completion(false, T("단축어를 실행하지 못했어요", "Could not run the shortcut")); return }
                completion(out.0 == 0, out.0 == 0 ? nil : (out.2.isEmpty ? nil : out.2))
            }
        }
    }

    /// (종료 코드, 표준 출력, 표준 오류)
    private static func run(_ args: [String], timeout: TimeInterval) -> (Int32, String, String)? {
        guard isAvailable else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        var outData = Data()
        let reader = DispatchQueue(label: "tf.shortcuts.read")
        let group = DispatchGroup()
        group.enter()
        reader.async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        _ = group.wait(timeout: .now() + 2)
        let errData = err.fileHandleForReading.availableData
        return (p.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}

/// 시간·집중 모듈 사이의 알림 (같은 프로세스 안)
enum TFEvents {
    /// 포모도로 단계가 바뀜. userInfo: "phase"(String, 없으면 정지), "running"(Bool)
    static let pomodoroChanged = Notification.Name("tf.pomodoro.changed")
}

/// 앱 아이콘·이름 (번들 ID로)
enum TFApps {
    private static var iconCache: [String: NSImage] = [:]

    static func icon(_ bundleID: String) -> NSImage? {
        if let c = iconCache[bundleID] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        iconCache[bundleID] = img
        return img
    }

    static func name(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    /// 앱 고르기 창 (설정 화면에서). 고른 앱들의 번들 ID.
    static func pickApps() -> [String] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// 설정 화면의 앱 목록 편집 (추가·빼기)
struct TFAppListEditor: View {
    @ObservedObject var prefs: TFPrefs
    var key: String
    var emptyText: String

    var body: some View {
        let list = prefs.strings(key)
        VStack(alignment: .leading, spacing: 4) {
            if list.isEmpty {
                Text(emptyText).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(list, id: \.self) { id in
                HStack(spacing: 6) {
                    if let icon = TFApps.icon(id) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    Text(TFApps.name(id))
                    Spacer()
                    Button(T("빼기", "Remove")) { prefs.setStrings(list.filter { $0 != id }, key) }
                }
            }
            Button(T("앱 추가…", "Add an App…")) {
                let picked = TFApps.pickApps().filter { !list.contains($0) }
                if !picked.isEmpty { prefs.setStrings(list + picked, key) }
            }
        }
    }
}
