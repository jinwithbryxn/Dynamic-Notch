import AppKit
import ApplicationServices
import SwiftUI

// 캡처·개인정보 모듈들이 함께 쓰는 작은 도우미 (다른 모듈과 이름이 겹치지 않게 CP 접두어).

/// 권한 상태 읽기와 요청. 읽기는 프롬프트를 띄우지 않고, 요청은 사용자가 누른 동작에서만 부른다.
enum CPPermission: String {
    case accessibility, inputMonitoring, screenRecording

    var title: String {
        switch self {
        case .accessibility: return T("손쉬운 사용", "Accessibility")
        case .inputMonitoring: return T("입력 모니터링", "Input Monitoring")
        case .screenRecording: return T("화면 및 시스템 오디오 녹음", "Screen & System Audio Recording")
        }
    }

    /// 프롬프트 없이 현재 상태만 본다
    var granted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return CGPreflightListenEventAccess()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// 실행 중에 허용하면 앱을 다시 시작해야 반영되는 권한
    var needsRelaunch: Bool { self != .accessibility }

    /// 사용자 동작에서만 호출. 처음이면 시스템 창을 띄우고, 이미 거부했으면 시스템 설정을 연다.
    func request() {
        switch self {
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) { openSettings() }
        case .inputMonitoring:
            if !CGRequestListenEventAccess() { openSettings() }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings() }
        }
    }

    func openSettings() {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 탭에 보일 한 줄 ("손쉬운 사용: 허용됨")
    var statusLine: String {
        "\(title): " + (granted ? T("허용됨", "Allowed") : T("필요", "Needed"))
    }
}

/// 노치 안 작은 캡슐 버튼
struct CPPill: View {
    let symbol: String
    let title: String
    var tint: Color = .white
    var help: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(disabled ? 0.04 : 0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
        .disabled(disabled)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// 큰 아이콘 타일 버튼 (탭 첫 줄의 주요 동작)
struct CPTile: View {
    let symbol: String
    let title: String
    var tint: Color = .white
    var help: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                    .frame(height: 20)
                Text(title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(disabled ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
        .disabled(disabled)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// 켜고 끄는 한 줄 (노치 안)
struct CPToggleRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                .foregroundStyle(isOn ? Color.green : .white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "지원 안 됨 + 이유 + 대안" 상자
struct CPUnsupported: View {
    let title: String
    let reason: String
    var alternative: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(reason).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                if let alternative {
                    Text(T("대안: ", "Instead: ") + alternative).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 권한이 필요한 기능 앞에 붙는 한 줄 (허용 안 됐을 때만 버튼)
struct CPPermissionLine: View {
    let permission: CPPermission
    var granted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.seal.fill" : "lock.fill").font(.system(size: 10))
                .foregroundStyle(granted ? .green : .orange)
            Text(permission.title + " · " + (granted ? T("허용됨", "Allowed") : T("필요", "Needed")))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
            if !granted {
                Button(T("허용하기", "Allow")) { permission.request() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.blue)
                    .help(T("시스템 설정에서 이 앱을 허용", "Allow this app in System Settings"))
                if permission.needsRelaunch {
                    Text(T("(허용 후 앱 다시 시작)", "(relaunch after allowing)")).font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

/// 클릭이 통과하는 테두리 없는 오버레이 창
final class CPOverlayPanel: NSPanel {
    /// - hideFromCapture: true면 `sharingType = .none` (일부 화면 공유·녹화에서 빠지도록 시도, 완전한 보호 아님)
    init(frame: CGRect, level: NSWindow.Level, clickThrough: Bool, hideFromCapture: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        sharingType = hideFromCapture ? .none : .readOnly
    }

    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

enum CPLevel {
    /// 화면 보호기 층 (커서 강조·청소 화면)
    static let overlay = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue)
    /// 메뉴 막대 위, 노치 패널(mainMenu+3) 바로 아래 (텔레프롬프터·창 지켜보기)
    static let belowNotch = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
}

/// 일반 창(편집기 등)을 띄우고 닫힐 때까지 잡아 둔다
final class CPWindowKeeper: NSObject, NSWindowDelegate {
    static let shared = CPWindowKeeper()
    private var windows: [NSWindow] = []
    private var onClose: [ObjectIdentifier: () -> Void] = [:]

    func show(_ window: NSWindow, onClose: (() -> Void)? = nil) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        windows.append(window)
        if let onClose { self.onClose[ObjectIdentifier(window)] = onClose }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        onClose.removeValue(forKey: ObjectIdentifier(w))?()
        windows.removeAll { $0 === w }
    }

}

/// 이미지 클립보드·파일 도우미
enum CPImageIO {
    /// 스크린샷 미리보기(본 앱 기능)가 이 복사를 '새 스크린샷'으로 잡지 않게 붙이는 표식 형식
    static let markerType = NSPasteboard.PasteboardType("com.dynamicnotch.module-image")

    static func copy(_ image: CGImage) {
        guard let png = pngData(image) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, markerType], owner: nil)
        pb.setData(png, forType: .png)
        pb.setData(Data(), forType: markerType)
    }

    static func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
    }

    static func clipboardImage() -> CGImage? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first, let img = load(first) { return img }
        return nil
    }

    /// 같은 이름이 있으면 " 2", " 3"을 붙인다
    static func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// 원본 옆 사본 경로 (원본이 없으면 스크린샷 저장 위치)
    static func siblingURL(for source: URL?, suffix: String) -> URL {
        if let source {
            let base = source.deletingPathExtension().lastPathComponent + " " + suffix
            return uniqueURL(in: source.deletingLastPathComponent(), base: base, ext: "png")
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return uniqueURL(in: RecordingMonitor.saveFolder(), base: "\(suffix) \(f.string(from: Date()))", ext: "png")
    }

    @discardableResult
    static func savePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = pngData(image) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 이미지 파일 고르기 (사용자 동작)
    static func pickImage(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = message
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// 짧은 외부 명령 실행 (끝나면 메인 스레드로 종료 코드)
enum CPProcess {
    @discardableResult
    static func run(_ path: String, _ args: [String], completion: ((Int32) -> Void)? = nil) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { completion?(code) }
        }
        do { try p.run() } catch {
            DispatchQueue.main.async { completion?(-1) }
            return nil
        }
        return p
    }
}

/// 비공개 함수 찾기 (없으면 nil → 지원 안 됨으로 떨어진다)
enum CPPrivate {
    static func symbol(_ name: String, in paths: [String]) -> UnsafeMutableRawPointer? {
        for path in paths {
            if let h = dlopen(path, RTLD_LAZY), let s = dlsym(h, name) { return s }
        }
        return nil
    }

    static let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
}

extension NSScreen {
    /// 화면 번호 (CGDirectDisplayID)
    var cpDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 마우스가 있는 화면
    static var cpUnderMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }
}

/// 앞에 있지 않은 패널에서도 첫 클릭이 바로 버튼에 닿게 한다
final class CPHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 편집기 창: 앱 메뉴가 없어도 글자 칸에서 ⌘X·C·V·A·Z가 되게 한다 (글자 칸이 아니면 화면의 단축키로 넘긴다)
final class CPEditorWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleEditing(event) { return }
        super.sendEvent(event)
    }

    private func handleEditing(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let responder = firstResponder, responder is NSText else { return false }
        let action: Selector
        // 키 위치로 판단 (한글 입력 중에도 동작)
        switch (event.keyCode, flags.contains(.shift)) {
        case (7, false): action = #selector(NSText.cut(_:))
        case (8, false): action = #selector(NSText.copy(_:))
        case (9, false): action = #selector(NSText.paste(_:))
        case (0, false): action = #selector(NSText.selectAll(_:))
        case (6, false): action = Selector(("undo:"))
        case (6, true): action = Selector(("redo:"))
        default: return false
        }
        return responder.tryToPerform(action, with: self)
    }
}
