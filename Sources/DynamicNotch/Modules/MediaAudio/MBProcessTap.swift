import AudioToolbox
import CoreAudio
import Foundation
import os

/// Core Audio 프로세스 탭 + 비공개(private) 집계 장치 한 벌.
/// - 탭과 집계 장치는 모두 private이라 이 프로세스에만 보이고, 프로세스가 끝나면 coreaudiod가 함께 지운다.
/// - `invalidate()`는 IOProc 정지 → IOProc 제거 → 집계 장치 제거 → 탭 제거 순으로 모두 지운다.
/// - API 최소 버전: AudioHardwareCreateProcessTap / DestroyProcessTap = macOS 14.2 (SDK 표기).
@available(macOS 14.2, *)
final class MBTapSession {
    enum Failure: Error, CustomStringConvertible {
        case tap(OSStatus), format, aggregate(OSStatus), ioProc(OSStatus), start(OSStatus)
        var description: String {
            switch self {
            case .tap(let s): return "AudioHardwareCreateProcessTap \(s)"
            case .format: return "tap format is not 32-bit float"
            case .aggregate(let s): return "AudioHardwareCreateAggregateDevice \(s)"
            case .ioProc(let s): return "AudioDeviceCreateIOProcIDWithBlock \(s)"
            case .start(let s): return "AudioDeviceStart \(s)"
            }
        }
    }

    static var uidPrefix: String { MBTapLedger.uidPrefix }

    private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    let tapUUID: UUID
    let outputUID: String
    let processes: [AudioObjectID]
    private(set) var format = AudioStreamBasicDescription()

    /// - processes: 비면 이 앱을 뺀 시스템 전체 출력 탭
    /// - mute: 탭한 앱 소리를 원래 출력에서 빼려면 .mutedWhenTapped
    /// - outputs: 집계 장치 출력 스트림에 쓸지 (믹서 true, 스펙트럼 false)
    init(processes: [AudioObjectID], mute: CATapMuteBehavior, outputUID: String, outputs: Bool, name: String,
         queue: DispatchQueue, io: @escaping AudioDeviceIOBlock) throws {
        self.processes = processes
        self.outputUID = outputUID
        tapUUID = UUID()
        let desc: CATapDescription
        if processes.isEmpty {
            desc = CATapDescription(stereoGlobalTapButExcludeProcesses: MBAudio.ownProcessObject().map { [$0] } ?? [])
        } else {
            desc = CATapDescription(stereoMixdownOfProcesses: processes)
        }
        desc.uuid = tapUUID
        desc.name = name
        desc.isPrivate = true
        desc.muteBehavior = mute
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else { throw Failure.tap(status) }
        tapID = tap
        MBTapLedger.record(tapUUID)

        // 탭 형식 (32비트 실수만 처리)
        var addr = MBAudio.address(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var asbd = AudioStreamBasicDescription()
        status = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else {
            invalidate()
            throw Failure.format
        }
        format = asbd

        let aggUID = Self.uidPrefix + tapUUID.uuidString
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg)
        guard status == noErr, agg != kAudioObjectUnknown else { invalidate(); throw Failure.aggregate(status) }
        aggregateID = agg

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, queue, io)
        guard status == noErr, let proc else { invalidate(); throw Failure.ioProc(status) }
        procID = proc
        // 출력 기기 마이크(블루투스 헤드셋 등)를 열지 않도록 탭 스트림(마지막)만 입력으로 켠다
        let tapStreams = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(asbd.mChannelsPerFrame) : 1
        setStreamUsage(kAudioDevicePropertyScopeInput) { index, count in index >= count - tapStreams }
        if !outputs { setStreamUsage(kAudioDevicePropertyScopeOutput) { _, _ in false } }
        status = AudioDeviceStart(agg, proc)
        guard status == noErr else { invalidate(); throw Failure.start(status) }
    }

    /// IOProc별 스트림 사용 여부 (AudioHardwareIOProcStreamUsage: 포인터, 개수, 켜짐 배열)
    private func setStreamUsage(_ scope: AudioObjectPropertyScope, _ on: (Int, Int) -> Bool) {
        guard let procID else { return }
        var addr = MBAudio.address(kAudioDevicePropertyIOProcStreamUsage, scope)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(aggregateID, &addr, 0, nil, &size) == noErr, size >= 16 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &addr, 0, nil, &size, raw) == noErr else { return }
        let count = Int(raw.load(fromByteOffset: 8, as: UInt32.self))
        guard count > 0, 12 + 4 * count <= Int(size) else { return }
        for i in 0..<count { raw.storeBytes(of: UInt32(on(i, count) ? 1 : 0), toByteOffset: 12 + 4 * i, as: UInt32.self) }
        AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, size, raw)
    }

    /// 여러 번 불러도 안전
    func invalidate() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            MBTapLedger.forget(tapUUID)
        }
    }

    deinit { invalidate() }
}

/// 만든 탭 UUID 기록 (UserDefaults). 정상 종료면 비어 있고, 비정상 종료 뒤 남은 항목을 다음 실행에서 정리한다.
enum MBTapLedger {
    private static let key = "module.soundmixer.liveTaps"
    /// 집계 장치 UID 접두사 (비정상 종료 뒤 다음 실행에서 찾아 정리)
    static let uidPrefix = "com.dynamicnotch.mb."

    static var recorded: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func record(_ uuid: UUID) {
        UserDefaults.standard.set(Array(Set(recorded + [uuid.uuidString])), forKey: key)
    }

    static func forget(_ uuid: UUID) {
        UserDefaults.standard.set(recorded.filter { $0 != uuid.uuidString }, forKey: key)
    }

    /// 남은 탭·집계 장치 (읽기만)
    static func leftovers() -> (taps: [AudioObjectID], aggregates: [AudioObjectID]) {
        let wanted = Set(recorded)
        let taps = MBAudio.objectIDs(MBAudio.system, kAudioHardwarePropertyTapList).filter { tap in
            MBAudio.string(tap, kAudioTapPropertyUID).map { wanted.contains($0) } ?? false
        }
        let aggs = MBAudio.objectIDs(MBAudio.system, kAudioHardwarePropertyDevices).filter { dev in
            (AudioOutput.uid(dev) ?? "").hasPrefix(uidPrefix)
        }
        return (taps, aggs)
    }

    /// 이전 실행이 남긴 것을 지운다 (보통은 coreaudiod가 이미 지워 비어 있다)
    @available(macOS 14.2, *)
    static func sweep() -> Int {
        let (taps, aggs) = leftovers()
        for a in aggs { AudioHardwareDestroyAggregateDevice(a) }
        for t in taps { AudioHardwareDestroyProcessTap(t) }
        UserDefaults.standard.removeObject(forKey: key)
        return taps.count + aggs.count
    }
}

// MARK: - 실시간 처리 (음량·음소거·3밴드 EQ)

/// 2차 필터 계수 (RBJ Audio EQ Cookbook)
struct MBBiquad: Equatable {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    static func lowShelf(freq: Double, gainDB: Double, rate: Double) -> MBBiquad { shelf(freq, gainDB, rate, low: true) }
    static func highShelf(freq: Double, gainDB: Double, rate: Double) -> MBBiquad { shelf(freq, gainDB, rate, low: false) }

    private static func shelf(_ f: Double, _ g: Double, _ fs: Double, low: Bool) -> MBBiquad {
        guard abs(g) > 0.01, fs > 0 else { return MBBiquad() }
        let a = pow(10, g / 40), w = 2 * Double.pi * f / fs
        let cw = cos(w), sw = sin(w)
        let alpha = sw / 2 * sqrt(2.0)   // 기울기 S = 1
        let s = 2 * sqrt(a) * alpha
        let b0, b1, b2, a0, a1, a2: Double
        if low {
            b0 = a * ((a + 1) - (a - 1) * cw + s); b1 = 2 * a * ((a - 1) - (a + 1) * cw); b2 = a * ((a + 1) - (a - 1) * cw - s)
            a0 = (a + 1) + (a - 1) * cw + s; a1 = -2 * ((a - 1) + (a + 1) * cw); a2 = (a + 1) + (a - 1) * cw - s
        } else {
            b0 = a * ((a + 1) + (a - 1) * cw + s); b1 = -2 * a * ((a - 1) + (a + 1) * cw); b2 = a * ((a + 1) + (a - 1) * cw - s)
            a0 = (a + 1) - (a - 1) * cw + s; a1 = 2 * ((a - 1) - (a + 1) * cw); a2 = (a + 1) - (a - 1) * cw - s
        }
        return MBBiquad(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0), a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    static func peak(freq: Double, gainDB: Double, q: Double, rate: Double) -> MBBiquad {
        guard abs(gainDB) > 0.01, rate > 0 else { return MBBiquad() }
        let a = pow(10, gainDB / 40), w = 2 * Double.pi * freq / rate
        let alpha = sin(w) / (2 * q), cw = cos(w)
        let a0 = 1 + alpha / a
        return MBBiquad(b0: Float((1 + alpha * a) / a0), b1: Float(-2 * cw / a0), b2: Float((1 - alpha * a) / a0),
                        a1: Float(-2 * cw / a0), a2: Float((1 - alpha / a) / a0))
    }
}

/// 실시간 스레드와 메인 스레드가 나눠 쓰는 값. 실시간 쪽은 trylock만 쓰고, 실패하면 이전 값을 그대로 쓴다.
final class MBTapParams {
    struct Values {
        var gain: Float = 1
        var muted = false
        var eqOn = false
        var low = MBBiquad(), mid = MBBiquad(), high = MBBiquad()
    }

    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    private var shared = Values()

    func set(_ v: Values) {
        os_unfair_lock_lock(lock)
        shared = v
        os_unfair_lock_unlock(lock)
    }

    func tryRead(into v: inout Values) {
        guard os_unfair_lock_trylock(lock) else { return }
        v = shared
        os_unfair_lock_unlock(lock)
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
}

/// 탭 입력 → 음량·EQ → 집계 장치 출력. IOProc 블록 안에서만 쓰고 메모리를 새로 잡지 않는다.
final class MBTapProcessor {
    let params = MBTapParams()
    private var values = MBTapParams.Values()
    /// [채널 2][밴드 3][z1, z2]
    private let state = UnsafeMutablePointer<Float>.allocate(capacity: 12)
    private let nonInterleaved: Bool
    private let tapChannels: Int

    init(format: AudioStreamBasicDescription) {
        nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        tapChannels = max(1, Int(format.mChannelsPerFrame))
        state.initialize(repeating: 0, count: 12)
    }

    deinit { state.deallocate() }

    @inline(__always) private func filter(_ x: Float, _ q: MBBiquad, _ z: UnsafeMutablePointer<Float>) -> Float {
        // 전치 직접형 II
        let y = q.b0 * x + z[0]
        z[0] = q.b1 * x - q.a1 * y + z[1]
        z[1] = q.b2 * x - q.a2 * y
        return y
    }

    /// 한 표본 처리 (채널 0·1)
    @inline(__always) func process(_ x: Float, channel: Int) -> Float {
        if values.muted { return 0 }
        var y = x
        if values.eqOn {
            let base = state + (min(channel, 1) * 6)
            y = filter(y, values.low, base)
            y = filter(y, values.mid, base + 2)
            y = filter(y, values.high, base + 4)
        }
        y *= values.gain
        return min(max(y, -1), 1)
    }

    /// IOProc 본문. 탭 버퍼는 입력 목록의 맨 뒤에 있다고 본다 (하위 기기 스트림 다음에 탭).
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        params.tryRead(into: &values)
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outList = UnsafeMutableAudioBufferListPointer(output)
        // 첫 출력 스트림에만 쓰고 나머지는 0
        var wrote = false
        for out in outList {
            guard let dstRaw = out.mData else { continue }
            let outCh = max(1, Int(out.mNumberChannels))
            let outFrames = Int(out.mDataByteSize) / (4 * outCh)
            let dst = dstRaw.assumingMemoryBound(to: Float.self)
            guard !wrote else { memset(dstRaw, 0, Int(out.mDataByteSize)); continue }
            wrote = true
            let needed = nonInterleaved ? tapChannels : 1
            guard inList.count >= needed else { memset(dstRaw, 0, Int(out.mDataByteSize)); continue }
            if nonInterleaved {
                let first = inList.count - needed
                let frames = min(outFrames, Int(inList[first].mDataByteSize) / 4)
                for f in 0..<frames {
                    for c in 0..<outCh {
                        let tc = c % tapChannels
                        let src = inList[first + tc].mData?.assumingMemoryBound(to: Float.self)
                        dst[f * outCh + c] = process(src?[f] ?? 0, channel: tc)
                    }
                }
                if frames < outFrames { memset(dst + frames * outCh, 0, (outFrames - frames) * outCh * 4) }
            } else {
                let tap = inList[inList.count - 1]
                guard let srcRaw = tap.mData else { memset(dstRaw, 0, Int(out.mDataByteSize)); continue }
                let src = srcRaw.assumingMemoryBound(to: Float.self)
                let inCh = max(1, Int(tap.mNumberChannels))
                let frames = min(outFrames, Int(tap.mDataByteSize) / (4 * inCh))
                for f in 0..<frames {
                    for c in 0..<outCh {
                        let tc = c % inCh
                        dst[f * outCh + c] = process(src[f * inCh + tc], channel: tc)
                    }
                }
                if frames < outFrames { memset(dst + frames * outCh, 0, (outFrames - frames) * outCh * 4) }
            }
        }
    }
}
