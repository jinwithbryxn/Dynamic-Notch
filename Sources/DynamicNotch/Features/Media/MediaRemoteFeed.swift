import Foundation

/// MediaRemote 어댑터(앱 리소스의 mr_run.pl + libMRAdapter.dylib를 /usr/bin/perl로 실행) 프로세스 하나를
/// 기본 미디어 표시(MediaController)와 음악 모듈(MBPlayerFeed)이 함께 쓴다.
/// - 구독하는 곳이 하나라도 있으면 띄우고, 모두 놓으면 끝낸다.
/// - 죽으면 구독이 남아 있는 동안 1초부터 최대 60초 간격으로 다시 띄운다.
/// - 어댑터가 보내는 줄(JSON)은 모든 구독자에게 그대로 전하고, 명령(toggle / next / prev / seek <초> / refresh)은 그대로 보낸다.
/// 모든 호출과 알림은 주 스레드에서.
final class MediaRemoteFeed {
    static let shared = MediaRemoteFeed()

    enum Event {
        case started
        /// 어댑터가 없거나, 띄우지 못했거나, 끝났다
        case stopped
        case report([String: Any])
    }

    private(set) var running = false
    private var subscribers: [String: (Event) -> Void] = [:]
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restartDelay: TimeInterval = 1

    static var available: Bool {
        guard let r = Bundle.main.resourceURL else { return false }
        return FileManager.default.fileExists(atPath: r.appendingPathComponent("libMRAdapter.dylib").path)
            && FileManager.default.fileExists(atPath: r.appendingPathComponent("mr_run.pl").path)
    }

    var subscriberCount: Int { subscribers.count }

    func subscribe(_ id: String, _ handler: @escaping (Event) -> Void) {
        subscribers[id] = handler
        if running {
            handler(.started)
            send("refresh")   // 이미 떠 있으면 지금 재생 정보를 다시 보내게 한다 (새 구독자용)
        } else if process == nil {
            start()
        }
    }

    func unsubscribe(_ id: String) {
        guard subscribers.removeValue(forKey: id) != nil, subscribers.isEmpty else { return }
        stop()
    }

    /// 앱을 끝낼 때: 구독과 상관없이 어댑터를 끝낸다
    func stopAll() {
        subscribers.removeAll()
        stop()
    }

    func send(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func start() {
        guard !subscribers.isEmpty, process == nil else { return }
        guard Self.available, let res = Bundle.main.resourceURL else { broadcast(.stopped); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [res.appendingPathComponent("mr_run.pl").path, res.appendingPathComponent("libMRAdapter.dylib").path]
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { h.readabilityHandler = nil; return }   // 끝(EOF)이면 더 부르지 않게
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.process = nil
                self.input = nil
                self.buffer.removeAll()
                self.running = false
                self.broadcast(.stopped)
                guard !self.subscribers.isEmpty else { return }
                let delay = self.restartDelay
                self.restartDelay = min(60, delay * 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.start() }
            }
        }
        do {
            try p.run()
            process = p
            input = inp.fileHandleForWriting
            running = true
            broadcast(.started)
        } catch {
            broadcast(.stopped)
        }
    }

    private func stop() {
        if let p = process {
            p.terminationHandler = nil
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if p.isRunning { p.terminate() }
        }
        try? input?.close()
        process = nil
        input = nil
        buffer.removeAll()
        running = false
        restartDelay = 1
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            restartDelay = 1
            broadcast(.report(obj))
        }
    }

    private func broadcast(_ event: Event) {
        for handler in subscribers.values { handler(event) }
    }
}
