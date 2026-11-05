import AppKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import EventKit
import Intents
import ScreenCaptureKit
import Speech

/// `--access-check`: 이 빌드가 이미 허용된 권한으로 실제 자원에 닿는지 확인한다.
/// 실행 보호(hardened runtime)에서는 허가(entitlement)가 빠진 자원이 상태 값은 '허용됨'인 채로 막힌다.
/// 그래서 상태만 읽는 `--module-selftest=permissions`와 달리 마이크 소리·카메라 화면·위치·일정 목록 등을 한 번 받아 본다.
/// 허용되지 않은 권한은 건드리지 않아 허용 창이 뜨지 않는다. 받은 내용(소리, 화면, 좌표, 일정 제목, 파일 이름)은
/// 출력하지 않고 받았는지와 개수만 쓴다. 마이크·카메라는 1–4초 켜지므로 표시등이 잠깐 켜진다.
/// `--access-check=location,calendar`처럼 이름을 주면 그 항목(과 서명 정보)만 본다.
enum AccessCheck {
    static let checks: [(name: String, run: () -> String)] = [
        ("microphone", microphone), ("camera", camera), ("location", location),
        ("calendar", { calendars(.event) }), ("reminders", { calendars(.reminder) }), ("appleevents", appleEvents),
        ("bluetooth", bluetooth), ("screen", screenRecording), ("accessibility", accessibility),
        ("input", inputMonitoring), ("speech", speech), ("focus", focus), ("files", files), ("systemaudio", systemAudio),
    ]

    static func run(only names: Set<String>? = nil) -> [String] {
        [signing()] + checks.filter { names?.contains($0.name) ?? true }.map { $0.run() }
    }

    /// 조건이 맞거나 시간이 다 될 때까지 주 스레드의 런루프를 돌린다 (콜백·주 큐 작업이 그동안 처리된다)
    private static func wait(_ seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// 이 프로세스의 서명: 애드혹/인증서, 실행 보호, 허가 목록, 지정 요구사항
    private static func signing() -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "FAIL signing: cannot read this process's signature" }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adhoc = flags & 0x2 != 0          // kSecCodeSignatureAdhoc
        let runtime = flags & 0x10000 != 0    // kSecCodeSignatureRuntime
        let entitlements = (dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any])?.keys.sorted() ?? []
        var requirement = "none"
        if let r = dict[kSecCodeInfoDesignatedRequirement as String] {
            var text: CFString?
            if SecRequirementCopyString(r as! SecRequirement, [], &text) == errSecSuccess, let text { requirement = text as String }
        }
        return "INFO signing: \(adhoc ? "ad hoc" : "certificate"), hardened runtime \(runtime ? "on" : "off"), "
            + "entitlements [\(entitlements.joined(separator: ", "))], designated => \(requirement)"
    }

    private static func microphone() -> String {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return "SKIP microphone (not granted)" }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return "FAIL microphone: no input format" }
        let lock = NSLock()
        var buffers = 0
        var peak: Float = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            var m: Float = 0
            for i in 0..<Int(buffer.frameLength) { m = max(m, abs(samples[i])) }
            lock.lock(); buffers += 1; peak = max(peak, m); lock.unlock()
        }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return "FAIL microphone: input did not start (\((error as NSError).code))"
        }
        wait(2) { lock.lock(); defer { lock.unlock() }; return buffers >= 10 }
        engine.stop()
        input.removeTap(onBus: 0)
        lock.lock(); let (n, p) = (buffers, peak); lock.unlock()
        // 마이크 접근이 막히면 macOS는 오류 대신 무음(0)을 준다. 조용한 방에서도 실제 마이크 신호는 0이 아니다.
        if n == 0 { return "FAIL microphone: no audio in 2 s" }
        return p > 0 ? "PASS microphone: \(n) buffers with signal" : "FAIL microphone: \(n) buffers, all silence (blocked)"
    }

    private final class FrameCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            lock.lock(); n += 1; lock.unlock()
        }
    }

    private static func camera() -> String {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return "SKIP camera (not granted)" }
        guard let device = AVCaptureDevice.default(for: .video) else { return "SKIP camera (no camera)" }
        let session = AVCaptureSession()
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            return "FAIL camera: cannot open the camera"
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        let counter = FrameCounter()
        output.setSampleBufferDelegate(counter, queue: DispatchQueue(label: "access-check.camera"))
        guard session.canAddOutput(output) else { return "FAIL camera: cannot add a frame output" }
        session.addOutput(output)
        session.startRunning()
        wait(4) { counter.count >= 3 }
        session.stopRunning()
        return counter.count > 0 ? "PASS camera: \(counter.count) frames" : "FAIL camera: no frames in 4 s"
    }

    private final class LocationProbe: NSObject, CLLocationManagerDelegate {
        var authorizationKnown = false
        var result: String?
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorizationKnown = true }
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            if result == nil, !locations.isEmpty { result = "PASS location: got a fix (coordinates not printed)" }
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            if result == nil { result = "FAIL location: error \((error as NSError).code)" }
        }
    }

    private static func location() -> String {
        // 만든 직후에는 위치 서비스의 답이 오기 전이라 '정하지 않음'으로 읽힌다. 첫 권한 알림을 기다린 뒤 본다.
        let manager = CLLocationManager()
        let probe = LocationProbe()
        manager.delegate = probe
        wait(3) { probe.authorizationKnown }
        guard manager.authorizationStatus == .authorizedAlways else {
            return "SKIP location (not granted: status \(manager.authorizationStatus.rawValue))"
        }
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.requestLocation()
        wait(10) { probe.result != nil }
        return probe.result ?? "FAIL location: no answer in 10 s"
    }

    private static func calendars(_ type: EKEntityType) -> String {
        let name = type == .event ? "calendar" : "reminders"
        guard EKEventStore.authorizationStatus(for: type) == .fullAccess else { return "SKIP \(name) (no full access)" }
        let store = EKEventStore()
        let lists = store.calendars(for: type)
        guard !lists.isEmpty else { return "FAIL \(name): no \(type == .event ? "calendars" : "lists") visible" }
        guard type == .event else { return "PASS reminders: \(lists.count) lists" }
        let week = store.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(7 * 86400), calendars: nil)
        return "PASS calendar: \(lists.count) calendars, \(store.events(matching: week).count) events in the next 7 days"
    }

    /// 묻지 않고(askUserIfNeeded = false) 자동화 권한을 확인한다. 실행 보호에서 Apple Events 허가가 없으면
    /// 사용자가 허용했든 아니든 -1743(거부)이 나온다. 늘 실행 중인 Finder는 아직 묻지 않았다면 -1744(물어야 함)가 정상이다.
    private static func appleEvents() -> String {
        let targets = ["com.apple.Music", "com.spotify.client", "com.apple.finder"]
        var results: [String: OSStatus] = [:]
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {   // 대상 앱과 주고받는 동안 주 스레드를 막지 않는다
            for id in targets {
                var desc = NSAppleEventDescriptor(bundleIdentifier: id).aeDesc!.pointee
                results[id] = AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success else { return "FAIL apple events: no answer in 10 s" }
        func word(_ s: OSStatus) -> String {
            switch s {
            case noErr: return "allowed"
            case -1744: return "not asked yet"
            case -1743: return "denied"
            case OSStatus(procNotFound): return "not running"
            default: return "error \(s)"
            }
        }
        let summary = targets.map { "\($0.split(separator: ".").last!)=\(word(results[$0] ?? 0))" }.joined(separator: " ")
        let allowedMedia = targets.prefix(2).filter { results[$0] == noErr }
        // 허용된 미디어 앱이 실행 중이면 재생 상태만 읽어 본다 (재생을 바꾸지 않는다)
        for id in allowedMedia {
            var error: NSDictionary?
            let script = NSAppleScript(source: "tell application id \"\(id)\" to get player state")
            if script?.executeAndReturnError(&error) == nil {
                return "FAIL apple events: \(summary); reading \(id) failed (\(error?[NSAppleScript.errorNumber] ?? "?"))"
            }
        }
        if results["com.apple.finder"] == -1743 { return "FAIL apple events: \(summary) (Finder denied: missing entitlement?)" }
        return allowedMedia.isEmpty ? "PASS apple events: \(summary) (no media app running to read)"
                                    : "PASS apple events: \(summary); read player state"
    }

    private final class BluetoothProbe: NSObject, CBCentralManagerDelegate {
        var state: CBManagerState = .unknown
        func centralManagerDidUpdateState(_ central: CBCentralManager) { state = central.state }
    }

    private static func bluetooth() -> String {
        guard CBManager.authorization == .allowedAlways else { return "SKIP bluetooth (not granted)" }
        let probe = BluetoothProbe()
        let central = CBCentralManager(delegate: probe, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        wait(3) { probe.state != .unknown && probe.state != .resetting }
        withExtendedLifetime(central) {}
        switch probe.state {
        case .poweredOn: return "PASS bluetooth: powered on"
        case .poweredOff: return "PASS bluetooth: reachable, radio off"
        case .unauthorized: return "FAIL bluetooth: unauthorized"
        default: return "FAIL bluetooth: state \(probe.state.rawValue)"
        }
    }

    private static func screenRecording() -> String {
        guard CGPreflightScreenCaptureAccess() else { return "SKIP screen recording (not granted)" }
        var result: String?
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            let line = content.map { "PASS screen recording: \($0.displays.count) displays, \($0.windows.count) windows listed" }
                ?? "FAIL screen recording: \((error as NSError?)?.code ?? -1)"
            DispatchQueue.main.async { result = line }
        }
        wait(5) { result != nil }
        return result ?? "FAIL screen recording: no answer in 5 s"
    }

    private static func accessibility() -> String {
        guard AXIsProcessTrusted() else { return "SKIP accessibility (not granted)" }
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &value)
        return err == .success ? "PASS accessibility: read the focused app" : "FAIL accessibility: AX error \(err.rawValue)"
    }

    /// 듣기 전용 이벤트 탭을 만들 수 있는지만 본다. 런루프에 붙이지 않고 바로 없애므로 키 입력을 받지 않는다.
    private static func inputMonitoring() -> String {
        guard CGPreflightListenEventAccess() else { return "SKIP input monitoring (not granted)" }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                                          userInfo: nil) else {
            return "FAIL input monitoring: cannot create a listen-only event tap"
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return "PASS input monitoring: listen-only event tap created"
    }

    /// 실제 받아쓰기는 소리가 필요해 돌리지 않는다. 소리 입력은 마이크 검사가 본다.
    private static func speech() -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return "SKIP speech (not granted)" }
        guard let recognizer = SFSpeechRecognizer() else { return "FAIL speech: no recognizer for this language" }
        return "INFO speech: authorized, recognizer \(recognizer.isAvailable ? "available" : "unavailable")"
            + "\(recognizer.supportsOnDeviceRecognition ? ", on device" : "") (recognition itself not run)"
    }

    private static func focus() -> String {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return "SKIP focus (not granted)" }
        return INFocusStatusCenter.default.focusStatus.isFocused == nil ? "FAIL focus: status unavailable" : "PASS focus: status read"
    }

    private static func files() -> String {
        guard PermissionsManager.shared.status(.files) == .granted else { return "SKIP files (not granted)" }
        let counts = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory].map { dir -> Int? in
            guard let url = FileManager.default.urls(for: dir, in: .userDomainMask).first else { return nil }
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count
        }
        guard let downloads = counts[0], let desktop = counts[1] else { return "FAIL files: cannot list Downloads or Desktop" }
        return "PASS files: Downloads \(downloads) items, Desktop \(desktop) items"
    }

    /// 이미 허용된 시스템 오디오 녹음 권한에 다시 물어, 창 없이 '허용' 답이 오는지 본다 (권한 단계만, 실제 녹음은 하지 않음)
    private static func systemAudio() -> String {
        guard PermissionsManager.shared.status(.systemAudio) == .granted else { return "SKIP system audio (not granted)" }
        var answer: Bool?
        MBAudio.requestTCC("kTCCServiceAudioCapture") { granted in DispatchQueue.main.async { answer = granted } }
        wait(5) { answer != nil }
        switch answer {
        case true?: return "PASS system audio: permission answered yes (no recording made)"
        case false?: return "FAIL system audio: permission answered no"
        case nil: return "FAIL system audio: no answer in 5 s"
        }
    }
}
