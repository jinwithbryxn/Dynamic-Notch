import AppKit
import Carbon.HIToolbox
import SwiftUI

extension ModuleContext {
    /// 짧은 안내를 노치에 띄운다 (상세 카드로 잠깐 펼쳤다가 사라짐). tab을 주면 누를 때 그 탭을 연다.
    func notice(_ title: String, _ subtitle: String? = nil, symbol: String, tint: Color = .white,
                tab: String? = nil, duration: TimeInterval? = nil, actions: [ActivityAction] = []) {
        center.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail,
                                  duration: duration, symbol: symbol, tint: tint, title: title, subtitle: subtitle,
                                  moduleTab: tab, actions: actions))
    }
}

/// 여러 기능이 함께 쓰는 macOS 도우미: 이전 앱 기억과 붙여넣기, 딥링크.
enum ModuleServices {
    /// `dynamicnotch://` 링크 처리기. 기능이 start()에서 등록하고 stop()에서 지운다. 처리했으면 true.
    static var urlHandlers: [String: (URL) -> Bool] = [:]

    /// 앱이 받은 링크를 등록된 처리기에 차례로 넘긴다
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "dynamicnotch" else { return }
        for handler in urlHandlers.values where handler(url) { return }
    }

    /// 기능이 screencapture로 직접 찍기를 마쳤을 때 본 앱이 부르는 처리 (녹화 오감지 거두기).
    static var captureDidFinish: (() -> Void)?

    /// screencapture -i 같은 영역 선택이 끝나면 기능이 부른다 (찍었든 취소했든). 어느 스레드에서 불러도 된다.
    /// 스크린샷 폴더 밖 임시 파일로 찍으면 스크린샷 감지가 못 보므로, 영역 선택 화면을 녹화로 잘못 본 것을 여기서 거둔다.
    static func captureFinished() {
        DispatchQueue.main.async { captureDidFinish?() }
    }

    /// 노치에 입력하기 전 앞에 있던 앱 (이 앱 제외)
    private(set) static var previousApp: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    /// 본 앱 시작 시 한 번
    static func startTracking() {
        guard observer == nil else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me { previousApp = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != me else { return }
            previousApp = app
        }
    }

    /// 키 입력을 다른 앱에 보낼 수 있는지 (손쉬운 사용 권한)
    static var canPostKeys: Bool { AXIsProcessTrusted() }

    /// 글자를 클립보드에 넣고 이전 앱으로 돌아가 ⌘V를 보낸다.
    /// 손쉬운 사용 권한이 없으면 클립보드에만 넣고 false를 돌려준다.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pasteCurrentClipboard()
    }

    /// 이미 클립보드에 넣어 둔 내용을 이전 앱에 붙여넣는다.
    @discardableResult
    static func pasteCurrentClipboard() -> Bool {
        NSApp.keyWindow?.resignKey()
        previousApp?.activate()
        guard canPostKeys else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let v = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        return true
    }
}

/// 전역 단축키 (Carbon RegisterEventHotKey). 손쉬운 사용 권한 없이 동작한다.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Shortcut: Equatable, Codable {
        var keyCode: UInt32
        var modifiers: UInt32   // Carbon 수정키 (cmdKey, optionKey, controlKey, shiftKey)

        /// "⌃⌥K" 같은 표시
        var display: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + (Self.keyNames[keyCode] ?? "?")
        }

        static let keyNames: [UInt32: String] = {
            var m: [UInt32: String] = [:]
            let letters: [(Int, String)] = [
                (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
                (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
                (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
                (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
                (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
                (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
                (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
                (kVK_ANSI_9, "9"), (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_ANSI_Slash, "/"),
                (kVK_ANSI_Period, "."), (kVK_ANSI_Comma, ","), (kVK_ANSI_Semicolon, ";"),
            ]
            for (k, n) in letters { m[UInt32(k)] = n }
            return m
        }()
    }

    private var refs: [String: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var ids: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    /// 같은 id로 다시 등록하면 이전 단축키를 바꾼다. 다른 앱이 이미 쓰는 조합이면 false.
    @discardableResult
    func register(_ id: String, _ shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        installHandler()
        unregister(id)
        let num = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x444D4E48), id: num)   // 'DMNH'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        ids[id] = num
        handlers[num] = handler
        return true
    }

    func unregister(_ id: String) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        if let num = ids.removeValue(forKey: id) { handlers[num] = nil }
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let num = hk.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[num]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
