import AppKit
import Carbon.HIToolbox
import SwiftUI

// 실행·검색·입력 묶음(launcher 계열 모듈)이 함께 쓰는 도우미.
// 다른 작업과 이름이 겹치지 않게 모두 Launch 접두어를 붙인다.

// MARK: - 화면 조각

enum LaunchUI {
    static let fill = Color.white.opacity(0.08)
    static let fillStrong = Color.white.opacity(0.16)
    static let secondary = Color.white.opacity(0.6)
}

/// 작은 캡슐 버튼
struct LaunchChip: View {
    let title: String
    var symbol: String? = nil
    var selected = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                if !title.isEmpty { Text(title).lineLimit(1) }
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.white.opacity(0.85) : LaunchUI.fill))
            .foregroundStyle(selected ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(help ?? title)
    }
}

/// "지원 안 됨 + 이유 + 대안" 상태
struct LaunchUnsupportedView: View {
    let title: String
    let reason: String
    var alternative: String? = nil
    var symbol = "exclamationmark.triangle"
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(LaunchUI.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(reason).font(.system(size: 11)).foregroundStyle(LaunchUI.secondary).multilineTextAlignment(.center)
            if let alternative {
                Text(alternative).font(.system(size: 11)).foregroundStyle(LaunchUI.secondary).multilineTextAlignment(.center)
            }
            if let buttonTitle, let buttonAction { LaunchChip(title: buttonTitle, action: buttonAction).padding(.top, 2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

/// 노치 안 입력 칸 (둥근 배경, 왼쪽 아이콘)
struct LaunchField: View {
    let placeholder: String
    @Binding var text: String
    var symbol = "magnifyingglass"
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(LaunchUI.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused(focus)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(LaunchUI.secondary) }
                    .buttonStyle(.plain).help(T("지우기", "Clear")).accessibilityLabel(T("지우기", "Clear"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LaunchUI.fill))
    }
}

// MARK: - 시스템 도우미

enum LaunchSystem {
    /// Info.plist에 권한 문구가 있는지 (없이 요청하면 macOS가 앱을 끝낸다)
    static func hasUsageKey(_ key: String) -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false
    }

    /// 손쉬운 사용 권한 (확인만, 요청 창 없음)
    static var axTrusted: Bool { AXIsProcessTrusted() }

    /// 사용자가 누른 동작에서만: 손쉬운 사용 권한 요청 창을 띄운다
    static func requestAX() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// PATH와 Homebrew 기본 위치에서 실행 파일을 찾는다 (실행하지 않음)
    static func findExecutable(_ name: String) -> String? {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", NSHomeDirectory() + "/.local/bin"]
        for d in dirs {
            let p = (d as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// http(s) 링크로 보이면 URL을 돌려준다 (붙여넣은 링크 바로 열기)
    static func webURL(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), !t.isEmpty else { return nil }
        if let u = URL(string: t), let s = u.scheme?.lowercased(), s == "http" || s == "https", u.host != nil { return u }
        // "example.com/path" 형태 (흔한 최상위 도메인만: file.txt 같은 파일 이름을 링크로 보지 않게)
        if t.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(/\S*)?$"#, options: .regularExpression) != nil,
           let last = t.split(separator: "/").first?.split(separator: ".").last,
           commonTLDs.contains(last.lowercased()) {
            return URL(string: "https://" + t)
        }
        return nil
    }

    static let commonTLDs: Set<String> = [
        "com", "net", "org", "io", "dev", "app", "ai", "co", "kr", "jp", "me", "so", "gg", "tv", "xyz", "info", "edu", "gov",
        "uk", "de", "fr", "us", "ca", "au", "cn", "ru", "in", "page", "site", "tech", "cloud", "blog", "shop", "store", "link",
        "ly", "to", "sh", "fm", "im", "es", "it", "nl", "se", "ch", "be", "at", "pl", "br", "mx", "tw", "hk", "sg", "vn", "th",
        "id", "ph", "my", "nz", "eu", "asia", "biz", "news", "wiki", "design", "studio", "art", "zone", "one", "space", "run",
    ]
}

/// 외부 명령을 백그라운드에서 실행하고 결과를 메인 스레드로 돌려준다.
final class LaunchProcess {
    struct Result { let status: Int32; let out: String; let err: String }

    private(set) var process: Process?

    /// 출력 한 줄마다 onLine(메인 스레드), 끝나면 done(메인 스레드)
    func run(_ path: String, _ args: [String], timeout: TimeInterval? = nil,
             onLine: ((String) -> Void)? = nil, done: @escaping (Result) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        var outData = Data(), errData = Data()
        let lock = NSLock()
        var pending = ""
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            lock.lock(); outData.append(d); lock.unlock()
            if let onLine, let s = String(data: d, encoding: .utf8) {
                pending += s
                // yt-dlp 진행률은 \r 또는 \n으로 끝난다
                let parts = pending.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
                pending = parts.last ?? ""
                for line in parts.dropLast() where !line.isEmpty { DispatchQueue.main.async { onLine(line) } }
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            lock.lock(); errData.append(d); lock.unlock()
        }
        p.terminationHandler = { proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let restOut = out.fileHandleForReading.readDataToEndOfFile()
            let restErr = err.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); outData.append(restOut); errData.append(restErr); lock.unlock()
            let r = Result(status: proc.terminationStatus,
                           out: String(data: outData, encoding: .utf8) ?? "",
                           err: String(data: errData, encoding: .utf8) ?? "")
            DispatchQueue.main.async { done(r) }
        }
        do {
            try p.run()
            process = p
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak p] in
                    if let p, p.isRunning { p.terminate() }
                }
            }
        } catch {
            DispatchQueue.main.async { done(Result(status: -1, out: "", err: error.localizedDescription)) }
        }
    }

    func cancel() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// 짧은 명령을 동기로 실행 (자체 검사용, 메인 스레드에서 오래 걸리지 않는 것만)
    static func runSync(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Result(status: -1, out: "", err: error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        var o = Data(), e = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate() }
        _ = group.wait(timeout: .now() + 2)
        p.waitUntilExit()
        return Result(status: p.terminationStatus, out: String(data: o, encoding: .utf8) ?? "", err: String(data: e, encoding: .utf8) ?? "")
    }
}

// MARK: - 단축키 저장·기록

extension ModuleDefaults {
    /// 저장된 전역 단축키 (없으면 기본값)
    func launchShortcut(_ name: String, default value: HotKeyCenter.Shortcut) -> HotKeyCenter.Shortcut {
        guard let d = data(name), let s = try? JSONDecoder().decode(HotKeyCenter.Shortcut.self, from: d) else { return value }
        return s
    }
    func setLaunchShortcut(_ s: HotKeyCenter.Shortcut?, _ name: String) {
        set(s.flatMap { try? JSONEncoder().encode($0) }, name)
    }
}

/// 설정 화면의 단축키 기록 버튼: 누른 뒤 수정키+키를 입력하면 저장한다.
struct LaunchShortcutRecorder: View {
    let current: HotKeyCenter.Shortcut
    let onChange: (HotKeyCenter.Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? T("키 입력…", "Press keys…") : current.display) {
            recording ? stop() : start()
        }
        .help(T("눌러서 새 단축키 기록", "Click to record a new shortcut"))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            var mods: UInt32 = 0
            if e.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            if e.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
            if e.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
            if e.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
            // 수정키 없는 단축키는 글자 입력을 가로채므로 받지 않는다
            guard mods != 0 else { return nil }
            onChange(HotKeyCenter.Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - 공통 동작 목록 (휠의 동작 고리, 수정키 탭 등이 같이 쓴다)

struct LaunchAction: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable { case app, url, shortcut, tab, snap }
    var id = UUID().uuidString
    var kind: Kind
    /// app: 번들 ID 또는 경로, url: 주소, shortcut: 단축어 이름, tab: 모듈 id, snap: 배치 이름
    var value: String
    var label: String

    var symbol: String {
        switch kind {
        case .app: return "app"
        case .url: return "link"
        case .shortcut: return "square.stack.3d.up"
        case .tab: return "rectangle.topthird.inset.filled"
        case .snap: return "rectangle.split.2x1"
        }
    }

    static func kindName(_ k: Kind) -> String {
        switch k {
        case .app: return T("앱 열기", "Open app")
        case .url: return T("링크 열기", "Open URL")
        case .shortcut: return T("단축어 실행", "Run Shortcut")
        case .tab: return T("탭 열기", "Open tab")
        case .snap: return T("창 배치", "Snap window")
        }
    }

    /// 사용자가 고른 동작을 실행한다 (사용자 입력으로만 불린다)
    func perform(context: ModuleContext?) {
        switch kind {
        case .app:
            if let url = LaunchApps.resolve(value) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                context?.notice(T("앱을 찾을 수 없음", "App not found"), label, symbol: "questionmark.app")
            }
        case .url:
            if let u = URL(string: value), u.scheme != nil { NSWorkspace.shared.open(u) }
        case .shortcut:
            LaunchShortcutRunner.run(name: value, context: context)
        case .tab:
            context?.openTab(value)
        case .snap:
            if let pos = WindowSnapPosition(rawValue: value) { WindowSnapper.snapFrontmost(pos, context: context) }
        }
    }
}

/// 단축어 실행 (사용자가 누른 경우에만)
enum LaunchShortcutRunner {
    static func run(name: String, context: ModuleContext?, completion: ((Bool, String) -> Void)? = nil) {
        let runner = LaunchProcess()
        runner.run("/usr/bin/shortcuts", ["run", name], timeout: 300) { r in
            _ = runner   // 끝날 때까지 붙잡아 둔다
            let ok = r.status == 0
            let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            completion?(ok, msg)
            if completion == nil, !ok {
                context?.notice(T("단축어 실패", "Shortcut failed"), "\(name)\(msg.isEmpty ? "" : " · " + String(msg.prefix(60)))",
                                symbol: "xmark.octagon", tint: .red)
            }
        }
    }
}

/// 앱 위치 해석: 번들 ID를 먼저 찾아 이름 변경·이동 뒤에도 동작한다.
enum LaunchApps {
    static func resolve(_ value: String) -> URL? {
        if !value.hasPrefix("/"), let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) { return u }
        if value.hasPrefix("/"), FileManager.default.fileExists(atPath: value) { return URL(fileURLWithPath: value) }
        return nil
    }

    static func name(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ value: String) -> NSImage? {
        resolve(value).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// 설정 화면: 동작 하나를 고르는 줄 (종류 + 값 + 이름 + 추가). 휠의 동작 고리와 수정키 탭이 같이 쓴다.
struct LaunchActionForm: View {
    var buttonTitle = T("추가", "Add")
    let onAdd: (LaunchAction) -> Void
    @State private var kind: LaunchAction.Kind = .url
    @State private var value = ""
    @State private var label = ""
    @State private var shortcutNames: [String] = []

    private var tabModules: [(String, String)] {
        ModuleRegistry.shared.modules.filter { $0.tabView() != nil }.map { ($0.id, $0.title) }
    }

    var body: some View {
        HStack {
            Picker("", selection: $kind) {
                ForEach([LaunchAction.Kind.url, .shortcut, .tab, .app, .snap], id: \.self) { Text(LaunchAction.kindName($0)).tag($0) }
            }
            .labelsHidden().frame(width: 130)
            .onChange(of: kind) { _, _ in value = "" }
            valueEditor
            TextField(T("이름", "Label"), text: $label).frame(width: 100)
            Button(buttonTitle) { add() }.disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            DispatchQueue.global().async {
                let r = LaunchProcess.runSync("/usr/bin/shortcuts", ["list"], timeout: 8)
                let names = r.out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                DispatchQueue.main.async { shortcutNames = names }
            }
        }
    }

    @ViewBuilder private var valueEditor: some View {
        switch kind {
        case .url: TextField("https://…", text: $value).frame(width: 170)
        case .shortcut:
            Picker("", selection: $value) {
                Text(T("단축어 고르기", "Choose")).tag("")
                ForEach(shortcutNames, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 170)
        case .tab:
            Picker("", selection: $value) {
                Text(T("탭 고르기", "Choose")).tag("")
                ForEach(tabModules, id: \.0) { Text($0.1).tag($0.0) }
            }.labelsHidden().frame(width: 170)
        case .app: TextField(T("번들 ID (예: com.apple.Safari)", "Bundle ID (com.apple.Safari)"), text: $value).frame(width: 170)
        case .snap:
            Picker("", selection: $value) {
                Text(T("배치 고르기", "Choose")).tag("")
                ForEach(WindowSnapPosition.allCases) { Text($0.title).tag($0.rawValue) }
            }.labelsHidden().frame(width: 170)
        }
    }

    private func add() {
        let v = value.trimmingCharacters(in: .whitespaces)
        if kind == .url, URL(string: v)?.scheme == nil { return }
        var name = label.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            switch kind {
            case .tab: name = tabModules.first { $0.0 == v }?.1 ?? v
            case .snap: name = WindowSnapPosition(rawValue: v)?.title ?? v
            case .app: name = LaunchApps.resolve(v).map(LaunchApps.name(of:)) ?? v
            case .url: name = URL(string: v)?.host ?? v
            case .shortcut: name = v
            }
        }
        onAdd(LaunchAction(kind: kind, value: v, label: name))
        value = ""; label = ""
    }
}
