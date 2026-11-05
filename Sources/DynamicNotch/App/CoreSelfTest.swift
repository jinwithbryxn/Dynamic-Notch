import Foundation

/// `--module-selftest=core`: 여러 기능이 함께 쓰는 부품 검사 (명령 봉투, AppleScript 큐, 전원 목록, 미디어 어댑터, HTTP 받기, 녹화 감지).
/// 네트워크 확인은 DMN_SELFTEST_NETWORK=1 일 때만.
enum CoreSelfTest {
    static func run() -> [String] {
        var lines = CommandEnvelope.selfTest()
        lines.append(appleScriptQueue())
        lines.append(contentsOf: powerSources())
        lines.append(mediaRemoteFeed())
        lines.append(contentsOf: httpFetch())
        lines.append(contentsOf: recordingCheck())
        lines.append(islandScale())
        return lines
    }

    /// 아일랜드 글자 단계가 iOS 글자 크기 × 환산 비율(0.5pt 단위)과 같고, 작은 것부터 커지는지
    private static func islandScale() -> String {
        let cases = IslandText.allCases
        let off = cases.filter { abs($0.rawValue - ($0.iosSize * Island.scale * 2).rounded() / 2) > 0.01 }
        let ordered = zip(cases, cases.dropFirst()).allSatisfy { $0.rawValue < $1.rawValue }
        guard off.isEmpty, ordered else {
            return "FAIL island type scale: off \(off.map { "\($0)" }), ordered \(ordered)"
        }
        return "PASS island type scale (\(cases.count) steps, iOS sizes x \(String(format: "%.3f", Island.scale)))"
    }

    /// 녹화 도구 이름 거르기가 ps와 같은지, 평소 확인(화면 캡처 여부)이 프로세스 목록 읽기보다 가벼운지
    private static func recordingCheck() -> [String] {
        guard let watcher = RecordingMonitor.screenWatcherPresent else {
            return ["WARN screen watcher call missing: the recording check reads the process list every time"]
        }
        func ms(_ count: Int, _ body: () -> Void) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<count { body() }
            return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count) / 1_000_000
        }
        var procs = (ui: false, cliVideo: false)
        let listMs = ms(50) { procs = RecordingMonitor.recorderProcesses() }
        var watched = false
        let watcherMs = ms(200) { watched = watcher() }
        let uid = String(getuid())
        let names = (ps("uid=,comm=") ?? "").split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[0] == uid else { return nil }
            return (String(parts[1]) as NSString).lastPathComponent
        }
        let tool = names.contains("screencaptureui") || names.contains("QuickTime Player")
        return [
            String(format: "recording check: screen watched %@, watcher call %.3f ms, process list %.3f ms",
                   watched ? "yes" : "no", watcherMs, listMs),
            procs.ui == tool ? "PASS recorder process filter agrees with ps (capture tool \(tool ? "running" : "not running"))"
                             : "FAIL recorder process filter says \(procs.ui), ps says \(tool)",
            watcherMs < listMs ? "PASS the screen watcher check is cheaper than reading the process list"
                               : "WARN the screen watcher check is not cheaper than reading the process list",
        ]
    }

    /// 권한이 필요 없는 스크립트로, 큐 안에서 다시 불러도 멈추지 않는지 본다
    private static func appleScriptQueue() -> String {
        let sem = DispatchSemaphore(value: 0)
        var value: Int32?
        DispatchQueue.global().async {
            value = AppleScriptQueue.queue.sync { AppleScriptQueue.run("return 6 * 7").result?.int32Value }
            sem.signal()
        }
        let finished = sem.wait(timeout: .now() + 10) == .success
        return finished && value == 42 ? "PASS AppleScript queue runs scripts and does not deadlock when called from inside itself"
                                       : "FAIL AppleScript queue (finished \(finished), result \(String(describing: value)))"
    }

    private static func powerSources() -> [String] {
        let system = PowerSources.system()
        let hasBattery = system.contains { $0["Type"] as? String == "InternalBattery" }
        let battery = BatteryMonitor.read()
        return [
            "power sources: \(system.count) system (internal battery \(hasBattery ? "found" : "not found")), \(PowerSources.accessories().count) accessories",
            hasBattery == (battery != nil) ? "PASS battery reading agrees with the shared power source list (\(battery.map { "\($0.percent)%" } ?? "no battery"))"
                                           : "FAIL battery reading and power source list disagree",
        ]
    }

    /// 두 곳이 구독해도 어댑터 프로세스는 하나이고, 둘 다 놓으면 끝나는지
    private static func mediaRemoteFeed() -> String {
        guard MediaRemoteFeed.available else { return "WARN media adapter resources missing (run from the built app)" }
        let feed = MediaRemoteFeed.shared
        var started = ["a": 0, "b": 0]
        feed.subscribe("selftest-a") { if case .started = $0 { started["a", default: 0] += 1 } }
        feed.subscribe("selftest-b") { if case .started = $0 { started["b", default: 0] += 1 } }
        spin(1)
        let together = adapterChildren()
        feed.unsubscribe("selftest-a")
        let keptForB = feed.running
        feed.unsubscribe("selftest-b")
        spin(1)
        let after = adapterChildren()
        let ok = together == 1 && started["a"] == 1 && started["b"] == 1 && keptForB && !feed.running && after == 0
        return ok ? "PASS two subscribers share one adapter process, which ends when both leave"
                  : "FAIL adapter sharing: processes \(together) → \(after), started \(started), kept for second \(keptForB)"
    }

    private static func httpFetch() -> [String] {
        var lines: [String] = []
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-http-\(UUID().uuidString).txt")
        try? Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        lines.append(HTTPFetch.data(file, timeout: 2, maxBytes: 100) == nil ? "PASS HTTP fetch refuses non-HTTP responses"
                                                                             : "FAIL HTTP fetch accepted a file URL")
        guard ProcessInfo.processInfo.environment["DMN_SELFTEST_NETWORK"] == "1",
              let url = URL(string: "https://api.github.com/repos/jinwithbryxn/Dynamic-Notch") else {
            lines.append("network fetch skipped (set DMN_SELFTEST_NETWORK=1)")
            return lines
        }
        let headers = ["User-Agent": "DynamicNotch-selftest"]
        let full = HTTPFetch.data(url, timeout: 10, maxBytes: 1_000_000, headers: headers)
        let small = HTTPFetch.data(url, timeout: 10, maxBytes: 10, headers: headers)
        lines.append(full != nil && small == nil ? "PASS HTTP fetch returns the body (\(full!.count) bytes) and drops it above the size limit"
                                                 : "FAIL HTTP fetch: full \(full?.count ?? -1), small \(small?.count ?? -1)")
        return lines
    }

    private static func spin(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// 이 프로세스가 띄운 mr_run.pl 개수
    private static func adapterChildren() -> Int {
        guard let out = ps("ppid=,command=") else { return -1 }
        let me = String(getpid())
        return out.split(separator: "\n").filter { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            return parts.first.map(String.init) == me && line.contains("mr_run.pl")
        }.count
    }

    /// 모든 프로세스의 `ps -axo <fields>` 출력 (앞 공백은 지운다)
    private static func ps(_ fields: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", fields]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.drop(while: { $0 == " " }) }.joined(separator: "\n")
    }
}
