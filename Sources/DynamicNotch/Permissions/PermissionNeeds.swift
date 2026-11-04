import Foundation

/// 켜 둔 기능이 꼭 필요로 하는 권한.
/// 기능의 주된 동작에 필요한 것만 적는다. 있으면 더 되는 것(예: 집중 모드 이름 표시의 전체 디스크 접근)과
/// 대상 앱마다 따로 묻는 자동화(메모, 브라우저)는 적지 않고, 그 기능을 처음 쓸 때 시스템이 묻게 둔다.
/// 새 기능이 권한을 쓰면 `modules`에 한 줄 더한다.
enum PermissionNeeds {
    static let modules: [String: [PermissionKind]] = [
        "notifymirror": [.accessibility],
        "lockcards": [.calendar, .focus],
        "soundmixer": [.systemAudio],
        "spectrum": [.systemAudio],
        "musictools": [.automation],
        "miniplayer": [.automation],
        "btbattery": [.bluetooth],
        "clipboard": [.accessibility],
        "snippets": [.accessibility],
        "windowsnap": [.accessibility],
        "nlcommands": [.calendar, .reminders],
        "videosaver": [.files],
        "inputtriggers": [.accessibility],
        "textactions": [.accessibility],
        "dictation": [.speech, .microphone, .accessibility],
        "spaces": [.accessibility],
        "calendar": [.calendar],
        "reminders": [.reminders],
        "breaks": [.focus],
        "focusswitch": [.focus],
        "typingsounds": [.inputMonitoring],
        "devices": [.location],
        "capture": [.screenRecording],
        "presenter": [.inputMonitoring, .accessibility],
        "cleaning": [.accessibility],
        "windowwatch": [.screenRecording],
        "meeting": [.accessibility],
        "menubar": [.accessibility],
    ]

    /// 기본 기능(확장 기능이 아닌 것) 중 켜져 있는 것과 그 권한
    static func core(_ s: AppSettings = .shared) -> [(name: String, kinds: [PermissionKind])] {
        var out: [(String, [PermissionKind])] = []
        if s.hudVolume || s.hudDisplay || s.hudKeyboard {
            out.append((T("음량·밝기 표시(HUD)", "Volume & brightness HUD"), [.accessibility, .inputMonitoring]))
        }
        if s.callEnabled { out.append((T("전화", "Phone calls"), [.accessibility])) }
        if s.recordingEnabled { out.append((T("화면 녹화 표시", "Screen recording indicator"), [.accessibility])) }
        if s.focusEnabled { out.append((T("방해금지 모드", "Focus"), [.focus])) }
        if s.btEnabled { out.append((T("블루투스 연결 알림", "Bluetooth alerts"), [.bluetooth])) }
        if s.netWifiConnection || s.netHotspot { out.append((T("Wi-Fi 알림", "Wi-Fi alerts"), [.location])) }
        if s.lyricsEnabled { out.append((T("전체 화면 가사", "Full-screen lyrics"), [.automation])) }
        if s.downloadEnabled { out.append((T("다운로드", "Downloads"), [.files])) }
        if s.screenshotEnabled && s.screenshotSource != .clipboard {
            out.append((T("스크린샷", "Screenshots"), [.files]))
        }
        if s.isHomeFeatureOn("camera") && s.cameraMirror { out.append((T("노치 카메라", "Notch camera"), [.camera])) }
        if s.isHomeFeatureOn("calendar") { out.append((T("홈 일정", "Home events"), [.calendar])) }
        return out
    }

    /// 권한별로 그 권한을 꼭 필요로 하는 켜진 기능 이름. 어떤 켜진 기능도 쓰지 않는 권한은 빠진다.
    static func users(registry: ModuleRegistry = .shared, settings: AppSettings = .shared) -> [PermissionKind: [String]] {
        var out: [PermissionKind: [String]] = [:]
        for (name, kinds) in core(settings) {
            for k in kinds { out[k, default: []].append(name) }
        }
        for m in registry.modules where registry.isEnabled(m) {
            for k in modules[m.id] ?? [] { out[k, default: []].append(m.title) }
        }
        return out
    }

    /// `--module-selftest=permissions`: 대응표가 실제 기능 목록과 맞는지
    static func selfTest() -> [String] {
        var lines: [String] = []
        let ids = Set(ModuleCatalog.makeAll().map(\.id))
        let unknown = modules.keys.filter { !ids.contains($0) }.sorted()
        lines.append(unknown.isEmpty ? "PASS every mapped id is a real module (\(modules.count))"
                                     : "FAIL unknown module ids: \(unknown.joined(separator: ", "))")
        let noURL = PermissionKind.allCases.filter { $0.settingsURL == nil }
        lines.append(noURL.isEmpty ? "PASS every permission has a System Settings link"
                                   : "FAIL no settings link: \(noURL.map(\.rawValue).joined(separator: ", "))")
        let cases: [(PermissionKind, PermissionStatus, PermissionStatus, Bool)] = [
            (.microphone, .notDetermined, .granted, true),
            (.microphone, .notDetermined, .denied, true),
            (.microphone, .denied, .denied, false),           // 이미 거부 → 설정에서 켤 때까지
            (.microphone, .notDetermined, .notDetermined, false),
            (.accessibility, .notDetermined, .notDetermined, false),
            (.accessibility, .notDetermined, .granted, true),
            (.fullDisk, .notDetermined, .denied, false),       // 설정에서 켜는 권한 → 켜질 때까지
            (.systemAudio, .notDetermined, .denied, MBAudio.canRequestCapturePermission),
            (.automation, .unknown, .needsAppRunning, true),
        ]
        let wrong = cases.filter { PermissionsManager.isAnswered($0.0, from: $0.1, now: $0.2) != $0.3 }
        lines.append(wrong.isEmpty ? "PASS walkthrough moves on only when answered (\(cases.count) cases)"
                                   : "FAIL walkthrough answer rule: \(wrong.map { "\($0.0.rawValue) \($0.1)->\($0.2)" })")
        lines.append(Self.tccRequestCheck())
        let users = Self.users()
        let neededNow = PermissionKind.allCases.filter { users[$0] != nil }.map(\.rawValue)
        lines.append("needed by what is on now: \(neededNow.joined(separator: ", "))")
        let statuses = PermissionKind.allCases.map { "\($0.rawValue)=\(PermissionsManager.shared.status($0))" }
        lines.append("status (read only): \(statuses.joined(separator: " "))")
        return lines
    }

    /// 시스템 오디오 녹음 허용 창을 띄우는 TCCAccessRequest가 있는지, 부르는 방식이 맞는지 본다.
    /// 창을 띄우지 않도록 이미 허용된 마이크 권한으로만 불러, 바로 '허용됨' 답이 오는지 확인한다.
    private static func tccRequestCheck() -> String {
        guard MBAudio.canRequestCapturePermission else {
            return "WARN TCCAccessRequest missing: system audio recording falls back to System Settings"
        }
        guard PermissionsManager.shared.status(.microphone) == .granted else {
            return "PASS TCCAccessRequest found (call not tried: microphone is not granted, so it could show a prompt)"
        }
        var answer: Bool?
        MBAudio.requestTCC("kTCCServiceMicrophone") { granted in DispatchQueue.main.async { answer = granted } }
        let deadline = Date().addingTimeInterval(5)
        while answer == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        switch answer {
        case true?: return "PASS TCCAccessRequest call works (already granted microphone answered yes without a prompt)"
        case false?: return "FAIL TCCAccessRequest answered no for the granted microphone"
        case nil: return "FAIL TCCAccessRequest did not answer within 5 s"
        }
    }
}
