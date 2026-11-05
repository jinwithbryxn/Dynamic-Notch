import Combine
import SwiftUI

/// 시스템 모니터: CPU·메모리·GPU·CPU 온도·네트워크 처리량·상위 프로세스·디스크.
/// 탭이 보이는 동안, 또는 노치 CPU 게이지를 켰을 때만 측정한다. 온도는 비공개 센서 API라 기본 꺼짐.
final class SystemMonitorModule: NotchModule {
    let id = "sysmon"
    var title: String { T("시스템", "System") }
    let symbol = "cpu"
    var enabledByDefault: Bool { false }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    private var context: ModuleContext?
    private var gaugeSub: AnyCancellable?
    let sampler = SysMonSampler.shared

    // 설정
    var showGauge: Bool { defaults.bool("notchGauge", default: false) }
    var rankByEnergy: Bool { defaults.string("rank", default: "cpu") == "energy" }
    var fahrenheit: Bool { defaults.bool("fahrenheit", default: false) }
    var showDrives: Bool { defaults.bool("showDrives", default: true) }

    func start(context: ModuleContext) {
        self.context = context
        applySettings()
    }

    func stop() {
        gaugeSub = nil
        sampler.release("sysmon.tab")
        sampler.release("sysmon.gauge")
        context?.center.removePersistent(.system)
        SysSMC.shared.close()
        context = nil
    }

    func settingsChanged() { applySettings() }

    private func applySettings() {
        sampler.rank = rankByEnergy ? .energy : .cpu
        guard let context else { return }
        if showGauge {
            sampler.acquire("sysmon.gauge", [.basic])
            gaugeSub = sampler.$snapshot.receive(on: RunLoop.main).sink { [weak self] s in self?.postGauge(s) }
        } else {
            gaugeSub = nil
            sampler.release("sysmon.gauge")
            context.center.removePersistent(.system)
        }
    }

    /// 노치 상시 표시: CPU 원형 게이지 (정수 %로만 바뀔 때 다시 게시)
    private func postGauge(_ s: SysMonSampler.Snapshot) {
        guard let context, let cpu = s.cpu else { return }
        let v = (cpu * 100).rounded() / 100
        let tint: Color = v > 0.85 ? .red : v > 0.6 ? .orange : .green
        var subtitle = T("메모리 ", "Memory ") + (s.memory.map { SysFmt.percent($0.fraction) } ?? "–")
        if let t = s.cpuTemp { subtitle += " · " + SysFmt.temperature(t, fahrenheit: fahrenheit) }
        context.center.setPersistent(NotchActivity(
            kind: .system, priority: ActivityPriority.pinned, symbol: "cpu", tint: tint,
            value: .ringPercent(v), title: T("CPU \(SysFmt.percent(v))", "CPU \(SysFmt.percent(v))"),
            subtitle: subtitle, moduleTab: id))
    }

    func tabView() -> AnyView? { AnyView(SysMonTab(module: self)) }
    var tabContentSize: CGSize { CGSize(width: 580, height: 276) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "sysmon.open", title: T("시스템 모니터 열기", "Open System Monitor"),
                       subtitle: T("CPU·메모리·GPU·온도·네트워크", "CPU, memory, GPU, temperature, network"),
                       symbol: symbol, keywords: ["cpu", "memory", "gpu", "system", "시스템", "메모리", "온도"]) { [weak self] in
            guard let self else { return }
            self.context?.openTab(self.id)
        }]
    }

    func settingsView() -> AnyView? { AnyView(SysMonSettings(module: self)) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let cpu = SysCPUReader()
        _ = cpu.sample()
        let procs = SysProcReader()
        _ = procs.sample()
        let net0 = SysNetCounters.readPhysical()
        Thread.sleep(forTimeInterval: 1.0)
        if let c = cpu.sample() {
            lines.append(String(format: "cpu total %.1f%% cores %d [%@]", c.total * 100, c.cores.count,
                                c.cores.map { String(format: "%.0f", $0 * 100) }.joined(separator: " ")))
        } else { lines.append("cpu: unavailable") }
        if let m = SysMemory.read() {
            lines.append("memory used \(SysFmt.bytes(Int64(m.used))) of \(SysFmt.bytes(Int64(m.total))) (\(SysFmt.percent(m.fraction))) wired \(SysFmt.bytes(Int64(m.wired))) compressed \(SysFmt.bytes(Int64(m.compressed))) swap \(SysFmt.bytes(Int64(m.swapUsed))) pressure level \(m.pressureLevel)")
        }
        lines.append("gpu utilization " + (SysGPU.utilization().map { SysFmt.percent($0) } ?? "unavailable"))
        if let t = SysTemperature.shared.hottestCPU() {
            lines.append(String(format: "cpu temperature hottest %.1f °C", t))
        } else {
            lines.append("cpu temperature unsupported: \(SysTemperature.shared.unsupportedReason ?? "-")")
        }
        let net1 = SysNetCounters.readPhysical()
        lines.append("network physical \(net1.interfaces.joined(separator: ",")) total rx \(SysFmt.bytes(Int64(net1.received))) tx \(SysFmt.bytes(Int64(net1.sent))) · last 1 s rx \(SysFmt.rate(Double(net1.received &- net0.received))) tx \(SysFmt.rate(Double(net1.sent &- net0.sent)))")
        let top = procs.sample().sorted { $0.cpu > $1.cpu }.prefix(5)
        lines.append("top processes (cpu, readable; \(procs.unreadable) unreadable):")
        for p in top {
            let path = SysProcReader.path(p.pid)
            lines.append(String(format: "  %@ pid %d cpu %.1f%% power %@ wakeups %.0f/s", SysProcReader.name(p.pid, path: path), p.pid, p.cpu,
                                p.watts.map { String(format: "%.2f W", $0) } ?? "n/a", p.wakeups))
        }
        for v in SysVolume.readAll() {
            lines.append("volume \(v.name) \(v.isBoot ? "(boot)" : "") free \(SysFmt.bytes(v.available)) of \(SysFmt.bytes(v.total))")
        }
        return lines
    }

    func setOption(_ value: Any?, _ name: String) { defaults.set(value, name); applySettings() }
}

// MARK: - 탭 화면

private struct SysMonTab: View {
    let module: SystemMonitorModule
    @ObservedObject var sampler = SysMonSampler.shared
    @State private var rankByEnergy = false

    var body: some View {
        let s = sampler.snapshot
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                gauge(T("CPU", "CPU"), value: s.cpu, detail: s.cores.isEmpty ? "–" : T("\(s.cores.count)코어", "\(s.cores.count) cores"))
                memoryCard(s.memory)
                gauge("GPU", value: s.gpu, detail: s.gpu == nil ? T("읽을 수 없음", "Unavailable") : T("가속기", "Accelerator"))
                tempCard(s.cpuTemp)
                netCard(s)
            }
            .frame(height: 74)
            HStack(spacing: 8) {
                processCard(s)
                if module.showDrives { drivesCard }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            rankByEnergy = module.rankByEnergy
            sampler.acquire("sysmon.tab", module.showDrives ? [.basic, .processes, .volumes] : [.basic, .processes])
        }
        .onDisappear { sampler.release("sysmon.tab") }
    }

    private func color(_ v: Double) -> Color { v > 0.85 ? .red : v > 0.6 ? .orange : .green }

    private func gauge(_ title: String, value: Double?, detail: String) -> some View {
        SysCard {
            HStack(spacing: 8) {
                ZStack {
                    SysRing(value: value ?? 0, tint: color(value ?? 0), lineWidth: 4)
                    Text(value.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                        .font(.island(.subhead, .semibold)).monospacedDigit()
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.island(.subhead, .semibold))
                    Text(detail).font(.island(.caption)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func memoryCard(_ m: SysMemory?) -> some View {
        let label: String
        let tint: Color
        switch m?.pressureLevel ?? 1 {
        case 4: label = T("압력 높음", "High pressure"); tint = .red
        case 2: label = T("압력 경고", "Pressure warning"); tint = .orange
        default: label = T("압력 정상", "Normal pressure"); tint = .green
        }
        return SysCard {
            HStack(spacing: 8) {
                ZStack {
                    SysRing(value: m?.fraction ?? 0, tint: tint, lineWidth: 4)
                    Text(m.map { "\(Int(($0.fraction * 100).rounded()))" } ?? "–")
                        .font(.island(.subhead, .semibold)).monospacedDigit()
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("메모리", "Memory")).font(.island(.subhead, .semibold))
                    Text(m.map { String(format: "%.0f/%.0f GB", Double($0.used) / 1_073_741_824, Double($0.total) / 1_073_741_824) } ?? "–")
                        .font(.island(.caption)).monospacedDigit().foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    Text(label).font(.island(.caption2)).foregroundStyle(tint.opacity(0.9)).lineLimit(1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
    }

    private func tempCard(_ t: Double?) -> some View {
        SysCard {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium").font(.island(.footnote))
                    Text(T("CPU 온도", "CPU Temp")).font(.island(.footnote, .semibold))
                }
                if let t {
                    Text(SysFmt.temperature(t, fahrenheit: module.fahrenheit))
                        .font(.island(.title2)).monospacedDigit()
                        .foregroundStyle(t > 90 ? .red : t > 75 ? .orange : .white)
                } else {
                    Text(T("지원 안 됨", "Unsupported")).font(.island(.footnote))
                    Text(SysTemperature.shared.unsupportedReason ?? "").font(.island(.caption2)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func netCard(_ s: SysMonSampler.Snapshot) -> some View {
        SysCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(T("네트워크", "Network")).font(.island(.footnote, .semibold))
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.island(.caption2, .bold)).foregroundStyle(.cyan)
                    Text(s.netIn.map(SysFmt.rate) ?? "–").font(.island(.footnote)).monospacedDigit()
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.island(.caption2, .bold)).foregroundStyle(.pink)
                    Text(s.netOut.map(SysFmt.rate) ?? "–").font(.island(.footnote)).monospacedDigit()
                }
            }
            .lineLimit(1)
        }
        .frame(width: 104)
        .accessibilityElement(children: .combine)
    }

    private func processCard(_ s: SysMonSampler.Snapshot) -> some View {
        SysCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    SysHeader(text: T("상위 프로세스", "Top processes"))
                    Spacer()
                    Picker("", selection: $rankByEnergy) {
                        Text("CPU").tag(false)
                        Text(T("에너지", "Energy")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(width: 110)
                    .onChange(of: rankByEnergy) { v in module.setOption(v ? "energy" : "cpu", "rank") }
                    .help(T("에너지: CPU 시간과 깨우기를 반영한 전력 추정(커널 에너지 값)", "Energy: kernel power estimate (CPU time and wakeups)"))
                }
                if s.processes.isEmpty {
                    Text(T("측정 중…", "Measuring…")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(s.processes) { p in
                    HStack(spacing: 6) {
                        Text(p.name).font(.island(.footnote)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if rankByEnergy, let w = p.watts {
                            Text(w >= 1 ? String(format: "%.1f W", w) : String(format: "%.0f mW", w * 1000))
                                .font(.island(.footnote)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                        }
                        Text(String(format: "%.0f%%", p.cpu))
                            .font(.island(.footnote)).monospacedDigit()
                            .foregroundStyle(p.cpu > 80 ? .orange : .white.opacity(0.75))
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
                if s.unreadableProcesses > 0 {
                    Text(T("다른 사용자·시스템(root) 프로세스 \(s.unreadableProcesses)개는 권한이 없어 빠짐",
                           "\(s.unreadableProcesses) root/other-user processes not readable without privileges"))
                        .font(.island(.caption2)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
            }
        }
    }

    private var drivesCard: some View {
        SysCard {
            VStack(alignment: .leading, spacing: 6) {
                SysHeader(text: T("디스크", "Drives"))
                if sampler.volumes.isEmpty {
                    Text(T("읽는 중…", "Reading…")).font(.island(.footnote)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(sampler.volumes.prefix(4)) { v in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: v.isBoot ? "internaldrive" : "externaldrive").font(.island(.caption))
                            Text(v.name).font(.island(.footnote)).lineLimit(1)
                            Spacer()
                            Text(T("\(SysFmt.bytes(v.available)) 남음", "\(SysFmt.bytes(v.available)) free"))
                                .font(.island(.caption)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                        }
                        SysBar(value: v.usedFraction, tint: v.usedFraction > 0.9 ? .red : .blue)
                        Text(T("전체 \(SysFmt.bytes(v.total))", "of \(SysFmt.bytes(v.total))"))
                            .font(.island(.caption2)).foregroundStyle(.white.opacity(0.4))
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 220)
    }
}

// MARK: - 설정

private struct SysMonSettings: View {
    let module: SystemMonitorModule
    @State private var gauge = false
    @State private var energy = false
    @State private var fahrenheit = false
    @State private var drives = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("노치에 CPU 게이지 늘 표시 (1.5초마다 측정)", "Always show a CPU gauge in the notch (samples every 1.5 s)"), isOn: $gauge)
                .onChange(of: gauge) { module.setOption($0, "notchGauge") }
            Toggle(T("프로세스를 에너지 기준으로 정렬", "Rank processes by energy"), isOn: $energy)
                .onChange(of: energy) { module.setOption($0 ? "energy" : "cpu", "rank") }
            Toggle(T("온도를 °F로 표시", "Show temperature in °F"), isOn: $fahrenheit)
                .onChange(of: fahrenheit) { module.setOption($0, "fahrenheit") }
            Toggle(T("디스크 행 표시", "Show drive rows"), isOn: $drives)
                .onChange(of: drives) { module.setOption($0, "showDrives") }
            Text(T("탭이 보이는 동안만 측정합니다. CPU 온도는 macOS 비공개 센서 API(IOHIDEventSystemClient)를 씁니다. 다른 사용자·root 프로세스는 권한 없이 읽을 수 없어 목록에서 빠집니다.",
                   "Sampling runs only while the tab is visible. CPU temperature uses the private IOHIDEventSystemClient sensor API. Root and other-user processes cannot be read without privileges and are left out."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            gauge = module.showGauge
            energy = module.rankByEnergy
            fahrenheit = module.fahrenheit
            drives = module.showDrives
        }
    }
}
