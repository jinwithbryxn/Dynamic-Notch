import AppKit
import ApplicationServices

/// 개발용: 알림 센터 프로세스의 손쉬운 사용 구조를 글자 내용 없이 찍는다 (`--nm-dump[=<초>]`).
/// 역할·subrole·식별자·동작 이름과 위치·크기만 보이고, 글자·설명·제목은 길이만 남긴다.
/// 파서가 읽은 배너는 앱 이름과 글자 길이만 보인다.
enum NMDump {
    /// wait초 안에 배너가 보이면 그때의 구조를, 아니면 마지막 구조를 찍는다.
    static func run(wait: TimeInterval) -> [String] {
        guard AXIsProcessTrusted() else { return ["accessibility not trusted"] }
        guard let pid = NMBannerReader.notificationCenterPID() else { return ["NotificationCenter not running"] }
        let deadline = Date().addingTimeInterval(wait)
        var roots = NMBannerReader.snapshot(pid: pid)
        var scan = NMBannerReader.parse(roots)
        while scan.banners.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            roots = NMBannerReader.snapshot(pid: pid)
            scan = NMBannerReader.parse(roots)
        }
        var out = ["roots \(roots.count), banners \(scan.banners.count), panelOpen \(scan.panelOpen)"]
        for (i, r) in roots.enumerated() {
            describe(r, depth: 0, path: "\(i)", into: &out)
        }
        for b in scan.banners {
            out.append("banner app=\"\(b.appName)\" title=\(b.title.count) subtitle=\(b.subtitle.count) body=\(b.body.count) "
                       + "fresh=\(b.isFresh.map { "\($0)" } ?? "nil") reply=\(b.replySeen) call=\(b.isCall)")
        }
        return out
    }

    private static func describe(_ n: NMNode, depth: Int, path: String, into out: inout [String]) {
        guard out.count < 400 else { return }
        var parts = [n.role.replacingOccurrences(of: "AX", with: "")]
        if !n.subrole.isEmpty { parts.append("sub=\(n.subrole)") }
        if !n.identifier.isEmpty { parts.append("id=\(n.identifier)") }
        if !n.title.isEmpty { parts.append("title(\(n.title.count))") }
        if !n.desc.isEmpty { parts.append("desc(\(n.desc.count))") }
        if !n.value.isEmpty { parts.append("text(\(n.value.count))") }
        let actions = n.actions.filter { !$0.hasPrefix("AX") || $0.hasPrefix("Name:") }.map(NMBannerReader.actionLabel)
        if !actions.isEmpty { parts.append("actions=\(actions.joined(separator: "|"))") }
        if depth <= 2 || n.identifier.lowercased().contains("widget") || n.subrole.contains("Widget") {
            parts.append(frame(n.element))
        }
        out.append(String(repeating: "  ", count: depth) + path + " " + parts.joined(separator: " "))
        for (i, c) in n.children.enumerated() { describe(c, depth: depth + 1, path: "\(path).\(i)", into: &out) }
    }

    private static func frame(_ el: AXUIElement?) -> String {
        guard let el else { return "" }
        var p = CGPoint.zero, s = CGSize.zero
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &v) == .success, let v {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &v) == .success, let v {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        return "@\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height))"
    }
}
