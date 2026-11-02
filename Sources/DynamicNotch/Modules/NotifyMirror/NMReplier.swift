import AppKit
import ApplicationServices

/// 배너 답장 결과. 실패를 성공으로 보이지 않는다.
enum NMReplyOutcome: Equatable {
    case sent
    case notSent(String)
}

/// 알림 배너의 답장 동작으로 노치에서 직접 답장한다 (손쉬운 사용).
/// 모든 조작은 NotificationCenter 프로세스 안의 요소에만 한다 → 다른 앱 창에 글자를 넣지 않는다.
/// 순서: 답장 동작 → 입력 칸 찾기 → 값 넣고 다시 읽어 확인 → 보내기 버튼(없으면 확인 동작) → 칸이 닫혔는지 확인.
enum NMReplier {
    static let sendWords = ["send", "보내기", "전송"]

    static func send(_ text: String, root: AXUIElement, reply: NMAction, pid: pid_t,
                     completion: @escaping (NMReplyOutcome) -> Void) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { completion(.notSent(T("보낼 글자가 없음", "Nothing to send"))); return }
        guard AXIsProcessTrusted() else { completion(.notSent(T("손쉬운 사용 권한 없음", "No Accessibility permission"))); return }
        guard NMBannerReader.isAlive(root) else { completion(.notSent(T("배너가 이미 사라짐", "The banner is gone"))); return }
        guard reply.perform() else { completion(.notSent(T("답장 동작을 실행하지 못함", "Could not open the reply field"))); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let field = findField(root: root, pid: pid) else {
                completion(.notSent(T("답장 입력 칸을 찾지 못함", "Reply field not found"))); return
            }
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success,
                  readValue(field) == text else {
                completion(.notSent(T("입력 칸에 글자를 넣지 못함", "Could not fill the reply field"))); return
            }
            if let button = findSend(root: root, pid: pid) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            } else if actions(of: field).contains("AXConfirm") {
                AXUIElementPerformAction(field, "AXConfirm" as CFString)
            } else {
                completion(.notSent(T("보내기 버튼을 찾지 못함", "Send button not found"))); return
            }
            // 칸이 닫히거나 비워지면 보낸 것으로 본다
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !NMBannerReader.isAlive(field) || (readValue(field) ?? "").isEmpty {
                    completion(.sent)
                } else {
                    completion(.notSent(T("전송을 확인하지 못함", "Could not confirm sending")))
                }
            }
        }
    }

    private static func readValue(_ el: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success else { return nil }
        return (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actions(of el: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(el, &names)
        return (names as? [String]) ?? []
    }

    /// 배너 안 → NotificationCenter 창 전체 순으로 글자 입력 칸을 찾는다.
    private static func findField(root: AXUIElement, pid: pid_t) -> AXUIElement? {
        func search(_ n: NMNode) -> AXUIElement? {
            if n.role == "AXTextArea" || n.role == "AXTextField", let el = n.element { return el }
            for c in n.children { if let f = search(c) { return f } }
            return nil
        }
        if let f = search(NMBannerReader.snapshot(element: root)) { return f }
        for w in NMBannerReader.snapshot(pid: pid) { if let f = search(w) { return f } }
        return nil
    }

    private static func findSend(root: AXUIElement, pid: pid_t) -> AXUIElement? {
        func search(_ n: NMNode) -> AXUIElement? {
            if n.role == kAXButtonRole as String, let el = n.element,
               NMBannerReader.matches([n.title, n.desc, n.identifier].joined(separator: " "), sendWords) { return el }
            for c in n.children { if let f = search(c) { return f } }
            return nil
        }
        if let b = search(NMBannerReader.snapshot(element: root)) { return b }
        for w in NMBannerReader.snapshot(pid: pid) { if let b = search(w) { return b } }
        return nil
    }
}
