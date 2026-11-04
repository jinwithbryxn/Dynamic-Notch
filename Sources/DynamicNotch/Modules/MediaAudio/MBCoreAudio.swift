import AppKit
import SwiftUI
import CoreAudio
import AudioToolbox

/// 음악·오디오 모듈이 함께 쓰는 CoreAudio 도우미 (공개 속성 API만).
/// 출력 기기 이름·UID·아이콘은 기존 `AudioOutput`을 그대로 쓴다.
enum MBAudio {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
        var addr = address(selector, scope, element)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        guard AudioObjectHasProperty(object, &addr) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func isSettable(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var addr = address(selector, scope, element)
        guard AudioObjectHasProperty(object, &addr) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(object, &addr, &settable) == noErr && settable.boolValue
    }

    // MARK: 기기

    static func hasStreams(_ device: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    /// 기본 입력으로 고를 수 있는 기기 (집계·숨김 기기 제외)
    static func inputDevices() -> [AudioDeviceID] {
        objectIDs(system, kAudioHardwarePropertyDevices).filter { id in
            guard hasStreams(id, kAudioDevicePropertyScopeInput) else { return false }
            if let canDefault = uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeInput), canDefault == 0 {
                return false
            }
            if let hidden = uint32(id, kAudioDevicePropertyIsHidden), hidden != 0 { return false }
            return true
        }
    }

    static func defaultInput() -> AudioDeviceID {
        uint32(system, kAudioHardwarePropertyDefaultInputDevice).map { AudioDeviceID($0) } ?? 0
    }

    static func defaultOutput() -> AudioDeviceID { AudioOutput.defaultDevice() }

    @discardableResult
    static func setDefaultInput(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = device
        return AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr
    }

    static func device(uid: String) -> AudioDeviceID? {
        objectIDs(system, kAudioHardwarePropertyDevices).first { AudioOutput.uid($0) == uid }
    }

    static func name(_ device: AudioDeviceID) -> String { AudioOutput.displayName(device) }

    /// 입력 기기 아이콘
    static func inputSymbol(_ device: AudioDeviceID) -> String {
        let lowered = (AudioOutput.name(device) ?? "").lowercased()
        switch AudioOutput.transport(device) {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return lowered.contains("airpods") ? "airpods" : "headphones"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: return "mic"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "iphone"
        default: return lowered.contains("iphone") ? "iphone" : "mic"
        }
    }

    // MARK: 입력 음소거·음량

    static func inputMuteSettable(_ device: AudioDeviceID) -> Bool {
        isSettable(device, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
    }

    static func inputMuted(_ device: AudioDeviceID) -> Bool? {
        uint32(device, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput).map { $0 != 0 }
    }

    @discardableResult
    static func setInputMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        var v = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    /// 입력 음량을 다룰 수 있는 속성: 기기 전체 가상 음량 → 주 요소 스칼라 순
    private static func inputVolumeAddress(_ device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var addr = address(selector, kAudioDevicePropertyScopeInput)
            if AudioObjectHasProperty(device, &addr) { return addr }
        }
        return nil
    }

    static func inputVolume(_ device: AudioDeviceID) -> Float? {
        guard var addr = inputVolumeAddress(device) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func inputVolumeSettable(_ device: AudioDeviceID) -> Bool {
        guard var addr = inputVolumeAddress(device) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    @discardableResult
    static func setInputVolume(_ device: AudioDeviceID, _ value: Float) -> Bool {
        guard var addr = inputVolumeAddress(device) else { return false }
        var v = Float32(min(max(value, 0), 1))
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    // MARK: 오디오를 쓰는 프로세스 (macOS 14.2+의 프로세스 객체, 읽기 전용·권한 불필요)

    struct Process: Equatable {
        let object: AudioObjectID
        let pid: pid_t
        let bundleID: String
        let runningOutput: Bool
        let runningInput: Bool
    }

    static func processes() -> [Process] {
        objectIDs(system, kAudioHardwarePropertyProcessObjectList).map { obj in
            Process(object: obj,
                    pid: pid_t(bitPattern: uint32(obj, kAudioProcessPropertyPID) ?? 0),
                    bundleID: string(obj, kAudioProcessPropertyBundleID) ?? "",
                    runningOutput: (uint32(obj, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
                    runningInput: (uint32(obj, kAudioProcessPropertyIsRunningInput) ?? 0) != 0)
        }
    }

    /// 이 앱 자신의 프로세스 객체 (전체 탭에서 뺄 때)
    static func ownProcessObject() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var obj = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
        return status == noErr && obj != 0 ? obj : nil
    }

    // MARK: 시스템 오디오 녹음 권한 (Core Audio 탭)

    enum CapturePermission: String { case authorized, denied, unknown, unavailable }

    /// 비공개 TCC.framework의 TCCAccessPreflight로 묻지 않고 상태만 읽는다 (0 허용, 1 거부, 그 밖 미정).
    /// 함수가 없으면 unavailable.
    static func capturePermission() -> CapturePermission {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        guard let lib = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let sym = dlsym(lib, "TCCAccessPreflight") else { return .unavailable }
        switch unsafeBitCast(sym, to: Preflight.self)("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    private static let tccRequest: UnsafeMutableRawPointer? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW) else { return nil }
        return dlsym(lib, "TCCAccessRequest")
    }()

    /// 시스템 오디오 녹음 허용 창을 띄울 수 있는지 (TCCAccessRequest가 있는지)
    static var canRequestCapturePermission: Bool { tccRequest != nil }

    /// 비공개 TCC.framework의 TCCAccessRequest로 시스템 오디오 녹음 허용 창을 띄운다.
    /// 이 요청이 있어야 시스템 설정의 '시스템 오디오 녹음만' 목록에 앱이 올라온다.
    /// 위쪽 '화면 및 시스템 오디오 녹음' 목록을 켜도 이 권한(kTCCServiceAudioCapture)은 미정으로 남는다 (2026-11-04 확인).
    /// 함수가 없으면 false를 돌려주고 completion은 부르지 않는다.
    @discardableResult
    static func requestCapturePermission(_ completion: @escaping (Bool) -> Void) -> Bool {
        requestTCC("kTCCServiceAudioCapture", completion)
    }

    /// TCCAccessRequest 호출. 이미 정해진 권한이면 창 없이 바로 답한다 (자체 검사가 허용된 권한으로 호출 경로를 확인할 때 쓴다).
    @discardableResult
    static func requestTCC(_ service: String, _ completion: @escaping (Bool) -> Void) -> Bool {
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let sym = tccRequest else { return false }
        unsafeBitCast(sym, to: Request.self)(service as CFString, nil) { completion($0) }
        return true
    }

    /// 탭을 쓰려면 Info.plist에 시스템 오디오 녹음 설명이 있어야 한다 (없으면 시도하지 않음)
    static var hasCaptureUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil
    }

    static var hasMicrophoneUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    static var osVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 명령줄 검사·화면 그리기 모드: 권한 창이나 Apple 이벤트가 생길 수 있는 일은 하지 않는다
    static let isDevTool: Bool = CommandLine.arguments.contains {
        $0.hasPrefix("--render-tab") || $0.hasPrefix("--module-selftest") || $0 == "--list-modules"
    }

    /// 시스템 설정의 개인정보 화면 열기 (사용자가 버튼을 눌렀을 때)
    static func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// CoreAudio 속성 감시 묶음. `removeAll()`로 붙인 감시를 모두 뗀다.
final class MBPropertyWatch {
    private var entries: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             _ handler: @escaping () -> Void) {
        var addr = MBAudio.address(selector, scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(object, &addr, .main, block) == noErr {
            entries.append((object, addr, block))
        }
    }

    func removeAll() {
        for (object, addr, block) in entries {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(object, &a, .main, block)
        }
        entries.removeAll()
    }

    deinit { removeAll() }
}

/// 노치 탭 공용 모양: 작은 캡슐 버튼
struct MBPillButton: View {
    var title: String
    var symbol: String? = nil
    var active = false
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                if !title.isEmpty { Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? tint.opacity(0.85) : Color.white.opacity(0.1)))
            .foregroundStyle(active ? Color.black : Color.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.isEmpty ? (symbol ?? "") : title)
    }
}

/// "지원 안 됨 + 이유 + 대안" 상자
struct MBUnsupportedBox: View {
    var title: String
    var reason: String
    var alternative: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(reason).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            if let alternative {
                Text(alternative).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
