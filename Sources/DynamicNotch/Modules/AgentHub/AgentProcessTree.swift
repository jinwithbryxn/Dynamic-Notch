import AppKit

/// 에이전트를 돌린 화면 앱(터미널·VS Code·Claude 등)을 부모 프로세스를 거슬러 올라가 찾는다 (M-K-023).
enum AgentProcessTree {
    static func parent(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

    /// pid부터 위로 올라가며 처음 만나는 일반 앱
    static func guiAncestor(of pid: pid_t) -> NSRunningApplication? {
        var p = pid
        for _ in 0..<40 where p > 1 {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
            p = parent(of: p)
        }
        return nil
    }

    static func isAlive(_ pid: pid_t) -> Bool { pid > 1 && (kill(pid, 0) == 0 || errno == EPERM) }

    /// "번들ID|pid" (AgentNotify.open과 같은 형식)
    static func target(for pid: pid_t) -> String? {
        guard let app = guiAncestor(of: pid) else { return nil }
        return "\(app.bundleIdentifier ?? "")|\(app.processIdentifier)"
    }

    /// 그 앱을 앞으로
    @discardableResult
    static func jump(_ target: String?) -> Bool {
        guard let target else { return false }
        let parts = target.split(separator: "|").map(String.init)
        if parts.count > 1, let pid = pid_t(parts[1]), let app = NSRunningApplication(processIdentifier: pid) {
            return app.activate()
        }
        guard let id = parts.first, !id.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    static func appName(_ target: String?) -> String? {
        guard let target else { return nil }
        let parts = target.split(separator: "|").map(String.init)
        if parts.count > 1, let pid = pid_t(parts[1]), let app = NSRunningApplication(processIdentifier: pid) { return app.localizedName }
        return nil
    }

    /// 프로젝트 폴더를 Finder에서 연다
    static func openFolder(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
