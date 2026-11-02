import AppKit
import Darwin
import DiskArbitration
import IOKit

// 공개 API로 시스템 값을 읽는 도우미들. 모두 읽기만 한다.

/// CPU 사용률 (host_processor_info 틱 차이)
final class SysCPUReader {
    private var previous: [UInt32] = []

    /// (전체 0...1, 코어별 0...1). 첫 호출은 기준만 잡고 nil.
    func sample() -> (total: Double, cores: [Double])? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let n = Int(count)
        var now = [UInt32](repeating: 0, count: n * Int(CPU_STATE_MAX))
        for i in 0..<now.count { now[i] = UInt32(bitPattern: info[i]) }
        defer { previous = now }
        guard previous.count == now.count else { return nil }
        var cores: [Double] = []
        var busyAll: UInt64 = 0, totalAll: UInt64 = 0
        for c in 0..<n {
            let b = c * Int(CPU_STATE_MAX)
            func d(_ s: Int32) -> UInt64 { UInt64(now[b + Int(s)] &- previous[b + Int(s)]) }
            let busy = d(CPU_STATE_USER) + d(CPU_STATE_SYSTEM) + d(CPU_STATE_NICE)
            let total = busy + d(CPU_STATE_IDLE)
            cores.append(total > 0 ? Double(busy) / Double(total) : 0)
            busyAll += busy
            totalAll += total
        }
        return (totalAll > 0 ? Double(busyAll) / Double(totalAll) : 0, cores)
    }
}

/// 메모리 (Activity Monitor 방식: active + wired + compressed)
struct SysMemory: Equatable {
    var used: UInt64
    var total: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    /// kern.memorystatus_vm_pressure_level: 1 보통, 2 경고, 4 위험
    var pressureLevel: Int

    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func read() -> SysMemory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var page: vm_size_t = 0
        host_page_size(mach_host_self(), &page)
        let p = UInt64(page)
        let wired = UInt64(stats.wire_count) * p
        let compressed = UInt64(stats.compressor_page_count) * p
        let active = UInt64(stats.active_count) * p
        var level: Int32 = 0
        var len = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0)
        var swap = xsw_usage()
        var slen = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &slen, nil, 0)
        return SysMemory(used: active + wired + compressed, total: ProcessInfo.processInfo.physicalMemory,
                         wired: wired, compressed: compressed, swapUsed: UInt64(swap.xsu_used), pressureLevel: Int(level))
    }
}

/// GPU 사용률 (IOAccelerator PerformanceStatistics "Device Utilization %")
enum SysGPU {
    static func utilization() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            guard let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let v = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, v / 100)
        }
        return best
    }
}

/// 물리 인터페이스(en*, 이더넷 형식) 64비트 바이트 카운터 (sysctl ifmib)
struct SysIfBytes: Equatable { var rx: UInt64; var tx: UInt64 }

struct SysNetCounters: Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var interfaces: [String] = []
    var byInterface: [String: SysIfBytes] = [:]

    static func readPhysical() -> SysNetCounters {
        var result = SysNetCounters()
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mibCount: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT]
        guard sysctl(&mibCount, 5, &count, &size, nil, 0) == 0, count > 0 else { return result }
        for index in 1...count {
            var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, index, IFDATA_GENERAL]
            var data = ifmibdata()
            var len = MemoryLayout<ifmibdata>.size
            guard sysctl(&mib, 6, &data, &len, nil, 0) == 0 else { continue }
            let name = withUnsafeBytes(of: data.ifmd_name) { raw -> String in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            // en0(Wi-Fi), en1…(이더넷·썬더볼트)만. awdl·llw·utun·bridge·lo는 뺀다.
            guard name.hasPrefix("en"), Int32(data.ifmd_data.ifi_type) == IFT_ETHER else { continue }
            result.received &+= data.ifmd_data.ifi_ibytes
            result.sent &+= data.ifmd_data.ifi_obytes
            result.interfaces.append(name)
            result.byInterface[name] = SysIfBytes(rx: data.ifmd_data.ifi_ibytes, tx: data.ifmd_data.ifi_obytes)
        }
        return result
    }
}

/// 디스크 볼륨 (부트 디스크 먼저, 그다음 마운트 순서의 외장 볼륨)
struct SysVolume: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String
    var total: Int64
    var available: Int64
    var isBoot: Bool

    var usedFraction: Double { total > 0 ? Double(total - available) / Double(total) : 0 }

    static func readAll() -> [SysVolume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes])
        else { return [] }
        let session = DASessionCreate(kCFAllocatorDefault)
        var list: [SysVolume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.path
            let boot = path == "/"
            // 네트워크 공유·숨은 시스템 볼륨·Time Machine은 빼고
            if !boot {
                if v.volumeIsLocal == false || v.volumeIsBrowsable == false { continue }
                if path.hasPrefix("/System/Volumes") || path.contains("TimeMachine") || path.contains(".timemachine") { continue }
                if let session, isDiskImage(url, session) { continue }
            }
            guard let total = v.volumeTotalCapacity, total > 0 else { continue }
            let avail = v.volumeAvailableCapacityForImportantUsage.map { Int64($0) } ?? Int64(v.volumeAvailableCapacity ?? 0)
            list.append(SysVolume(path: path, name: v.volumeName ?? url.lastPathComponent, total: Int64(total),
                                  available: avail, isBoot: boot))
        }
        return list.sorted { a, b in a.isBoot && !b.isBoot }
    }

    private static func isDiskImage(_ url: URL, _ session: DASession) -> Bool {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let desc = DADiskCopyDescription(disk) as? [String: Any] else { return false }
        let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String) ?? ""
        let proto = (desc[kDADiskDescriptionDeviceProtocolKey as String] as? String) ?? ""
        return model.contains("Disk Image") || proto.contains("Disk Image")
    }
}

/// 프로세스별 CPU·에너지 (proc_pid_rusage 차이). 같은 사용자 프로세스만 읽힌다.
struct SysProcInfo: Identifiable, Equatable {
    var id: pid_t { pid }
    var pid: pid_t
    var name: String
    var path: String
    /// 한 코어 기준 % (100 = 한 코어를 다 씀)
    var cpu: Double
    /// 와트 (ri_energy_nj 차이, 없으면 nil)
    var watts: Double?
    /// 초당 깨우기 횟수
    var wakeups: Double
}

final class SysProcReader {
    private struct Mark { var cpuNs: UInt64; var energy: UInt64; var wakeups: UInt64 }
    private var previous: [pid_t: Mark] = [:]
    private var lastDate: Date?
    private let timebase: (UInt64, UInt64) = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(1, tb.denom)))
    }()
    private var useV6 = true
    /// 마지막 샘플에서 읽지 못한(다른 사용자·root) 프로세스 수
    private(set) var unreadable = 0

    /// 모든 읽을 수 있는 프로세스의 사용량. 첫 호출은 기준만 잡는다.
    func sample() -> [SysProcInfo] {
        let now = Date()
        var pids = [pid_t](repeating: 0, count: 8192)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var marks: [pid_t: Mark] = [:]
        var out: [SysProcInfo] = []
        let dt = lastDate.map { now.timeIntervalSince($0) } ?? 0
        var failed = 0
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            guard let m = read(pid) else { failed += 1; continue }
            marks[pid] = m
            guard dt > 0.2, let p = previous[pid] else { continue }
            let cpu = Double(m.cpuNs &- p.cpuNs) / 1e9 / dt * 100
            let watts: Double? = useV6 ? Double(m.energy &- p.energy) / 1e9 / dt : nil
            let wake = Double(m.wakeups &- p.wakeups) / dt
            guard cpu > 0.05 || (watts ?? 0) > 0.001 else { continue }
            out.append(SysProcInfo(pid: pid, name: "", path: "", cpu: max(0, cpu), watts: watts, wakeups: max(0, wake)))
        }
        previous = marks
        lastDate = now
        unreadable = failed
        return out
    }

    private func read(_ pid: pid_t) -> Mark? {
        if useV6 {
            var ri = rusage_info_v6()
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            if r == 0 {
                return Mark(cpuNs: ns(ri.ri_user_time + ri.ri_system_time), energy: ri.ri_energy_nj,
                            wakeups: ri.ri_pkg_idle_wkups + ri.ri_interrupt_wkups)
            }
            if errno == EINVAL { useV6 = false } else { return nil }
        }
        var ri = rusage_info_v4()
        let r = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard r == 0 else { return nil }
        return Mark(cpuNs: ns(ri.ri_user_time + ri.ri_system_time), energy: 0, wakeups: ri.ri_pkg_idle_wkups + ri.ri_interrupt_wkups)
    }

    private func ns(_ machTime: UInt64) -> UInt64 { machTime / timebase.1 * timebase.0 + (machTime % timebase.1) * timebase.0 / timebase.1 }

    static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    /// 보기 좋은 이름: 앱 이름 → 실행 파일 이름 → proc_name
    static func name(_ pid: pid_t, path: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let n = app.localizedName, !n.isEmpty { return n }
        if !path.isEmpty { return (path as NSString).lastPathComponent }
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "pid \(pid)"
    }

    /// 시스템 프로세스 (비정상 소모 알림에서 뺀다)
    static func isSystem(path: String) -> Bool {
        path.isEmpty || ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/"].contains { path.hasPrefix($0) }
    }
}
