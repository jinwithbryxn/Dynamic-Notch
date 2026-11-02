import AppKit
import ApplicationServices

/// 손쉬운 사용 요소 하나를 값으로 옮긴 것. 파싱은 이 값만 보고 하므로 가짜 트리로도 검사할 수 있다.
struct NMNode {
    var role = ""
    var subrole = ""
    var identifier = ""
    var title = ""
    var desc = ""
    var value = ""
    var actions: [String] = []
    var children: [NMNode] = []
    /// 실제 요소 (자체 검사용 트리에서는 nil)
    var element: AXUIElement? = nil
}

/// 누를 수 있는 동작 (요소 + 동작 이름)
struct NMAction {
    let element: AXUIElement
    let name: String
    @discardableResult
    func perform() -> Bool { AXUIElementPerformAction(element, name as CFString) == .success }
}

/// 배너 하나에서 읽은 내용
struct NMBanner {
    var appName = ""
    var title = ""
    var subtitle = ""
    var body = ""
    var isCall = false
    var element: AXUIElement? = nil
    var open: NMAction? = nil
    var close: NMAction? = nil
    var reply: NMAction? = nil
    /// 답장 동작이 보였는지 (자체 검사용 트리에서도 표시됨)
    var replySeen = false
    /// 시각 글자로 본 새 알림 여부: '지금'이면 true, '5분 전'·'오후 3:12'면 false, 시각 글자가 없으면 nil
    var isFresh: Bool? = nil

    var canReply: Bool { reply != nil }
    /// 같은 알림인지 가리는 값 (내용은 남기지 않고 해시만 쓴다)
    var signature: String {
        var h = Hasher()
        h.combine(appName); h.combine(title); h.combine(subtitle); h.combine(body)
        return String(h.finalize())
    }
    var isEmpty: Bool { title.isEmpty && body.isEmpty && subtitle.isEmpty }
}

/// 한 번 훑은 결과
struct NMScan {
    var banners: [NMBanner] = []
    /// 알림 센터 패널(목록·위젯)이 열려 있는 것으로 보이면 true. 이때는 미러링하지 않는다 (예전 배너 재생 방지).
    var panelOpen = false
}

/// macOS 알림 배너(NotificationCenter 프로세스)를 손쉬운 사용으로 읽는다.
/// 구조는 macOS 버전마다 달라서 여러 단서를 함께 본다:
/// ① subrole이 AXNotificationCenter…(Banner·Alert)인 요소, ② 닫기 동작이 있고 글자를 가진 묶음.
/// 글자는 식별자(title·subtitle·body)가 있으면 그것을, 없으면 정적 텍스트 순서와 설명(“앱, 제목, 본문”)을 쓴다.
enum NMBannerReader {
    static let bundleID = "com.apple.notificationcenterui"

    static let closeWords = ["close", "clear", "dismiss", "닫기", "지우기", "삭제"]
    static let replyWords = ["reply", "respond", "답장", "회신"]
    static let callWords = ["accept", "answer", "decline", "수락", "받기", "응답", "거절"]
    static let callContext = ["call", "facetime", "phone", "전화", "통화"]
    static let ignoredActions = ["options", "show details", "옵션", "세부사항", "자세히"]

    // MARK: 실제 요소 → 값

    static func notificationCenterPID() -> pid_t? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.processIdentifier
    }

    /// NotificationCenter 프로세스의 창(또는 최상위 자식)을 값 트리로 읽는다. 권한이 없으면 빈 배열.
    static func snapshot(pid: pid_t, maxNodes: Int = 600) -> [NMNode] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        var roots: [AXUIElement] = []
        for attr in [kAXWindowsAttribute, kAXChildrenAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &v) == .success, let list = v as? [AXUIElement] {
                for el in list where !roots.contains(where: { CFEqual($0, el) }) { roots.append(el) }
            }
        }
        var budget = maxNodes
        return roots.map { capture($0, depth: 0, budget: &budget) }
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        return ""
    }

    /// 요소 하나와 그 아래를 값 트리로 읽는다.
    static func snapshot(element: AXUIElement, maxNodes: Int = 300) -> NMNode {
        var budget = maxNodes
        return capture(element, depth: 0, budget: &budget)
    }

    private static func capture(_ el: AXUIElement, depth: Int, budget: inout Int) -> NMNode {
        budget -= 1
        var node = NMNode(element: el)
        node.role = string(el, kAXRoleAttribute)
        node.subrole = string(el, kAXSubroleAttribute)
        node.identifier = string(el, "AXIdentifier")
        node.title = string(el, kAXTitleAttribute)
        node.desc = string(el, kAXDescriptionAttribute)
        if node.role == kAXStaticTextRole as String || node.role == "AXTextArea" || node.role == "AXTextField" {
            node.value = string(el, kAXValueAttribute)
        }
        var names: CFArray?
        if AXUIElementCopyActionNames(el, &names) == .success { node.actions = (names as? [String]) ?? [] }
        guard depth < 14, budget > 0 else { return node }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children)
        for c in (children as? [AXUIElement]) ?? [] {
            guard budget > 0 else { break }
            node.children.append(capture(c, depth: depth + 1, budget: &budget))
        }
        return node
    }

    // MARK: 값 → 배너 (순수 함수)

    /// "Name:Close\nTarget:0x0\nSelector:(null)" → "close"
    static func actionLabel(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("Name:") { s.removeFirst(5) }
        if let nl = s.firstIndex(of: "\n") { s = String(s[..<nl]) }
        return s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// 한글은 포함 여부, 영어는 단어 단위
    static func matches(_ text: String, _ words: [String]) -> Bool {
        let t = text.lowercased()
        return words.contains { w in
            if w.range(of: "[a-z]", options: .regularExpression) == nil { return t.contains(w) }
            return t.range(of: "\\b\(NSRegularExpression.escapedPattern(for: w))\\b", options: .regularExpression) != nil
        }
    }

    private static func isBannerRole(_ n: NMNode) -> Bool {
        n.subrole.hasPrefix("AXNotificationCenter") && !n.subrole.contains("Stack") && !n.subrole.contains("Widget")
    }

    private static func customActions(_ n: NMNode) -> [String] {
        n.actions.filter { !$0.hasPrefix("AX") || $0.hasPrefix("Name:") }
    }

    private static func hasCloseAction(_ n: NMNode) -> Bool {
        customActions(n).contains { matches(actionLabel($0), closeWords) }
    }

    private static func hasText(_ n: NMNode) -> Bool {
        if n.role == kAXStaticTextRole as String, !n.value.isEmpty { return true }
        return n.children.contains { hasText($0) }
    }

    /// 트리에서 배너 묶음을 찾는다.
    static func parse(_ roots: [NMNode]) -> NMScan {
        var scan = NMScan()
        var widgetSeen = false
        func walk(_ n: NMNode) {
            let id = n.identifier.lowercased()
            if id.contains("widget") || n.subrole.contains("Widget") { widgetSeen = true }
            if isBannerRole(n) || (n.role == kAXGroupRole as String && hasCloseAction(n) && hasText(n)) {
                let b = banner(from: n)
                if !b.isEmpty { scan.banners.append(b) }
                return   // 배너 안쪽은 더 내려가지 않는다
            }
            n.children.forEach(walk)
        }
        roots.forEach(walk)
        // 위젯이 보이거나 한 번에 배너가 많으면 사용자가 알림 센터 목록을 연 것으로 본다
        scan.panelOpen = widgetSeen || scan.banners.count > 4
        return scan
    }

    /// 배너 묶음 하나에서 앱 이름·제목·본문·동작을 읽는다.
    static func banner(from root: NMNode) -> NMBanner {
        var b = NMBanner(element: root.element)
        var texts: [(id: String, value: String)] = []
        var buttons: [NMNode] = []
        var allLabels: [String] = []
        func walk(_ n: NMNode, depth: Int) {
            if depth > 0, isBannerRole(n) { return }
            if n.role == kAXStaticTextRole as String, !n.value.isEmpty {
                if isTimestamp(n) {
                    if b.isFresh == nil { b.isFresh = isNow(n.value) }
                } else {
                    texts.append((n.identifier.lowercased(), n.value.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            if n.role == kAXButtonRole as String { buttons.append(n) }
            allLabels.append(contentsOf: [n.title, n.desc, n.value, n.identifier] + customActions(n).map(actionLabel))
            n.children.forEach { walk($0, depth: depth + 1) }
        }
        walk(root, depth: 0)

        // 글자: 식별자 우선
        func byID(_ keys: [String]) -> String? { texts.first { t in keys.contains { t.id == $0 || t.id.hasSuffix($0) } }?.value }
        let titled = byID(["title"]), subtitled = byID(["subtitle"]), bodied = byID(["body", "message"])
        let appByID = byID(["appname", "app", "header"])
        if titled != nil || bodied != nil {
            b.title = titled ?? ""
            b.subtitle = subtitled ?? ""
            b.body = bodied ?? ""
        } else {
            let plain = texts.map(\.value).filter { !$0.isEmpty }
            switch plain.count {
            case 0: break
            case 1: b.title = plain[0]
            case 2: b.title = plain[0]; b.body = plain[1]
            default: b.title = plain[0]; b.subtitle = plain[1]; b.body = plain[2...].joined(separator: "\n")
            }
        }
        // 앱 이름: 식별자 → 설명 첫 칸("앱, 제목, 본문") → 이미지 설명
        if let a = appByID, a != b.title { b.appName = a }
        if b.appName.isEmpty { b.appName = appName(fromDescription: root.desc, title: b.title) ?? "" }
        if b.appName.isEmpty {
            b.appName = firstImageDescription(root).flatMap { $0 == b.title ? nil : $0 } ?? ""
        }
        if b.title.isEmpty, b.body.isEmpty, !root.desc.isEmpty {
            // 글자 요소가 없고 설명만 있는 구조: "앱, 제목, 본문"
            let parts = root.desc.components(separatedBy: ", ")
            if parts.count >= 3 { b.appName = parts[0]; b.title = parts[1]; b.body = parts[2...].joined(separator: ", ") }
            else if parts.count == 2 { b.appName = parts[0]; b.title = parts[1] }
        }

        // 동작: 배너 자체의 사용자 정의 동작 → 하위 버튼
        if let el = root.element {
            if root.actions.contains(kAXPressAction as String) { b.open = NMAction(element: el, name: kAXPressAction as String) }
            for raw in customActions(root) {
                let label = actionLabel(raw)
                if b.close == nil, matches(label, closeWords) { b.close = NMAction(element: el, name: raw) }
                if b.reply == nil, matches(label, replyWords) { b.reply = NMAction(element: el, name: raw) }
            }
        }
        if customActions(root).contains(where: { matches(actionLabel($0), replyWords) }) { b.replySeen = true }
        for btn in buttons {
            let label = [btn.title, btn.desc, btn.identifier].joined(separator: " ")
            if matches(label, replyWords) { b.replySeen = true }
            guard let el = btn.element else { continue }
            if b.close == nil, matches(label, closeWords) { b.close = NMAction(element: el, name: kAXPressAction as String) }
            if b.reply == nil, matches(label, replyWords) { b.reply = NMAction(element: el, name: kAXPressAction as String) }
        }
        // 전화·FaceTime 수신 배너는 기존 통화 기능이 맡는다
        let joined = allLabels.joined(separator: " ")
        b.isCall = matches(joined, callWords) && matches(joined, callContext)
        return b
    }

    /// "지금", "now", "5분 전", "3m ago", "오후 3:12" 같은 시각 글자
    static func isTimestamp(_ n: NMNode) -> Bool {
        let id = n.identifier.lowercased()
        if id.contains("date") || id.contains("time") { return true }
        let v = n.value.trimmingCharacters(in: .whitespaces).lowercased()
        if isNow(v) { return true }
        let patterns = [#"^\d+\s?(m|min|h|d)\s?ago$"#, #"^\d+\s?(분|시간|일)\s?전$"#,
                        #"^(오전|오후)?\s?\d{1,2}:\d{2}(\s?(am|pm))?$"#, #"^\d{1,2}:\d{2}\s?(am|pm)?$"#]
        return patterns.contains { v.range(of: $0, options: .regularExpression) != nil }
    }

    static func isNow(_ value: String) -> Bool {
        ["now", "지금", "방금", "just now"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// 설명이 "앱, 제목, …"이면 앱 이름을 돌려준다.
    static func appName(fromDescription desc: String, title: String) -> String? {
        let parts = desc.components(separatedBy: ", ")
        guard parts.count >= 2, let first = parts.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        if first == title { return nil }
        if !title.isEmpty, !desc.contains(title) { return nil }
        return first.count <= 40 ? first : nil
    }

    private static func firstImageDescription(_ n: NMNode) -> String? {
        if n.role == kAXImageRole as String, !n.desc.isEmpty { return n.desc }
        for c in n.children { if let d = firstImageDescription(c) { return d } }
        return nil
    }

    /// 요소가 아직 살아 있는지 (배너가 사라지면 false)
    static func isAlive(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v)
        return r == .success
    }
}
