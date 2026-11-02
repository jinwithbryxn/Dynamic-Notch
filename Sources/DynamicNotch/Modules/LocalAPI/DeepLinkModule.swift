import AppKit
import SwiftUI

/// 딥링크·단축어 연동 (M-K-027): `dynamicnotch://show?title=…&message=…&duration=…`
/// 글자만 띄운다 (명령 실행·파일 열기 없음). 제목 120자, 메시지 500자, 1–10초, 잠금 해제 중에만.
/// 단축어 앱의 "URL 열기" 동작으로도 쓸 수 있다.
///
/// 본 앱 연결(통합 담당): Info.plist에 CFBundleURLTypes(스킴 "dynamicnotch")를 넣고,
/// AppDelegate `application(_:open:)`에서 `DeepLinkModule.handle(url)`을 부른다.
final class DeepLinkModule: NotchModule {
    let id = "deeplink"
    var title: String { T("딥링크 알림", "Deep Link Messages") }
    let symbol = "link"
    var enabledByDefault: Bool { false }

    static let scheme = "dynamicnotch"
    /// 켜져 있는 모듈 (본 앱에 하나)
    private static weak var running: DeepLinkModule?
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        Self.running = self
    }

    func stop() {
        context = nil
        if Self.running === self { Self.running = nil }
    }

    func settingsView() -> AnyView? { AnyView(DeepLinkSettings()) }

    /// AppDelegate에서 부른다. 처리했으면 true.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let module = running, let context = module.context else { return false }
        guard let activity = activity(for: url, locked: isScreenLocked()) else { return false }
        context.center.post(activity)
        return true
    }

    /// 링크를 안내 카드로 바꾼다. 형식이 틀리거나 잠금 중이면 nil.
    static func activity(for url: URL, locked: Bool) -> NotchActivity? {
        guard !locked,
              url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "show",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = comps.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let title = LocalAPIModule.clean(q("title"), limit: 120)
        guard !title.isEmpty else { return nil }
        let message = LocalAPIModule.clean(q("message"), limit: 500)
        let duration = min(10, max(1, Double(q("duration") ?? "") ?? 4))
        return NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail, duration: duration,
                             symbol: "link", tint: .white, title: title, subtitle: message.isEmpty ? nil : message)
    }

    /// 화면 잠금 중인지 (CGSession 사전)
    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    static var example: String { "\(scheme)://show?title=Hello&message=Ready&duration=4" }

    func selfTest() -> [String] {
        func t(_ s: String, locked: Bool = false) -> NotchActivity? { URL(string: s).flatMap { Self.activity(for: $0, locked: locked) } }
        var out: [String] = []
        let ok = t("dynamicnotch://show?title=Hello&message=Ready&duration=3")
        out.append("\(ok?.title == "Hello" && ok?.subtitle == "Ready" && ok?.duration == 3 ? "PASS" : "FAIL") basic link")
        let long = t("dynamicnotch://show?title=\(String(repeating: "a", count: 300))&duration=99")
        out.append("\((long?.title?.count ?? 0) == 121 && long?.duration == 10 ? "PASS" : "FAIL") title capped at 120 (+…), duration capped at 10")
        out.append("\(t("dynamicnotch://show?message=x") == nil ? "PASS" : "FAIL") title required")
        out.append("\(t("dynamicnotch://run?title=x") == nil ? "PASS" : "FAIL") other actions rejected")
        out.append("\(t("notchy://show?title=x") == nil ? "PASS" : "FAIL") other schemes rejected")
        out.append("\(t("dynamicnotch://show?title=x", locked: true) == nil ? "PASS" : "FAIL") ignored while locked")
        let ctl = t("dynamicnotch://show?title=a%0Ab%07c")
        out.append("\(ctl?.title == "a bc" ? "PASS" : "FAIL") control characters removed (\(ctl?.title ?? "nil"))")
        out.append("screen locked now: \(Self.isScreenLocked())")
        let registered = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])?
            .contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(Self.scheme) == true } ?? false
        out.append("Info.plist URL scheme registered: \(registered) (needs integrator change if false)")
        return out
    }
}

private struct DeepLinkSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("단축어나 링크로 노치에 짧은 글을 띄웁니다. 글자만 표시하고 명령 실행·파일 열기는 하지 않습니다. 화면이 잠겨 있으면 무시합니다.",
                   "Shortcuts or links can show a short message in the notch. Text only — no commands or files. Ignored while the screen is locked."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(DeepLinkModule.example).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button(T("예시 복사", "Copy Example")) { AIDevPasteboard.copy(DeepLinkModule.example) }
            }
            Text(T("단축어 앱: 'URL 열기' 동작에 위 링크를 넣으세요. 제목 120자, 메시지 500자, 1–10초.",
                   "Shortcuts app: put the link in an 'Open URL' action. Title 120 chars, message 500 chars, 1–10 s."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
