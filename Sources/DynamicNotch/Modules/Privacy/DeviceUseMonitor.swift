import AppKit
import CoreAudio
import CoreMediaIO
import Darwin

/// 카메라·마이크가 어느 앱에서든 쓰이는지 장치 플래그로만 본다 (카메라·마이크 권한 불필요, 영상·소리를 읽지 않음).
/// 폴링 없이 CoreMediaIO·CoreAudio 속성 변경 알림을 받는다.
final class CPDeviceUseMonitor {
    struct Snapshot: Equatable {
        var cameras: [String] = []   // 지금 쓰이는 카메라 이름
        var mics: [String] = []      // 지금 쓰이는 입력 장치 이름
        var cameraOn: Bool { !cameras.isEmpty }
        var micOn: Bool { !mics.isEmpty }
    }

    var onChange: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()
    private var cmioListeners: [(CMIOObjectID, CMIOObjectPropertyAddress, CMIOObjectPropertyListenerBlock)] = []
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        rebuild()
    }

    func stop() {
        running = false
        removeAll()
    }

    private func removeAll() {
        for (id, addr, block) in cmioListeners {
            var a = addr
            _ = CMIOObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, block)
        }
        for (id, addr, block) in audioListeners {
            var a = addr
            _ = AudioObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, block)
        }
        cmioListeners.removeAll()
        audioListeners.removeAll()
    }

    /// 장치 목록이 바뀌면 장치별 알림을 다시 건다
    private func rebuild() {
        removeAll()
        guard running else { return }
        let refresh: () -> Void = { [weak self] in self?.refresh() }
        let rebuild: () -> Void = { [weak self] in self?.rebuild() }

        // 카메라: 시스템 장치 목록 + 장치별 "어디선가 실행 중"
        var devAddr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let devBlock: CMIOObjectPropertyListenerBlock = { _, _ in rebuild() }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devAddr, DispatchQueue.main, devBlock) == 0 {
            cmioListeners.append((CMIOObjectID(kCMIOObjectSystemObject), devAddr, devBlock))
        }
        for cam in Self.cameraDevices() {
            var a = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            let b: CMIOObjectPropertyListenerBlock = { _, _ in refresh() }
            if CMIOObjectAddPropertyListenerBlock(cam, &a, DispatchQueue.main, b) == 0 { cmioListeners.append((cam, a, b)) }
        }

        // 마이크: 시스템 장치 목록 + 입력 장치별 "어디선가 실행 중"
        var audAddr = Self.audioAddress(kAudioHardwarePropertyDevices)
        let audBlock: AudioObjectPropertyListenerBlock = { _, _ in rebuild() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &audAddr, DispatchQueue.main, audBlock) == noErr {
            audioListeners.append((AudioObjectID(kAudioObjectSystemObject), audAddr, audBlock))
        }
        for dev in Self.inputDevices() {
            var a = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            let b: AudioObjectPropertyListenerBlock = { _, _ in refresh() }
            if AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main, b) == noErr { audioListeners.append((dev, a, b)) }
        }
        refresh()
    }

    private func refresh() {
        let s = Self.current()
        guard s != snapshot else { return }
        snapshot = s
        onChange?(s)
    }

    // MARK: 읽기 (권한 프롬프트 없음)

    static func current() -> Snapshot {
        Snapshot(cameras: cameraDevices().filter { cmioUInt32($0, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) == 1 }.map { cmioName($0) },
                 mics: inputDevices().filter { audioUInt32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 }.map { audioName($0) })
    }

    static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func audioAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func cameraDevices() -> [CMIOObjectID] {
        var addr = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return ids
    }

    static func cmioUInt32(_ id: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> UInt32? {
        var addr = cmioAddress(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == 0 else { return nil }
        return value
    }

    static func cmioName(_ id: CMIOObjectID) -> String {
        var addr = cmioAddress(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
        var name: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, size, &used, &name) == 0, let n = name else { return T("카메라", "Camera") }
        return n.takeRetainedValue() as String
    }

    static func audioDevices() -> [AudioObjectID] {
        var addr = audioAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// 입력 스트림이 있는 장치만
    static func inputDevices() -> [AudioObjectID] {
        audioDevices().filter { dev in
            var addr = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr && size > 0
        }
    }

    static func audioUInt32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = audioAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func audioName(_ id: AudioObjectID) -> String {
        var addr = audioAddress(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let n = name else { return T("마이크", "Microphone") }
        return n.takeRetainedValue() as String
    }

    // MARK: 어느 앱인지 (최선 추정)

    /// 지금 입력(마이크)을 쓰는 프로세스 (macOS 14.2 이상 CoreAudio 프로세스 객체). 더 낮으면 빈 목록.
    static func audioInputPIDs() -> [pid_t] {
        guard #available(macOS 14.2, *) else { return [] }
        var addr = audioAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { obj in
            guard audioUInt32(obj, kAudioProcessPropertyIsRunningInput) == 1 else { return nil }
            var a = audioAddress(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var s = UInt32(MemoryLayout<pid_t>.size)
            return AudioObjectGetPropertyData(obj, &a, 0, nil, &s, &pid) == noErr ? pid : nil
        }
    }

    /// 도우미 프로세스면 실행 파일 경로의 가장 바깥 .app을 찾아 그 앱으로 바꾼다
    static func owningApp(_ pid: pid_t) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return NSRunningApplication(processIdentifier: pid) }
        let path = String(cString: buf)
        guard let r = path.range(of: ".app/") else { return NSRunningApplication(processIdentifier: pid) }
        let outer = String(path[..<r.lowerBound]) + ".app"
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == outer } ?? NSRunningApplication(processIdentifier: pid)
    }
}

/// 화면 잠금과 디스플레이 끄기
enum CPScreenLock {
    private typealias LockFn = @convention(c) () -> Int32
    private static let sacLock: LockFn? = {
        let paths = ["/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
                     "/System/Library/PrivateFrameworks/login.framework/login"]
        return CPPrivate.symbol("SACLockScreenImmediate", in: paths).map { unsafeBitCast($0, to: LockFn.self) }
    }()

    static var privateLockAvailable: Bool { sacLock != nil }

    /// 바로 잠근다. 비공개 함수가 없으면 손쉬운 사용 권한으로 ⌃⌘Q를 보낸다. 둘 다 안 되면 이유를 돌려준다.
    static func lockNow() -> String? {
        if let f = sacLock {
            _ = f()
            return nil
        }
        if AXIsProcessTrusted() {
            let q: CGKeyCode = 12
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: q, keyDown: down)
                e?.flags = [.maskCommand, .maskControl]
                e?.post(tap: .cghidEventTap)
            }
            return nil
        }
        return T("잠금 함수를 찾지 못했고 손쉬운 사용 권한이 없어 ⌃⌘Q도 보낼 수 없음. 직접 ⌃⌘Q를 눌러 줘.",
                 "The lock function is missing and Accessibility is off, so ⌃⌘Q cannot be sent. Press ⌃⌘Q yourself.")
    }

    /// 디스플레이만 끈다 (잠금이 아님: '잠자기 후 바로 암호 요구'가 켜져 있어야 잠긴다)
    static func sleepDisplays() {
        CPProcess.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}
