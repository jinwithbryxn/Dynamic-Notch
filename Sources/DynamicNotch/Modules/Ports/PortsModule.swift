import AppKit
import SwiftUI

/// 사용 중인 포트: LISTEN 상태 TCP 포트와 프로세스(비특권 lsof, IPv4·IPv6, pid+포트로 중복 제거).
/// 팔레트에 "port 3000"·":3000"을 입력하면 바로 찾고, 종료는 사용자가 확인했을 때만 SIGTERM → 안 끝나면 SIGKILL을 제안한다.
final class PortsModule: NotchModule {
    let id = "ports"
    var title: String { T("포트", "Ports") }
    let symbol = "point.3.connected.trianglepath.dotted"
    var enabledByDefault: Bool { false }

    let model = PortsModel()

    func start(context: ModuleContext) { model.context = context; model.tabID = id }
    func stop() { model.stopLive(); model.context = nil }

    func tabView() -> AnyView? { AnyView(PortsTab(model: model)) }
    var tabContentSize: CGSize { CGSize(width: 520, height: 260) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "ports.open", title: T("사용 중인 포트 보기", "Show listening ports"),
                       subtitle: T("LISTEN 중인 TCP 포트와 프로세스", "Listening TCP ports and processes"),
                       symbol: symbol, keywords: ["port", "ports", "포트", "lsof", "listen"]) { [weak self] in
            guard let self else { return }
            self.model.context?.openTab(self.id)
        }]
    }

    /// "port 3000", "포트 3000", ":3000", "3000" → 캐시에서 바로 찾고, 오래됐으면 뒤에서 다시 읽는다
    func paletteResults(for query: String) -> [PaletteAction] {
        guard let prefix = Self.portQuery(query) else { return [] }
        model.refreshIfStale(maxAge: 3)
        return model.ports.filter { prefix.isEmpty || String($0.port).hasPrefix(prefix) }.prefix(8).map { p in
            PaletteAction(id: "ports.kill.\(p.id)", title: T("포트 \(p.port) · \(p.name)", "Port \(p.port) · \(p.name)"),
                          subtitle: T("pid \(p.pid) · \(p.bindings) · 누르면 종료할지 묻습니다", "pid \(p.pid) · \(p.bindings) · asks before stopping"),
                          symbol: "xmark.octagon", keywords: []) { [weak self] in
                self?.model.askTerminate(p)
            }
        }
    }

    static func portQuery(_ query: String) -> String? {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var explicit = false
        for p in ["port", "포트", ":"] where q.hasPrefix(p) {
            q = String(q.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            explicit = true
            break
        }
        if q.hasPrefix(":") { q.removeFirst() }
        guard q.allSatisfy(\.isNumber), q.count <= 5 else { return nil }
        if !explicit, q.count < 2 { return nil }   // 숫자만 입력했을 때는 두 자리부터
        return q
    }

    func selfTest() -> [String] {
        guard let list = PortScanner.scan() else { return ["lsof failed"] }
        var lines = ["listening TCP ports (this user, deduped by pid+port): \(list.count)"]
        for p in list.prefix(15) { lines.append("  \(p.port)\t\(p.name)\tpid \(p.pid)\t\(p.bindings)") }
        lines.append("palette parse 'port 3000' → \(Self.portQuery("port 3000") ?? "nil"), ':80' → \(Self.portQuery(":80") ?? "nil"), 'abc' → \(Self.portQuery("abc") ?? "nil")")
        // 팔레트 즉석 결과: 캐시가 차면 "port <번호>"로 찾아지는지
        let m = PortsModule()
        _ = m.paletteResults(for: "port")
        let deadline = Date().addingTimeInterval(8)
        while m.model.lastScan == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if let first = list.first {
            let hits = m.paletteResults(for: "port \(first.port)")
            lines.append("palette 'port \(first.port)' → \(hits.count) result(s): \(hits.first?.title ?? "-")")
        }
        lines.append("self test never sends signals")
        return lines
    }
}

struct ListeningPort: Identifiable, Equatable {
    var id: String { "\(pid):\(port)" }
    var pid: pid_t
    var name: String
    var port: Int
    var addresses: [String]
    var ipv4 = false
    var ipv6 = false

    var bindings: String {
        let fam = [ipv4 ? "IPv4" : nil, ipv6 ? "IPv6" : nil].compactMap { $0 }.joined(separator: "/")
        return Array(Set(addresses)).sorted().joined(separator: ", ") + (fam.isEmpty ? "" : " · \(fam)")
    }
}

enum PortScanner {
    /// lsof 필드 출력: p<pid>, c<명령>, f<fd>, t<IPv4|IPv6>, n<주소:포트>. 실패하면 nil. 백그라운드에서 부른다.
    static func scan() -> [ListeningPort]? {
        guard let r = SysCommand.run("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpctn"], timeout: 8) else { return nil }
        // 열린 포트가 없으면 lsof는 출력 없이 1로 끝난다. 출력이 있으면 끝 코드와 상관없이 읽는다.
        if r.output.isEmpty { return r.status == 0 || r.status == 1 ? [] : nil }
        var map: [String: ListeningPort] = [:]
        var order: [String] = []
        var pid: pid_t = 0, cmd = "", fam = ""
        for line in r.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = pid_t(value) ?? 0; cmd = ""
            case "c": cmd = value
            case "t": fam = value
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                var addr = String(value[..<colon])
                if addr.hasPrefix("[") { addr = String(addr.dropFirst().dropLast()) }
                let key = "\(pid):\(port)"
                if map[key] == nil {
                    map[key] = ListeningPort(pid: pid, name: displayName(pid, cmd), port: port, addresses: [])
                    order.append(key)
                }
                map[key]?.addresses.append(addr)
                if fam == "IPv4" { map[key]?.ipv4 = true }
                if fam == "IPv6" { map[key]?.ipv6 = true }
            default: break
            }
        }
        return order.compactMap { map[$0] }.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func displayName(_ pid: pid_t, _ cmd: String) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let n = app.localizedName { return n }
        return cmd.isEmpty ? "pid \(pid)" : cmd
    }

    /// 같은 프로세스가 아직 살아 있는지 (pid 재사용을 피하려고 실행 파일 경로도 비교)
    static func alive(_ pid: pid_t, path: String) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        return path.isEmpty || SysProcReader.path(pid) == path
    }
}

final class PortsModel: ObservableObject {
    enum Stage: Equatable { case confirmTerm, stopping, offerKill, confirmKill, failed(String) }

    @Published var ports: [ListeningPort] = []
    @Published var lastScan: Date?
    @Published var scanning = false
    @Published var error: String?
    @Published var stage: [String: Stage] = [:]

    var context: ModuleContext?
    var tabID = "ports"
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.dynamicnotch.ports", qos: .userInitiated)

    func startLive() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopLive() {
        timer?.invalidate(); timer = nil
    }

    func refreshIfStale(maxAge: TimeInterval) {
        if let t = lastScan, Date().timeIntervalSince(t) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            let list = PortScanner.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                self.lastScan = Date()
                if let list {
                    self.ports = list
                    self.error = nil
                    let ids = Set(list.map(\.id))
                    self.stage = self.stage.filter { ids.contains($0.key) }
                } else {
                    self.error = T("lsof를 실행하지 못함", "Could not run lsof")
                }
            }
        }
    }

    private func canSignal(_ p: ListeningPort) -> Bool { p.pid > 1 && p.pid != getpid() }

    // MARK: 팔레트에서: 노치 카드로 확인을 받는다

    func askTerminate(_ p: ListeningPort) {
        guard canSignal(p) else { return }
        let stop = ActivityAction(id: "ports.term.\(p.id)", title: T("종료 (SIGTERM)", "Stop (SIGTERM)"), role: .destructive) { [weak self] in
            self?.terminate(p)
        }
        let cancel = ActivityAction(id: "ports.cancel", title: T("취소", "Cancel")) { [weak self] in
            self?.context?.center.dismissTransient(kind: .notice)
        }
        context?.notice(T("포트 \(p.port)의 \(p.name)을(를) 종료할까요?", "Stop \(p.name) on port \(p.port)?"),
                        "pid \(p.pid) · \(p.bindings)", symbol: "xmark.octagon", tint: .orange, tab: tabID, duration: 12,
                        actions: [stop, cancel])
    }

    // MARK: 신호 보내기 (사용자 확인 뒤에만)

    func terminate(_ p: ListeningPort) {
        guard canSignal(p) else { return }
        let path = SysProcReader.path(p.pid)
        guard kill(p.pid, SIGTERM) == 0 else {
            let msg = errno == EPERM ? T("권한 없음 (다른 사용자 프로세스)", "Not permitted (another user's process)") : T("신호를 보내지 못함", "Could not send the signal")
            stage[p.id] = .failed(msg)
            context?.notice(T("\(p.name) 종료 실패", "Could not stop \(p.name)"), msg, symbol: "exclamationmark.triangle", tint: .red, tab: tabID)
            return
        }
        stage[p.id] = .stopping
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if PortScanner.alive(p.pid, path: path) {
                self.stage[p.id] = .offerKill
                let kill = ActivityAction(id: "ports.kill.\(p.id)", title: T("강제 종료 (SIGKILL)", "Force quit (SIGKILL)"), role: .destructive) { [weak self] in
                    self?.forceKill(p, path: path)
                }
                let cancel = ActivityAction(id: "ports.cancel", title: T("그대로 두기", "Leave running")) { [weak self] in
                    self?.context?.center.dismissTransient(kind: .notice)
                }
                self.context?.notice(T("\(p.name)이(가) 아직 실행 중", "\(p.name) is still running"),
                                     T("SIGTERM 뒤 2초가 지나도 끝나지 않았습니다", "It did not exit 2 s after SIGTERM"),
                                     symbol: "exclamationmark.triangle", tint: .orange, tab: self.tabID, duration: 12, actions: [kill, cancel])
            } else {
                self.stage[p.id] = nil
                self.context?.notice(T("포트 \(p.port) 비움", "Port \(p.port) freed"), T("\(p.name) 종료됨", "\(p.name) stopped"),
                                     symbol: "checkmark.circle", tint: .green, tab: self.tabID)
            }
            self.refresh()
        }
    }

    func forceKill(_ p: ListeningPort, path: String? = nil) {
        guard canSignal(p) else { return }
        let path = path ?? SysProcReader.path(p.pid)
        // pid가 다른 프로세스에 재사용됐으면 보내지 않는다
        guard PortScanner.alive(p.pid, path: path) else { stage[p.id] = nil; refresh(); return }
        if kill(p.pid, SIGKILL) == 0 {
            stage[p.id] = .stopping
            context?.notice(T("\(p.name) 강제 종료", "\(p.name) force quit"), "pid \(p.pid)", symbol: "xmark.octagon.fill", tint: .red, tab: tabID)
        } else {
            stage[p.id] = .failed(T("강제 종료 실패", "Force quit failed"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }
}

// MARK: - 탭

private struct PortsTab: View {
    @ObservedObject var model: PortsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(T("사용 중인 포트", "Listening ports")).font(.island(.callout, .semibold))
                Text(verbatim: "\(model.ports.count)").font(.island(.footnote)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let t = model.lastScan {
                    Text(SysFmt.time(t)).font(.island(.caption2)).foregroundStyle(.white.opacity(0.4))
                }
                SysPillButton(title: T("새로 고침", "Refresh"), symbol: "arrow.clockwise") { model.refresh() }
            }
            if let e = model.error { Text(e).font(.island(.caption)).foregroundStyle(.orange) }
            SysCard(padding: 4) {
                if model.ports.isEmpty {
                    Text(model.scanning ? T("읽는 중…", "Reading…") : T("LISTEN 중인 TCP 포트 없음", "No listening TCP ports"))
                        .font(.island(.footnote)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.ports) { p in row(p) }
                        }
                    }
                }
            }
            Text(T("비특권 lsof로 이 사용자 프로세스만 봅니다. 종료는 확인 뒤 SIGTERM, 끝나지 않으면 SIGKILL을 제안합니다.",
                   "Unprivileged lsof shows only this user's processes. Stopping asks first and sends SIGTERM, then offers SIGKILL."))
                .font(.island(.caption2)).foregroundStyle(.white.opacity(0.4))
        }
        .foregroundStyle(.white)
        .onAppear { model.startLive() }
        .onDisappear { model.stopLive() }
    }

    private func row(_ p: ListeningPort) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: ":\(p.port)").font(.island(.subhead, .semibold, design: .monospaced)).frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.island(.footnote)).lineLimit(1)
                Text(verbatim: "pid \(p.pid) · \(p.bindings)").font(.island(.caption2)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            controls(p)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(_ p: ListeningPort) -> some View {
        let mine = p.pid == getpid()
        switch model.stage[p.id] {
        case .confirmTerm?:
            Text(T("종료할까요?", "Stop it?")).font(.island(.caption))
            SysPillButton(title: "SIGTERM", tint: .orange, prominent: true) { model.terminate(p) }
            SysPillButton(title: T("취소", "Cancel")) { model.stage[p.id] = nil }
        case .stopping?:
            ProgressView().controlSize(.mini)
        case .offerKill?:
            Text(T("아직 실행 중", "Still running")).font(.island(.caption)).foregroundStyle(.orange)
            SysPillButton(title: T("강제 종료", "Force quit"), tint: .red) { model.stage[p.id] = .confirmKill }
        case .confirmKill?:
            Text(T("SIGKILL을 보낼까요?", "Send SIGKILL?")).font(.island(.caption))
            SysPillButton(title: "SIGKILL", tint: .red, prominent: true) { model.forceKill(p) }
            SysPillButton(title: T("취소", "Cancel")) { model.stage[p.id] = .offerKill }
        case .failed(let msg)?:
            Text(msg).font(.island(.caption2)).foregroundStyle(.red).lineLimit(1)
        case nil:
            if !mine {
                SysPillButton(title: T("종료", "Stop"), symbol: "xmark",
                              help: T("확인 뒤 SIGTERM을 보냅니다", "Asks, then sends SIGTERM")) { model.stage[p.id] = .confirmTerm }
            }
        }
    }
}
