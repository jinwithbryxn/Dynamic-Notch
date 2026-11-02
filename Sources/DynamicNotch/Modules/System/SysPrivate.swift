import Foundation
import IOKit

// 비공개 API 어댑터 (읽기 전용). 심볼은 실행 중에 dlsym으로 찾고, 없으면 지원 안 됨으로 떨어진다.
//   - SysTemperature: IOHIDEventSystemClient (IOKit 비공개 심볼) → Apple silicon 온도 센서
//   - SysSMC: AppleSMC 사용자 클라이언트 읽기 (팬 수·회전수, 충전 제어 키 존재 여부). 쓰기 함수는 없다.

/// Apple silicon 온도 센서 (IOHID). Intel·센서 없는 Mac에서는 nil.
final class SysTemperature {
    static let shared = SysTemperature()

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?
    private var services: [(name: String, ref: AnyObject)] = []
    private var client: AnyObject?
    private let lock = NSLock()
    /// 지원 안 될 때 이유
    private(set) var unsupportedReason: String?

    private static let kTemperatureEvent: Int64 = 15
    private static var kTemperatureField: Int32 { Int32(kTemperatureEvent << 16) }

    private init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? { h.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: type) } }
        let create = sym("IOHIDEventSystemClientCreate", CreateFn.self)
        let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)
        let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)
        let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
        getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)
        guard let create, let setMatching, let copyServices, let copyProperty, copyEvent != nil, getFloat != nil else {
            unsupportedReason = T("이 macOS에 온도 센서 API가 없음", "Sensor API is missing on this macOS")
            return
        }
        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            unsupportedReason = T("센서 클라이언트를 만들 수 없음", "Could not create the sensor client")
            return
        }
        // Apple 벤더 페이지(0xff00)의 온도 센서(5)
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let list = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        for s in list {
            let name = copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            services.append((name, s))
        }
        if cpuSensors.isEmpty {
            unsupportedReason = T("CPU 온도 센서를 보고하지 않는 Mac", "This Mac reports no CPU temperature sensor")
        }
        self.client = client
    }

    /// CPU 다이 센서 ("PMU tdie*", 일부 기종 "pACC/eACC MTR")
    private var cpuSensors: [AnyObject] {
        services.filter { $0.name.hasPrefix("PMU tdie") || $0.name.contains("ACC MTR") }.map(\.ref)
    }

    /// 가장 뜨거운 CPU 센서 값 (°C)
    func hottestCPU() -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let copyEvent, let getFloat else { return nil }
        var best: Double?
        for s in cpuSensors {
            guard let e = copyEvent(s, Self.kTemperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let v = getFloat(e, Self.kTemperatureField)
            if v > 0, v < 150 { best = max(best ?? 0, v) }
        }
        return best
    }

    /// 자체 검사용: 센서 이름별 값
    func allReadings() -> [(String, Double)] {
        lock.lock(); defer { lock.unlock() }
        guard let copyEvent, let getFloat else { return [] }
        return services.compactMap { s in
            guard let e = copyEvent(s.ref, Self.kTemperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return (s.name, getFloat(e, Self.kTemperatureField))
        }
    }
}

/// AppleSMC 읽기 전용 접근. 이 앱은 SMC에 값을 쓰지 않는다.
final class SysSMC {
    static let shared = SysSMC()

    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    // C 구조체와 같은 12바이트가 되도록 패딩을 둔다
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, attributes: UInt8 = 0, p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var opened = false

    var available: Bool { lock.lock(); defer { lock.unlock() }; return open() }

    /// 연결은 쓸 때 열고 close()로 닫는다 (탭이 닫히면 닫음)
    private func open() -> Bool {
        if opened { return true }
        guard MemoryLayout<Param>.stride == 80 else { return false }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        opened = IOServiceOpen(svc, mach_task_self_, 0, &connection) == KERN_SUCCESS
        return opened
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        if opened { IOServiceClose(connection); opened = false; connection = 0 }
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func typeName(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? ""
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var size = MemoryLayout<Param>.stride
        // 선택자 2 = 키 읽기·정보 (구조체 안 data8: 9 정보, 5 읽기)
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &size)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    /// 키 값 읽기 → (형식, 바이트). 없으면 nil.
    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        lock.lock(); defer { lock.unlock() }
        guard open() else { return nil }
        var info = Param()
        info.key = Self.fourCC(key)
        info.data8 = 9
        guard let i = call(&info) else { return nil }
        var req = Param()
        req.key = Self.fourCC(key)
        req.keyInfo.dataSize = i.keyInfo.dataSize
        req.data8 = 5
        guard let o = call(&req) else { return nil }
        let all = withUnsafeBytes(of: o.bytes) { Array($0) }
        return (Self.typeName(i.keyInfo.dataType), Array(all.prefix(Int(min(32, i.keyInfo.dataSize)))))
    }

    /// 숫자 키 (flt, ui8/16/32, fpe2)
    func number(_ key: String) -> Double? {
        guard let (type, b) = read(key) else { return nil }
        switch type {
        case "flt " where b.count == 4: return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 " where b.count >= 1: return Double(b[0])
        case "ui16" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4: return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "fpe2" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        default: return nil
        }
    }

    func has(_ key: String) -> Bool { read(key) != nil }

    struct Fan: Equatable, Identifiable {
        var id: Int
        var rpm: Double
        var min: Double
        var max: Double
    }

    func fans() -> [Fan] {
        guard let n = number("FNum"), n > 0 else { return [] }
        return (0..<Int(n)).map { i in
            Fan(id: i, rpm: number("F\(i)Ac") ?? 0, min: number("F\(i)Mn") ?? 0, max: number("F\(i)Mx") ?? 0)
        }
    }
}
