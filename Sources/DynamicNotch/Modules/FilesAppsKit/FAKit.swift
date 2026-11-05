import AppKit
import SwiftUI

/// 파일 도구·드라이브·패키지·설정 백업 기능이 함께 쓰는 도우미.
/// 다른 기능과 이름이 겹치지 않게 모든 형식에 FA 접두사를 붙인다.
enum FAKit {
    /// "1.2 MB" 같은 용량 표시
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// 파일 하나의 크기 (폴더는 0)
    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// 폴더면 안의 파일을 모두 더한 디스크 사용량. 읽을 수 없으면 nil.
    static func allocatedSize(_ url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var failed = false
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                     errorHandler: { _, _ in failed = true; return true }) else { return nil }
        var total: Int64 = 0
        for case let child as URL in e {
            let v = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return failed && total == 0 ? nil : total
    }

    /// 심볼릭 링크까지 포함해 그 경로에 무언가 있는지
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// 같은 이름이 있으면 Finder처럼 "이름 2.확장자"를 찾는다 (덮어쓰지 않기 위해).
    static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        func make(_ name: String) -> URL {
            ext.isEmpty ? dir.appendingPathComponent(name) : dir.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var url = make(base)
        var n = 2
        while exists(url) {
            url = make("\(base) \(n)")
            n += 1
        }
        return url
    }

    /// 데이터를 새 파일로 쓴다. 이미 있으면 다음 이름으로 (절대 덮어쓰지 않음).
    static func writeNew(_ data: Data, in dir: URL, base: String, ext: String) throws -> URL {
        var lastError: Error?
        for _ in 0..<5 {
            let url = uniqueURL(in: dir, base: base, ext: ext)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch {
                lastError = error
                if !exists(url) { break }   // 이름 충돌이 아닌 실패(권한 등)
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    /// 임시 파일을 새 이름으로 옮긴다. 같은 이름이 있으면 다음 이름으로 (moveItem은 덮어쓰지 않음).
    static func moveNew(_ file: URL, in dir: URL, base: String, ext: String) throws -> URL {
        var lastError: Error?
        for _ in 0..<5 {
            let url = uniqueURL(in: dir, base: base, ext: ext)
            do {
                try FileManager.default.moveItem(at: file, to: url)
                return url
            } catch {
                lastError = error
                if !exists(url) { break }
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// 홈 폴더를 ~로 줄인 경로
    static func shortPath(_ url: URL) -> String {
        let p = url.path, h = home.path
        return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
    }
}

// MARK: - 외부 프로그램 실행

/// 외부 프로그램 한 번 실행한 결과
struct FAProcessResult {
    let status: Int32
    let out: Data
    let err: Data
    var outText: String { String(decoding: out, as: UTF8.self) }
    var errText: String { String(decoding: err, as: UTF8.self) }
    var ok: Bool { status == 0 }
}

/// 기능 하나가 띄운 외부 프로그램 묶음. 기능을 끄면 `terminateAll()`로 모두 멈춘다.
final class FAProcessGroup {
    private var running: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    var hasRunning: Bool { lock.lock(); defer { lock.unlock() }; return !running.isEmpty }

    /// 끝날 때까지 기다리는 실행 (백그라운드 스레드에서 부른다). 실행하지 못하면 nil.
    func run(_ path: String, _ args: [String], env: [String: String] = [:], timeout: TimeInterval = 120,
             currentDirectory: URL? = nil) -> FAProcessResult? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let currentDirectory { p.currentDirectoryURL = currentDirectory }
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        add(p)
        defer { remove(p) }
        // 표준 오류는 따로 읽어야 큰 출력에서 파이프가 막히지 않는다
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        watchdog.cancel()
        return FAProcessResult(status: p.terminationStatus, out: outData, err: errData)
    }

    /// 줄 단위로 출력을 받는 실행 (설치·업그레이드 로그). 콜백은 메인 스레드.
    @discardableResult
    func stream(_ path: String, _ args: [String], env: [String: String] = [:],
                onLine: @escaping (String) -> Void, onExit: @escaping (Int32) -> Void) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        p.standardInput = FileHandle.nullDevice   // 비대화식: 비밀번호를 물으면 바로 실패한다
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buffer = Data()
        let bufferLock = NSLock()
        func flush(final: Bool) {
            bufferLock.lock()
            var lines: [String] = []
            while let nl = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            }
            if final, !buffer.isEmpty {
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll()
            }
            bufferLock.unlock()
            if !lines.isEmpty { DispatchQueue.main.async { lines.forEach(onLine) } }
        }
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            bufferLock.lock(); buffer.append(d); bufferLock.unlock()
            flush(final: false)
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            if let rest = try? pipe.fileHandleForReading.readToEnd() {
                bufferLock.lock(); buffer.append(rest); bufferLock.unlock()
            }
            flush(final: true)
            self?.remove(proc)
            let status = proc.terminationStatus
            DispatchQueue.main.async { onExit(status) }
        }
        do { try p.run() } catch { return nil }
        add(p)
        return p
    }

    func terminateAll() {
        lock.lock()
        let list = Array(running.values)
        lock.unlock()
        for p in list where p.isRunning { p.terminate() }
    }

    private func add(_ p: Process) { lock.lock(); running[ObjectIdentifier(p)] = p; lock.unlock() }
    private func remove(_ p: Process) { lock.lock(); running[ObjectIdentifier(p)] = nil; lock.unlock() }
}

// MARK: - 노치 안 화면 조각

/// 작은 캡슐 버튼 (노치 안: 검은 배경, 흰 글자)
struct FAPillStyle: ButtonStyle {
    enum Tone { case normal, primary, destructive }
    var tone: Tone = .normal

    func makeBody(configuration: Configuration) -> some View {
        FAPillBody(configuration: configuration, tone: tone)
    }
}

private struct FAPillBody: View {
    let configuration: ButtonStyle.Configuration
    let tone: FAPillStyle.Tone
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    private var fill: Color {
        switch tone {
        case .normal: return .white
        case .primary: return .accentColor
        case .destructive: return .red
        }
    }

    var body: some View {
        configuration.label
            .font(.island(.footnote))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
            .background(Capsule().fill(fill.opacity(tone == .normal
                ? (configuration.isPressed ? 0.28 : hover ? 0.2 : 0.13)
                : (configuration.isPressed ? 0.7 : hover ? 0.6 : 0.45))))
            .contentShape(Capsule())
            .onHover { hover = $0 && enabled }
    }
}

/// 둥근 회색 구역 배경
struct FACard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// 지원 안 됨 + 이유 + 대안
struct FAUnsupportedView: View {
    let symbol: String
    let title: String
    let reason: String
    var alternative: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.island(.title1)).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.island(.subhead, .semibold))
            Text(reason).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            if let alternative {
                Text(alternative).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(FAPillStyle()).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

/// 파일 아이콘 (Finder와 같은 그림)
struct FAFileIcon: View {
    let url: URL
    var size: CGFloat = 18
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - 팝업 메뉴

/// 마우스 위치에 뜨는 작은 메뉴 (변환 형식·용량 고르기). SwiftUI Menu보다 노치 안 모양을 맞추기 쉽다.
enum FAMenu {
    struct Entry {
        let title: String
        var enabled: Bool
        let run: () -> Void
        init(title: String, enabled: Bool = true, run: @escaping () -> Void) {
            self.title = title
            self.enabled = enabled
            self.run = run
        }
    }

    static func popUp(_ entries: [Entry]) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for e in entries {
            let item = FAMenuItem(title: e.title, handler: e.run)
            item.isEnabled = e.enabled
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class FAMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
