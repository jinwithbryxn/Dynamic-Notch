import Darwin
import Foundation

/// 의사 터미널(PTY) 위의 셸 프로세스 하나.
/// openpty + posix_spawn(POSIX_SPAWN_SETSID)로 띄운다 (Swift에서 fork하지 않음).
/// 열린 파일은 PTY 말고는 물려주지 않는다 (POSIX_SPAWN_CLOEXEC_DEFAULT).
final class TerminalSession {
    let screen: TerminalScreen
    private(set) var pid: pid_t = 0
    private(set) var running = false
    private(set) var exitStatus: Int32?
    private var master: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    /// 화면이 바뀌면 메인 스레드에서 불린다
    var onChange: (() -> Void)?
    var onExit: ((Int32) -> Void)?

    init(cols: Int, rows: Int) {
        screen = TerminalScreen(cols: cols, rows: rows)
        screen.respond = { [weak self] bytes in self?.write(bytes) }
    }

    deinit { terminate() }

    enum StartError: LocalizedError {
        case pty(Int32), spawn(Int32)
        var errorDescription: String? {
            switch self {
            case .pty(let e): return "openpty: \(String(cString: strerror(e)))"
            case .spawn(let e): return "posix_spawn: \(String(cString: strerror(e)))"
            }
        }
    }

    /// 사용자 로그인 셸 (없으면 /bin/zsh)
    static var loginShell: String {
        if let pw = getpwuid(getuid()), let s = pw.pointee.pw_shell { let shell = String(cString: s); if FileManager.default.isExecutableFile(atPath: shell) { return shell } }
        return "/bin/zsh"
    }

    /// TIOCSCTTY = _IO('t', 97). 실패해도 셸은 띄운다.
    static let cttyTrampoline = #"ioctl(STDIN, 0x20007461, 0) or warn "dmn: no controlling tty: $!\n"; exec { $ARGV[0] } @ARGV or die "dmn: exec $ARGV[0]: $!\n";"#

    func start(shell: String = TerminalSession.loginShell, args: [String] = ["-l"], cwd: String? = nil, extraEnv: [String: String] = [:]) throws {
        guard !running else { return }
        var ws = winsize(ws_row: UInt16(screen.rows), ws_col: UInt16(screen.cols), ws_xpixel: 0, ws_ypixel: 0)
        var m: Int32 = -1, s: Int32 = -1
        guard openpty(&m, &s, nil, nil, &ws) == 0 else { throw StartError.pty(errno) }
        defer { close(s) }
        guard let namePtr = ptsname(m) else { close(m); throw StartError.pty(errno) }
        let slaveName = String(cString: namePtr)

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attr, &none)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGPIPE, SIGINT, SIGQUIT, SIGTERM, SIGHUP, SIGCHLD, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)

        var fa: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        // 새 세션에서 PTY 슬레이브를 열면 제어 터미널이 된다
        posix_spawn_file_actions_addopen(&fa, 0, slaveName, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&fa, 0, 1)
        posix_spawn_file_actions_adddup2(&fa, 0, 2)
        let dir = cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        posix_spawn_file_actions_addchdir_np(&fa, dir)

        var env = ProcessInfo.processInfo.environment.filter { ["HOME", "USER", "LOGNAME", "PATH", "SHELL", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "SSH_AUTH_SOCK"].contains($0.key) }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "DynamicNotch"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if env["SHELL"] == nil { env["SHELL"] = shell }
        for (k, v) in extraEnv { env[k] = v }

        // posix_spawn은 파일 작업을 setsid보다 먼저 해서 PTY가 제어 터미널이 되지 않는다 (ctrl+C가 안 먹음).
        // 그래서 시스템 perl로 TIOCSCTTY 한 번 부르고 같은 pid에서 셸로 exec한다. perl이 없으면 셸을 바로 띄운다.
        let perl = "/usr/bin/perl"
        let usesTrampoline = FileManager.default.isExecutableFile(atPath: perl)
        let path = usesTrampoline ? perl : shell
        let fullArgs = usesTrampoline ? [perl, "-e", Self.cttyTrampoline, "--", shell] + args : [shell] + args
        let argv = fullArgs.map { strdup($0) } + [nil]
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        let rc = posix_spawn(&child, path, &fa, &attr, argv, envp)
        guard rc == 0 else { close(m); throw StartError.spawn(rc) }

        master = m
        pid = child
        running = true
        exitStatus = nil
        _ = fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK)
        _ = fcntl(m, F_SETFD, FD_CLOEXEC)

        let rs = DispatchSource.makeReadSource(fileDescriptor: m, queue: .main)
        rs.setEventHandler { [weak self] in self?.readAvailable() }
        rs.resume()
        readSource = rs
        let es = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: .main)
        es.setEventHandler { [weak self] in self?.reap() }
        es.resume()
        exitSource = es
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 16384)
        var changed = false
        while true {
            let n = read(master, &buf, buf.count)
            if n > 0 { screen.feed(Array(buf[0..<n])); changed = true; continue }
            if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                // 셸이 끝났다 (EIO)
                readSource?.cancel()
                readSource = nil
            }
            break
        }
        if changed { onChange?() }
    }

    private func reap() {
        var status: Int32 = 0
        let r = waitpid(pid, &status, WNOHANG)
        guard r == pid || r < 0 else { return }
        readAvailable()
        running = false
        exitStatus = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        exitSource?.cancel()
        exitSource = nil
        closeMaster()
        onExit?(exitStatus ?? 0)
        onChange?()
    }

    func write(_ bytes: [UInt8]) {
        guard master >= 0, !bytes.isEmpty else { return }
        var offset = 0
        var tries = 0
        while offset < bytes.count, tries < 200 {
            let n = bytes.withUnsafeBufferPointer { Darwin.write(master, $0.baseAddress! + offset, bytes.count - offset) }
            if n > 0 { offset += n } else if errno == EAGAIN || errno == EINTR { tries += 1; usleep(1000) } else { break }
        }
    }

    func write(_ text: String) { write(Array(text.utf8)) }

    /// 붙여넣기 (프로그램이 붙여넣기 모드를 켰으면 감싼다)
    func paste(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        write(screen.bracketedPaste ? "\u{1B}[200~" + normalized + "\u{1B}[201~" : normalized)
    }

    func resize(cols: Int, rows: Int) {
        guard cols != screen.cols || rows != screen.rows else { return }
        screen.resize(cols: cols, rows: rows)
        guard master >= 0 else { return }
        var ws = winsize(ws_row: UInt16(screen.rows), ws_col: UInt16(screen.cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &ws)
    }

    /// 실제 PTY 크기 (검사용)
    var ptySize: (cols: Int, rows: Int)? {
        guard master >= 0 else { return nil }
        var ws = winsize()
        guard ioctl(master, TIOCGWINSZ, &ws) == 0 else { return nil }
        return (Int(ws.ws_col), Int(ws.ws_row))
    }

    private func closeMaster() {
        readSource?.cancel()
        readSource = nil
        if master >= 0 { close(master); master = -1 }
    }

    /// 셸과 그 자식(같은 프로세스 그룹)에 SIGHUP을 보내고 PTY를 닫는다.
    /// 2초 안에 안 끝나면 SIGKILL 후 거둬들인다 (좀비 안 남김).
    func terminate() {
        if running, pid > 0 {
            let p = pid
            kill(-p, SIGHUP)
            kill(p, SIGHUP)
            DispatchQueue.global().async {
                var st: Int32 = 0
                for _ in 0..<40 {
                    if waitpid(p, &st, WNOHANG) != 0 { return }
                    usleep(50_000)
                }
                kill(-p, SIGKILL)
                kill(p, SIGKILL)
                waitpid(p, &st, 0)
            }
        }
        exitSource?.cancel()
        exitSource = nil
        closeMaster()
        running = false
    }
}
