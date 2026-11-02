import AppKit
import CoreAudio
import CoreMediaIO
import Darwin

/// 카메라·마이크가 어느 앱에서든 쓰이는지 장치 플래그로만 본다 (카메라·마이크 권한 불필요, 영상·소리를 읽지 않음).
/// 폴링 없이 CoreMediaIO·CoreAudio 속성 변경 알림을 받는다.
///
/// 장치 목록 알림은 시작할 때 한 번만 건다. 예전처럼 목록 알림 안에서 알림을 모두 떼고 다시 걸면
/// 카메라 장치가 새로 나타날 때 목록 알림이 끝없이 이어져 메인 스레드가 멈춘 적이 있다 (2026-11-02, CPU 96–99%).
/// 그래서 목록이 바뀌면 잠시 모아서 한 번만 맞추고, 새로 생긴 장치에만 걸고 빠진 장치에서만 뗀다.
final class CPDeviceUseMonitor {
    struct Snapshot: Equatable {
        var cameras: [String] = []   // 지금 쓰이는 카메라 이름
        var mics: [String] = []      // 지금 쓰이는 입력 장치 이름
        var cameraOn: Bool { !cameras.isEmpty }
        var micOn: Bool { !mics.isEmpty }
    }

    /// 목록 알림을 모으는 시간
    static let syncDelay: TimeInterval = 0.5
    /// 이 시간 안에 맞추기가 이만큼 일어나면 한동안 쉰다 (알림이 그치지 않을 때 CPU를 지키는 안전장치)
    static let burstWindow: TimeInterval = 10
    static let burstLimit = 20
    static let burstPause: TimeInterval = 30

    var onChange: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()
    private var cameraListListener: CMIOObjectPropertyListenerBlock?
    private var micListListener: AudioObjectPropertyListenerBlock?
    private var cameraListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var micListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var running = false
    private var syncWork: DispatchWorkItem?
    private var recentSyncs: [Date] = []

    /// 자체 검사용 셈
    private(set) var syncCount = 0
    private(set) var listenerAdds = 0
    private(set) var listenerRemoves = 0
    var deviceListenerCount: Int { cameraListeners.count + micListeners.count }

    func start() {
        guard !running else { return }
        running = true
        var cameraList = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let cameraBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceListChanged() }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, DispatchQueue.main, cameraBlock) == 0 {
            cameraListListener = cameraBlock
        }
        var micList = Self.audioAddress(kAudioHardwarePropertyDevices)
        let micBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceListChanged() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &micList, DispatchQueue.main, micBlock) == noErr {
            micListListener = micBlock
        }
        sync()
    }

    func stop() {
        running = false
        syncWork?.cancel()
        syncWork = nil
        recentSyncs.removeAll()
        if let block = cameraListListener {
            var a = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            _ = CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &a, DispatchQueue.main, block)
        }
        if let block = micListListener {
            var a = Self.audioAddress(kAudioHardwarePropertyDevices)
            _ = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, block)
        }
        cameraListListener = nil
        micListListener = nil
        for id in Array(cameraListeners.keys) { removeCamera(id) }
        for id in Array(micListeners.keys) { removeMic(id) }
    }

    /// 장치 목록이 바뀌었다는 알림. 몰려와도 syncDelay 뒤 한 번만 맞춘다.
    func deviceListChanged() {
        guard running, syncWork == nil else { return }
        let now = Date()
        recentSyncs.removeAll { now.timeIntervalSince($0) > Self.burstWindow }
        let delay = recentSyncs.count >= Self.burstLimit ? Self.burstPause : Self.syncDelay
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncWork = nil
            self.sync()
        }
        syncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 새로 생긴 장치에만 "어디선가 실행 중" 알림을 걸고, 빠진 장치에서만 뗀다
    private func sync() {
        guard running else { return }
        syncCount += 1
        recentSyncs.append(Date())
        let cameras = Set(Self.cameraDevices())
        for id in Array(cameraListeners.keys) where !cameras.contains(id) { removeCamera(id) }
        for id in cameras where cameraListeners[id] == nil {
            var a = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            let b: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            if CMIOObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, b) == 0 {
                cameraListeners[id] = b
                listenerAdds += 1
            }
        }
        let mics = Set(Self.inputDevices())
        for id in Array(micListeners.keys) where !mics.contains(id) { removeMic(id) }
        for id in mics where micListeners[id] == nil {
            var a = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
            if AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main, b) == noErr {
                micListeners[id] = b
                listenerAdds += 1
            }
        }
        refresh()
    }

    private func removeCamera(_ id: CMIOObjectID) {
        guard let block = cameraListeners.removeValue(forKey: id) else { return }
        var a = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        _ = CMIOObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, block)
        listenerRemoves += 1
    }

    private func removeMic(_ id: AudioObjectID) {
        guard let block = micListeners.removeValue(forKey: id) else { return }
        var a = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        _ = AudioObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, block)
        listenerRemoves += 1
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
