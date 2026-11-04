import AppKit
import Combine

/// 시스템 모니터 측정기. 쓰는 곳(탭 화면, 노치 게이지)이 하나라도 있을 때만 1.5초마다 잰다.
/// 아무도 안 쓰면 타이머가 없다. 헤더 게이지 등 다른 화면도 `acquire`/`release`로 같은 값을 쓸 수 있다.
final class SysMonSampler: ObservableObject {
    static let shared = SysMonSampler()

    struct Snapshot: Equatable {
        var date = Date.distantPast
        var cpu: Double?
        var cores: [Double] = []
        var memory: SysMemory?
        var gpu: Double?
        var cpuTemp: Double?
        /// 초당 바이트
        var netIn: Double?
        var netOut: Double?
        var processes: [SysProcInfo] = []
        var unreadableProcesses = 0
    }

    enum Part: Hashable { case basic, processes, volumes }
    enum Rank: String { case cpu, energy }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var volumes: [SysVolume] = []

    var interval: TimeInterval = 1.5
    var rank: Rank = .cpu
    var topCount = 5

    private var users: [String: Set<Part>] = [:]
    private var timer: Timer?
    private var volumeTimer: Timer?
    private let queue = DispatchQueue(label: "com.dynamicnotch.sysmon", qos: .utility)
    private let cpuReader = SysCPUReader()
    private let procReader = SysProcReader()
    private var lastNet: (SysNetCounters, Date)?
    private var busy = false

    var isRunning: Bool { timer != nil }

    private var parts: Set<Part> { users.values.reduce(into: Set<Part>()) { $0.formUnion($1) } }

    /// 측정을 쓰기 시작한다 (같은 이름으로 다시 부르면 필요한 부분만 바꾼다)
    func acquire(_ user: String, _ parts: Set<Part>) {
        users[user] = parts
        reschedule()
        sampleNow()
        if parts.contains(.volumes) { refreshVolumes() }
    }

    func release(_ user: String) {
        users[user] = nil
        reschedule()
    }

    private func reschedule() {
        let need = parts
        if need.isEmpty {
            timer?.invalidate(); timer = nil
            volumeTimer?.invalidate(); volumeTimer = nil
            lastNet = nil
            return
        }
        if timer == nil {
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sampleNow() }
            t.tolerance = 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        if need.contains(.volumes) {
            if volumeTimer == nil {
                let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshVolumes() }
                t.tolerance = 5
                RunLoop.main.add(t, forMode: .common)
                volumeTimer = t
            }
        } else {
            volumeTimer?.invalidate(); volumeTimer = nil
        }
    }

    func refreshVolumes() {
        queue.async { [weak self] in
            let list = SysVolume.readAll()
            DispatchQueue.main.async { self?.volumes = list }
        }
    }

    private func sampleNow() {
        guard !busy else { return }
        let need = parts
        guard !need.isEmpty else { return }
        busy = true
        let rank = self.rank, top = self.topCount
        let prevNet = lastNet
        queue.async { [weak self] in
            guard let self else { return }
            var s = Snapshot()
            s.date = Date()
            if let c = self.cpuReader.sample() { s.cpu = c.total; s.cores = c.cores }
            s.memory = SysMemory.read()
            s.gpu = SysGPU.utilization()
            s.cpuTemp = SysTemperature.shared.hottestCPU()
            let net = SysNetCounters.readPhysical()
            if let (old, at) = prevNet, net.received >= old.received, net.sent >= old.sent {
                let dt = s.date.timeIntervalSince(at)
                if dt > 0.2 {
                    s.netIn = Double(net.received - old.received) / dt
                    s.netOut = Double(net.sent - old.sent) / dt
                }
            }
            if need.contains(.processes) {
                var list = self.procReader.sample()
                switch rank {
                case .cpu: list.sort { $0.cpu > $1.cpu }
                case .energy: list.sort { ($0.watts ?? $0.cpu / 100) > ($1.watts ?? $1.cpu / 100) }
                }
                s.processes = Array(list.prefix(top)).map { p in
                    var p = p
                    p.path = SysProcReader.path(p.pid)
                    return p
                }
                s.unreadableProcesses = self.procReader.unreadable
            }
            DispatchQueue.main.async {
                self.busy = false
                guard !self.parts.isEmpty else { return }
                self.lastNet = (net, s.date)
                var snap = s
                // 앱 이름은 메인 스레드에서
                snap.processes = s.processes.map { p in var p = p; p.name = SysProcReader.name(p.pid, path: p.path); return p }
                if !need.contains(.processes) { snap.processes = self.snapshot.processes }
                self.snapshot = snap
            }
        }
    }
}
