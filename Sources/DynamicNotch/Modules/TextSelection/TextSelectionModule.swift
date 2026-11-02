import AppKit
import SwiftUI

/// 선택한 글에 맞는 추가 버튼 (링크·메일·전화·수식·JSON)
enum TextSelectionSmart: Equatable {
    case link(URL), email(String), phone(String), math(String), json(String)

    static let trackingParams: Set<String> = ["fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "igshid", "mc_cid", "mc_eid",
                                              "yclid", "_hsenc", "_hsmi", "mkt_tok", "ref_src", "ref_url", "spm", "vero_id", "oly_enc_id", "oly_anon_id"]

    /// 추적용 파라미터(utm_* 등)를 뺀 주소
    static func cleaned(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = c.queryItems else { return url }
        let host = url.host?.lowercased() ?? ""
        let kept = items.filter { q in
            let n = q.name.lowercased()
            if n.hasPrefix("utm_") || trackingParams.contains(n) { return false }
            if n == "si", host.contains("youtu") || host.contains("spotify") { return false }
            return true
        }
        c.queryItems = kept.isEmpty ? nil : kept
        return c.url ?? url
    }

    static func detect(_ raw: String) -> [TextSelectionSmart] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [TextSelectionSmart] = []
        if let u = LaunchSystem.webURL(from: t) { out.append(.link(cleaned(u))) }
        if t.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil { out.append(.email(t)) }
        if t.count <= 30, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue),
           let m = det.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), m.range.length >= t.utf16.count - 2, let p = m.phoneNumber {
            out.append(.phone(p))
        }
        // 전화번호·날짜(010-1234-5678, 2026-11-02)는 뺄셈으로 보지 않는다
        let dashed = t.range(of: #"^\d+(-\d+){2,}$"#, options: .regularExpression) != nil
        let hasPhone = out.contains { if case .phone = $0 { return true }; return false }
        if t.count <= 200, !dashed, !hasPhone, CalcEngine.looksLikeMath(t), let v = CalcEngine.evaluate(t) { out.append(.math(CalcEngine.format(v, grouping: false))) }
        if let first = t.first, first == "{" || first == "[", let d = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: pretty, encoding: .utf8) {
            out.append(.json(s))
        }
        return out
    }
}

/// 선택 텍스트 동작: 드래그·더블·트리플 클릭으로 글을 고르면 그 위에 복사·검색·사전·번역 막대를 띄운다.
/// 손쉬운 사용 권한으로 선택한 글만 읽는다. 보안 입력·버튼·⌘드래그는 무시하고 PopClip 실행 중엔 숨는다. 기본 꺼짐.
final class TextSelectionModule: NotchModule {
    let id = "textactions"
    var title: String { T("선택 텍스트 동작", "Text Actions") }
    let symbol = "text.cursor"
    var enabledByDefault: Bool { false }

    fileprivate var context: ModuleContext?
    private var monitors: [Any] = []
    private var downPoint: CGPoint = .zero
    private var downCommand = false
    private var bar: TextActionBar?
    private var hideWork: DispatchWorkItem?
    private var axWait: Timer?

    func start(context: ModuleContext) {
        self.context = context
        install()
    }

    func stop() {
        axWait?.invalidate()
        axWait = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hideBar()
        context = nil
    }

    func settingsChanged() { if context != nil { install() } }

    private func install() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        guard LaunchSystem.axTrusted else {
            // 권한이 허용되면 시작한다 (10초마다 확인만, 요청 창은 띄우지 않음)
            if axWait == nil {
                axWait = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] t in
                    guard LaunchSystem.axTrusted else { return }
                    t.invalidate()
                    self?.axWait = nil
                    self?.install()
                }
            }
            return
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown], handler: { [weak self] e in
            self?.handle(e)
        }) { monitors.append(m) }
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            downPoint = NSEvent.mouseLocation
            downCommand = e.modifierFlags.contains(.command)
            if let bar, !bar.frame.contains(downPoint) { hideBar() }
        case .leftMouseUp:
            let up = NSEvent.mouseLocation
            let dragged = hypot(up.x - downPoint.x, up.y - downPoint.y) > 6
            guard !downCommand, dragged || e.clickCount >= 2 else { return }
            // 앱이 선택을 반영할 시간을 잠깐 준다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.readSelection(at: up) }
        case .scrollWheel, .keyDown:
            hideBar()
        default: break
        }
    }

    private func readSelection(at point: CGPoint) {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.pilotmoon.popclip" }) { return }
        guard let text = Self.selectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        showBar(text: String(text.prefix(5000)), at: point)
    }

    /// 앞 앱에서 포커스된 요소의 선택한 글. 보안 입력·버튼·슬라이더는 읽지 않는다.
    static func selectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref) == .success, let ref else { return nil }
        let el = ref as! AXUIElement
        var role: CFTypeRef?, sub: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &sub)
        let r = role as? String ?? "", s = sub as? String ?? ""
        if s == (kAXSecureTextFieldSubrole as String) || r == "AXSecureTextField" { return nil }
        if [kAXButtonRole as String, kAXSliderRole as String, kAXScrollBarRole as String].contains(r) { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &sel) == .success else { return nil }
        return sel as? String
    }

    private func showBar(text: String, at point: CGPoint) {
        hideBar()
        let actions = barActions(for: text)
        let b = TextActionBar(actions: actions) { [weak self] in self?.hideBar() }
        bar = b
        b.show(near: point)
        let w = DispatchWorkItem { [weak self] in self?.hideBar() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
    }

    private func hideBar() {
        hideWork?.cancel()
        hideWork = nil
        bar?.orderOut(nil)
        bar = nil
    }

    struct BarAction: Identifiable { let id: String; let title: String; let symbol: String; let run: () -> Void }

    func barActions(for text: String) -> [BarAction] {
        func copy(_ s: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s, forType: .string)
        }
        var out = [
            BarAction(id: "copy", title: T("복사", "Copy"), symbol: "doc.on.doc") { copy(text) },
            BarAction(id: "search", title: T("검색", "Search"), symbol: "magnifyingglass") {
                if let r = QuickSearchModule().resolve(text) { NSWorkspace.shared.open(r.url) }
            },
        ]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60, let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let u = URL(string: "dict://" + enc) {
            out.append(BarAction(id: "dict", title: T("사전", "Look Up"), symbol: "character.book.closed") { NSWorkspace.shared.open(u) })
        }
        out.append(BarAction(id: "translate", title: T("번역", "Translate"), symbol: "character.bubble") { [weak self] in
            TranslateShared.pendingText = text
            if ModuleRegistry.shared.running.contains("translate") { self?.context?.openTab("translate") }
            else { self?.context?.notice(T("번역 기능이 꺼져 있음", "Translate is off"), T("설정 > 확장 기능에서 번역 켜기", "Turn on Translate in Settings"), symbol: "character.bubble") }
        })
        for s in TextSelectionSmart.detect(text) {
            switch s {
            case .link(let u): out.append(BarAction(id: "link", title: T("링크 열기", "Open Link"), symbol: "link") { NSWorkspace.shared.open(u) })
            case .email(let m):
                if let u = URL(string: "mailto:" + m) { out.append(BarAction(id: "mail", title: T("메일 쓰기", "New Email"), symbol: "envelope") { NSWorkspace.shared.open(u) }) }
            case .phone(let p):
                let digits = p.filter { $0.isNumber || $0 == "+" }
                if let u = URL(string: "tel:" + digits) { out.append(BarAction(id: "tel", title: T("전화", "Call"), symbol: "phone") { NSWorkspace.shared.open(u) }) }
            case .math(let v): out.append(BarAction(id: "math", title: "= \(v)", symbol: "equal") { copy(v) })
            case .json(let j): out.append(BarAction(id: "json", title: T("JSON 정리 복사", "Copy Formatted"), symbol: "curlybraces") { copy(j) })
            }
        }
        return out
    }

    func settingsView() -> AnyView? {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            if !LaunchSystem.axTrusted {
                HStack {
                    Text(T("선택한 글을 읽으려면 손쉬운 사용 권한이 필요합니다.", "Reading selected text needs Accessibility access."))
                    Button(T("권한 요청", "Request access")) { LaunchSystem.requestAX() }
                }
            }
            Text(T("드래그·더블·트리플 클릭으로 글을 고르면 복사·검색·사전·번역 막대가 뜹니다. 링크·메일·전화·수식·JSON이면 버튼이 더 붙습니다. 보안 입력, ⌘드래그는 무시하고 PopClip 실행 중엔 숨습니다. 번역은 기기 안 번역 탭으로 넘깁니다.",
                   "Select text by dragging or double/triple-clicking to get Copy, Search, Look Up and Translate. Links, emails, phone numbers, math and JSON add a button. Secure fields and ⌘-drag are ignored; hidden while PopClip runs. Translate hands off to the on-device Translate tab."))
                .font(.caption).foregroundStyle(.secondary)
        })
    }

    func selfTest() -> [String] {
        var out = ["accessibility trusted: \(LaunchSystem.axTrusted) (mouse monitor installed only while enabled and trusted)"]
        let samples = ["https://example.com/a?utm_source=x&id=7&fbclid=abc", "hello@example.com", "010-1234-5678", "12*(3+4)",
                       "{\"b\":1,\"a\":[1,2]}", "그냥 문장입니다", "https://youtu.be/abc?si=track&t=10"]
        for s in samples {
            let d = TextSelectionSmart.detect(s).map { k -> String in
                switch k {
                case .link(let u): return "link \(u.absoluteString)"
                case .email: return "email"
                case .phone(let p): return "phone \(p)"
                case .math(let v): return "math \(v)"
                case .json(let j): return "json \(j.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: ""))"
                }
            }
            out.append("\(s) -> \(d.isEmpty ? "copy/search/look up/translate only" : d.joined(separator: "; "))")
        }
        out.append("bar actions for 'hello': \(barActions(for: "hello").map(\.id).joined(separator: ","))")
        out.append("selection read in self test: no")
        return out
    }
}

/// 선택한 글 위에 뜨는 작은 막대 (앱을 앞으로 가져오지 않음)
final class TextActionBar: NSPanel {
    init(actions: [TextSelectionModule.BarAction], onDone: @escaping () -> Void) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        let root = HStack(spacing: 4) {
            ForEach(actions) { a in
                LaunchChip(title: a.title, symbol: a.symbol) { a.run(); onDone() }
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.layoutSubtreeIfNeeded()
        contentView = host
        setContentSize(host.fittingSize)
    }

    /// 선택 위쪽(공간이 없으면 아래)에 띄운다
    func show(near p: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        var origin = CGPoint(x: p.x - frame.width / 2, y: p.y + 14)
        if origin.y + frame.height > vf.maxY { origin.y = p.y - frame.height - 14 }
        origin.x = max(vf.minX + 4, min(origin.x, vf.maxX - frame.width - 4))
        setFrameOrigin(origin)
        orderFrontRegardless()
    }
}
