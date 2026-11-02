import AppKit
import NaturalLanguage
import SwiftUI
import Translation

/// 다른 기능(선택 텍스트 동작 등)이 번역 탭에 넘길 글
enum TranslateShared {
    static var pendingText: String?
}

/// 번역 탭: Apple 기기 안 번역(macOS 15 이상, Translation 프레임워크). 글을 밖으로 보내지 않는다.
/// 원문 언어는 NaturalLanguage로 자동 감지, 입력하는 대로 갱신, 두 언어 쌍(원문이 대상 언어면 반대로).
final class TranslateModule: NotchModule {
    let id = "translate"
    var title: String { T("번역", "Translate") }
    let symbol = "character.bubble"
    var enabledByDefault: Bool { false }

    private var defaults: ModuleDefaults { ModuleDefaults(module: id) }
    fileprivate var context: ModuleContext?

    /// 대상 언어 (BCP-47, 예: "ko", "en")
    var target: String { defaults.string("target", default: L10n.isEnglish ? "en" : "ko") }
    /// 원문이 대상 언어와 같을 때 번역할 다른 언어
    var pairLanguage: String { defaults.string("pair", default: L10n.isEnglish ? "ko" : "en") }
    func setTarget(_ t: String) { defaults.set(t, "target") }
    func setPair(_ t: String) { defaults.set(t, "pair") }

    func start(context: ModuleContext) { self.context = context }
    func stop() { context = nil }

    func tabView() -> AnyView? {
        if #available(macOS 15.0, *) { return AnyView(TranslateTab(module: self)) }
        return AnyView(LaunchUnsupportedView(title: T("번역 지원 안 됨", "Translation unavailable"),
                                             reason: T("Apple 기기 안 번역은 macOS 15 이상에서만 쓸 수 있음", "Apple's on-device translation needs macOS 15 or later"),
                                             alternative: T("대안: macOS를 업데이트하거나 Safari의 번역 기능 사용", "Alternative: update macOS or use Safari's built-in translation"),
                                             symbol: "character.bubble"))
    }
    var tabContentSize: CGSize { CGSize(width: 500, height: 230) }
    func settingsView() -> AnyView? { AnyView(TranslateSettings(module: self)) }

    func paletteActions() -> [PaletteAction] {
        [PaletteAction(id: "translate.tab", title: T("번역 열기", "Open Translate"), symbol: symbol,
                       keywords: ["translate", "번역"]) { [weak self] in self?.context?.openTab("translate") }]
    }

    /// 감지한 원문 언어 (짧거나 애매하면 nil)
    static func detect(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(t)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first, p > 0.3 else { return r.dominantLanguage?.rawValue }
        return lang.rawValue
    }

    /// 감지 언어와 설정으로 대상 언어를 고른다
    func targetFor(source: String?) -> String {
        guard let source else { return target }
        return Self.base(source) == Self.base(target) ? pairLanguage : target
    }

    static func base(_ code: String) -> String { String(code.split(separator: "-").first ?? Substring(code)) }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// 자체 검사: 비동기 결과를 기다리는 동안 메인 런루프를 돌린다
    static func spin(until done: () -> Bool, timeout: TimeInterval) {
        let end = Date().addingTimeInterval(timeout)
        while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    static let common = ["ko", "en", "ja", "zh-Hans", "zh-Hant", "es", "fr", "de", "it", "pt", "ru", "vi", "th", "id", "ar", "hi", "tr", "nl", "pl", "uk"]

    func selfTest() -> [String] {
        var out: [String] = []
        for s in ["안녕하세요, 오늘 날씨가 좋네요.", "The quick brown fox jumps over the lazy dog.", "今日はいい天気ですね。", "Bonjour tout le monde", "Hola, ¿cómo estás?"] {
            let d = Self.detect(s)
            out.append("detect \(d ?? "nil") -> target \(targetFor(source: d)): \(s)")
        }
        guard #available(macOS 15.0, *) else {
            out.append("Translation framework: unavailable (macOS < 15) -> tab shows unsupported")
            return out
        }
        let pairs = [("ko", "en"), ("en", "ko"), ("ja", "ko")]
        var done = false
        var statuses: [String] = []
        Task.detached {
            let a = LanguageAvailability()
            for (s, t) in pairs {
                let st = await a.status(from: Locale.Language(identifier: s), to: Locale.Language(identifier: t))
                statuses.append("\(s)->\(t): \(st == .installed ? "installed" : st == .supported ? "supported (download needed)" : "unsupported")")
            }
            done = true
        }
        Self.spin(until: { done }, timeout: 10)
        if !done { out.append("availability: timed out") } else { out += statuses }
        if #available(macOS 26.0, *), statuses.first?.contains("installed") == true {
            var finished = false
            var result = "?"
            Task.detached {
                do {
                    let session = TranslationSession(installedSource: Locale.Language(identifier: "ko"), target: Locale.Language(identifier: "en"))
                    result = try await session.translate("안녕하세요, 오늘 날씨가 좋네요.").targetText
                } catch { result = "error: \(error.localizedDescription)" }
                finished = true
            }
            Self.spin(until: { finished }, timeout: 20)
            if !finished { result = "timed out" }
            out.append("on-device ko->en: \(result)")
        } else {
            out.append("on-device translation sample skipped (ko model not installed or macOS < 26)")
        }
        out.append("network used: no (Apple on-device Translation only)")
        return out
    }
}

@available(macOS 15.0, *)
private struct TranslateTab: View {
    let module: TranslateModule
    @State private var input = ""
    @State private var output = ""
    @State private var source: String?
    @State private var targetCode = "en"
    @State private var config: TranslationSession.Configuration?
    @State private var status = ""
    @State private var work: DispatchWorkItem?
    @State private var copied = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "character.bubble").font(.system(size: 12)).foregroundStyle(LaunchUI.secondary).padding(.top, 2)
                TextField(T("번역할 글", "Text to translate"), text: $input, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...3)
                    .focused($focused)
                if !input.isEmpty {
                    Button { input = ""; output = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(LaunchUI.secondary) }
                        .buttonStyle(.plain).help(T("지우기", "Clear")).accessibilityLabel(T("지우기", "Clear"))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LaunchUI.fill))

            HStack(spacing: 6) {
                Text(source.map { TranslateModule.name($0) } ?? T("자동 감지", "Detect"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(LaunchUI.secondary)
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(LaunchUI.secondary)
                Menu {
                    ForEach(TranslateModule.common, id: \.self) { c in
                        Button(TranslateModule.name(c)) {
                            module.setTarget(c)
                            schedule(immediate: true)
                        }
                    }
                } label: { Text(TranslateModule.name(targetCode)).font(.system(size: 11, weight: .medium)) }
                .menuStyle(.borderlessButton).fixedSize()
                .help(T("대상 언어", "Target language"))
                Spacer()
                LaunchChip(title: copied ? T("복사함", "Copied") : T("복사", "Copy"), symbol: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .disabled(output.isEmpty)
            }

            ScrollView {
                Text(output.isEmpty ? " " : output)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            Text(status.isEmpty ? T("기기 안에서 번역 · 글을 밖으로 보내지 않음", "Translated on this Mac · text never leaves it") : status)
                .font(.system(size: 10.5)).foregroundStyle(LaunchUI.secondary).lineLimit(1)
        }
        .foregroundStyle(.white)
        .translationTask(config) { session in
            let text = input
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                let r = try await session.translate(text)
                await MainActor.run {
                    if text == input { output = r.targetText }
                    status = ""
                }
            } catch {
                await MainActor.run { status = T("번역 실패: ", "Translation failed: ") + error.localizedDescription }
            }
        }
        .onChange(of: input) { _, _ in schedule(immediate: false) }
        .onAppear {
            targetCode = module.target
            if let t = TranslateShared.pendingText { input = t; TranslateShared.pendingText = nil }
            module.context?.focusInput()
            DispatchQueue.main.async { focused = true }
        }
    }

    /// 입력이 멈추면(0.35초) 언어를 감지해 번역을 다시 돌린다
    private func schedule(immediate: Bool) {
        work?.cancel()
        let w = DispatchWorkItem { run() }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.35), execute: w)
    }

    private func run() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { output = ""; source = nil; return }
        let detected = TranslateModule.detect(text)
        source = detected
        let t = module.targetFor(source: detected)
        targetCode = module.target
        let src = detected.map { Locale.Language(identifier: $0) }
        let dst = Locale.Language(identifier: t)
        Task {
            if let src {
                let st = await LanguageAvailability().status(from: src, to: dst)
                await MainActor.run {
                    switch st {
                    case .unsupported: status = T("이 언어 쌍은 Apple 번역이 지원하지 않음", "Apple Translation does not support this pair")
                    case .supported: status = T("언어 모델이 없어 macOS가 내려받기를 물어봄", "Language model missing: macOS will offer a download")
                    default: status = ""
                    }
                }
                if st == .unsupported { return }
            }
            await MainActor.run {
                if config?.source == src, config?.target == dst {
                    config?.invalidate()
                } else {
                    config = TranslationSession.Configuration(source: src, target: dst)
                }
            }
        }
    }
}

private struct TranslateSettings: View {
    let module: TranslateModule
    @State private var target = "ko"
    @State private var pair = "en"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(T("대상 언어", "Translate into"), selection: $target) {
                ForEach(TranslateModule.common, id: \.self) { Text(TranslateModule.name($0)).tag($0) }
            }
            .onChange(of: target) { _, v in module.setTarget(v) }
            Picker(T("원문이 대상 언어일 때", "When the text is already in that language"), selection: $pair) {
                ForEach(TranslateModule.common, id: \.self) { Text(TranslateModule.name($0)).tag($0) }
            }
            .onChange(of: pair) { _, v in module.setPair(v) }
            Text(T("Apple 기기 안 번역(macOS 15 이상)을 씁니다. 언어 모델이 없으면 macOS가 내려받기를 묻습니다. 글은 외부 서비스로 보내지 않습니다.",
                   "Uses Apple's on-device translation (macOS 15+). macOS asks before downloading a language model. Text is never sent to web services."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { target = module.target; pair = module.pairLanguage }
    }
}
