import AppKit
import SwiftUI

final class AskAIModel: ObservableObject {
    enum Role { case user, assistant, error }
    struct Turn: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        var hasImage = false
        var note: String?
    }
    struct PendingImage {
        let data: Data
        let mediaType: String
        let size: CGSize
        let preview: NSImage
    }

    @Published var draft = ""
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var sending = false
    @Published private(set) var pendingImage: PendingImage?
    @Published private(set) var confirmingImage = false
    @Published private(set) var capturing = false
    @Published private(set) var captureNote: String?
    @Published private(set) var lastUsage: (usage: AnthropicAPI.Usage, model: String)?
    @Published private(set) var conversationCost: Double = 0
    @Published private(set) var hasKey = false

    /// API에 보내는 대화 (덧붙이기만 한다. assistant 내용은 받은 그대로)
    private(set) var messages: [[String: Any]] = []
    private var task: URLSessionDataTask?
    private var capture: Process?
    private var generation = 0

    var session = URLSession(configuration: .ephemeral)
    var loadKey: () -> String? = { KeychainStore.get(AnthropicAPI.keychainAccount) }
    var modelID: () -> String = {
        let m = ModuleDefaults(module: "askai").string("model", default: AnthropicAPI.defaultModel)
        return AnthropicAPI.isValidModelID(m) ? m : AnthropicAPI.defaultModel
    }

    func refreshKey() { hasKey = loadKey().map { !$0.isEmpty } ?? false }

    /// 보내기. 이미지가 붙어 있으면 한 번 더 눌러 확인해야 보낸다.
    func send() {
        guard !sending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }
        if pendingImage != nil, !confirmingImage { confirmingImage = true; return }
        confirmingImage = false
        guard let key = loadKey(), !key.isEmpty else {
            turns.append(Turn(role: .error, text: AnthropicAPI.APIError.noKey.localizedDescription))
            hasKey = false
            return
        }
        let model = modelID()
        let question = text.isEmpty ? T("이 화면을 설명해 주세요.", "Explain this screenshot.") : text
        let image = pendingImage
        let outgoing = messages + [AnthropicAPI.userTurn(text: question, imagePNG: image?.data, mediaType: image?.mediaType ?? "image/png")]
        let request: URLRequest
        do { request = try AnthropicAPI.request(key: key, model: model, messages: outgoing) } catch {
            turns.append(Turn(role: .error, text: AnthropicAPI.APIError.malformed.localizedDescription))
            return
        }
        turns.append(Turn(role: .user, text: question, hasImage: image != nil))
        draft = ""
        pendingImage = nil
        sending = true
        generation &+= 1
        let gen = generation
        let finish: (Data?, URLResponse?, Error?) -> Void = { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(gen, outgoing: outgoing, model: model, data: data, response: response, error: error) }
        }
        let t = session.dataTask(with: request) { data, response, error in finish(data, response, error) }
        task = t
        t.resume()
    }

    private func finish(_ gen: Int, outgoing: [[String: Any]], model: String, data: Data?, response: URLResponse?, error: Error?) {
        guard gen == generation else { return }
        sending = false
        task = nil
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { turns.append(Turn(role: .error, text: T("멈춤", "Stopped"))); return }
            turns.append(Turn(role: .error, text: AnthropicAPI.APIError.network(error.localizedDescription).localizedDescription))
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch AnthropicAPI.parse(data: data ?? Data(), status: status, model: model) {
        case .success(let reply):
            // 다음 질문에 그대로 돌려준다 (thinking 블록 포함)
            messages = outgoing + [["role": "assistant", "content": reply.rawContent]]
            let note = reply.truncated ? T("답이 길어 중간에 잘림", "The answer was cut off at the length limit") : nil
            turns.append(Turn(role: .assistant, text: reply.text.isEmpty ? T("(빈 답)", "(empty answer)") : reply.text, note: note))
            lastUsage = (reply.usage, reply.model)
            conversationCost += reply.usage.cost(model: reply.model) ?? 0
        case .failure(let e):
            // 실패한 질문은 대화에 넣지 않는다
            turns.append(Turn(role: .error, text: e.localizedDescription))
            if e == .badKey || e == .noKey { refreshKey() }
        }
    }

    func stopSending() { task?.cancel() }

    func newConversation() {
        generation &+= 1
        task?.cancel()
        task = nil
        sending = false
        messages = []
        turns = []
        conversationCost = 0
        lastUsage = nil
        confirmingImage = false
    }

    func removeImage() { pendingImage = nil; confirmingImage = false }
    func cancelImageConfirm() { confirmingImage = false }

    func attach(_ raw: Data) -> Bool {
        guard let p = AnthropicAPI.prepareImage(raw) else { return false }
        pendingImage = PendingImage(data: p.data, mediaType: p.mediaType, size: p.size, preview: NSImage(data: p.data) ?? NSImage())
        confirmingImage = false
        return true
    }

    /// 사용자가 누를 때만: 노치를 접고 screencapture -i로 영역을 고르게 한다. 보내기 전엔 아무 데도 안 간다.
    func captureScreen(collapse: @escaping () -> Void, reopen: @escaping () -> Void) {
        guard !capturing else { return }
        capturing = true
        captureNote = nil
        collapse()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-askai-\(UUID().uuidString).png")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", "-t", "png", url.path]
            let done: () -> Void = { [weak self] in
                DispatchQueue.main.async {
                    let data = try? Data(contentsOf: url)
                    try? FileManager.default.removeItem(at: url)
                    guard let self else { return }
                    self.capture = nil
                    self.capturing = false
                    if let data, !data.isEmpty {
                        if !self.attach(data) { self.captureNote = T("캡처를 읽지 못했습니다", "Couldn't read the capture") }
                    } else {
                        self.captureNote = T("캡처를 취소했습니다", "Capture cancelled")
                    }
                    reopen()
                }
            }
            p.terminationHandler = { _ in done() }
            do {
                try p.run()
                self.capture = p
            } catch {
                self.capturing = false
                self.captureNote = error.localizedDescription
                reopen()
            }
        }
    }

    func stop() {
        newConversation()
        if let c = capture, c.isRunning { c.terminate() }
        capture = nil
        capturing = false
        pendingImage = nil
    }
}

/// Claude에게 묻기 (M-K-013) + 화면 영역 묻기 (M-K-015).
/// 사용자의 Anthropic API 키(키체인)로 api.anthropic.com에 보낸다. 사용자가 쓴 글과 확인한 이미지만 보낸다.
final class AskAIModule: NotchModule {
    let id = "askai"
    var title: String { T("Claude에게 묻기", "Ask Claude") }
    let symbol = "bubble.left.and.text.bubble.right"
    var enabledByDefault: Bool { false }

    let model = AskAIModel()
    private var context: ModuleContext?

    func start(context: ModuleContext) {
        self.context = context
        model.refreshKey()
    }

    func stop() {
        model.stop()
        context = nil
    }

    func settingsChanged() { model.refreshKey() }

    func tabView() -> AnyView? {
        AnyView(AskAITab(model: model,
                         focus: { [weak self] in self?.context?.focusInput() },
                         capture: { [weak self] in
                             guard let self, let ctx = self.context else { return }
                             self.model.captureScreen(collapse: ctx.collapse, reopen: { ctx.openTab("askai") })
                         }))
    }
    var tabContentSize: CGSize { CGSize(width: 600, height: 290) }

    func paletteActions() -> [PaletteAction] {
        guard let ctx = context else { return [] }
        return [
            PaletteAction(id: "askai.open", title: T("Claude에게 묻기", "Ask Claude"), subtitle: T("API 키 사용 · 유료", "Uses your API key · billed"), symbol: symbol, keywords: ["claude", "ai", "질문", "ask"]) { ctx.openTab("askai") },
            PaletteAction(id: "askai.screen", title: T("화면 영역을 Claude에게 묻기", "Ask Claude About a Screen Area"), subtitle: T("영역을 고른 뒤 확인해야 보냅니다", "Sent only after you confirm"), symbol: "viewfinder", keywords: ["screenshot", "캡처", "화면"]) { [weak self] in
                self?.model.captureScreen(collapse: ctx.collapse, reopen: { ctx.openTab("askai") })
            },
        ]
    }

    func settingsView() -> AnyView? { AnyView(AskAISettings()) }
    func selfTest() -> [String] { AskAISelfTest.run() }
}

private struct AskAITab: View {
    @ObservedObject var model: AskAIModel
    let focus: () -> Void
    let capture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !model.hasKey && model.turns.isEmpty {
                AIDevUnsupported(title: T("Anthropic API 키가 없습니다", "No Anthropic API key"),
                                 reason: T("설정 > Claude에게 묻기에 키(sk-ant-…)를 넣으면 여기서 바로 물어볼 수 있습니다. 사용료는 Claude 구독(Pro·Max)과 별도로 API 계정에 청구됩니다.",
                                           "Add a key (sk-ant-…) in Settings > Ask Claude to ask from here. Usage is billed to your API account, separately from a Claude subscription (Pro, Max)."),
                                 alternative: T("무료 대안: 'AI 글 다듬기'(온디바이스)", "Free alternative: AI Text Tools (on device)"))
                Spacer(minLength: 0)
            } else {
                conversation
                if let img = model.pendingImage { imageRow(img) }
                if model.confirmingImage { confirmRow }
                inputRow
                footer
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 11, weight: .semibold))
            Text(T("Claude에게 묻기", "Ask Claude")).font(.system(size: 12, weight: .semibold))
            Text(model.modelID()).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            if model.conversationCost > 0 {
                Text(T("이번 대화 약 \(AIDevFormat.usd(model.conversationCost))", "This chat ≈ \(AIDevFormat.usd(model.conversationCost))")).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            }
            if !model.turns.isEmpty {
                AIDevPill(title: T("새 대화", "New Chat"), symbol: "square.and.pencil") { model.newConversation() }
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if model.turns.isEmpty {
                        Text(T("질문을 보내면 입력한 글(과 확인한 화면 이미지)만 Anthropic API로 갑니다. 같은 대화의 이전 질문과 답도 함께 보냅니다.",
                               "Type a question and send. Only what you typed (and a screen image you confirm) goes to the Anthropic API, along with earlier turns of this chat."))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                    }
                    ForEach(model.turns) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if model.sending {
                        Text(T("Claude가 생각하는 중…", "Claude is thinking…")).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5)).id("sending")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.turns.count) { _, _ in
                withAnimation { proxy.scrollTo(model.sending ? AnyHashable("sending") : AnyHashable(model.turns.last?.id), anchor: .bottom) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder private func bubble(_ t: AskAIModel.Turn) -> some View {
        switch t.role {
        case .user:
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: t.hasImage ? "photo" : "person.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).padding(.top, 2)
                Text(t.text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 3) {
                Text(t.text).font(.system(size: 12)).textSelection(.enabled)
                HStack(spacing: 6) {
                    if let n = t.note { Text(n).font(.system(size: 10)).foregroundStyle(.orange) }
                    Button { AIDevPasteboard.copy(t.text) } label: { Label(T("복사", "Copy"), systemImage: "doc.on.doc").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.leading, 15)
        case .error:
            Label(t.text, systemImage: "exclamationmark.triangle").font(.system(size: 11.5)).foregroundStyle(.orange)
        }
    }

    private func imageRow(_ img: AskAIModel.PendingImage) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: img.preview).resizable().aspectRatio(contentMode: .fit).frame(height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(T("화면 이미지 \(Int(img.size.width))×\(Int(img.size.height)) · \(img.data.count / 1024) KB · 보내기 전까지 이 Mac에만 있음",
                   "Screen image \(Int(img.size.width))×\(Int(img.size.height)) · \(img.data.count / 1024) KB · stays on this Mac until you send"))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            Spacer()
            AIDevPill(title: T("빼기", "Remove"), symbol: "xmark") { model.removeImage() }
        }
    }

    private var confirmRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.shield").font(.system(size: 11)).foregroundStyle(.yellow)
            Text(T("이 이미지와 질문을 api.anthropic.com으로 보냅니다 (유료). 민감한 내용이 없는지 확인하세요.",
                   "This image and question go to api.anthropic.com (billed). Check the image has nothing sensitive."))
                .font(.system(size: 10.5)).lineLimit(2)
            Spacer()
            AIDevPill(title: T("보내기", "Send"), symbol: "paperplane.fill", role: .primary) { model.send() }
            AIDevPill(title: T("취소", "Cancel")) { model.cancelImageConfirm() }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField(T("Claude에게 물어보기…", "Ask Claude…"), text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                .onSubmit { model.send() }
                .onTapGesture { focus() }
                .disabled(model.sending)
            AIDevPill(title: model.capturing ? T("고르는 중…", "Selecting…") : T("화면 영역", "Screen Area"), symbol: "viewfinder",
                      help: CGPreflightScreenCaptureAccess() ? T("영역을 골라 첨부 (보내기 전 확인)", "Select an area to attach (confirmed before sending)")
                                                            : T("처음에는 화면 기록 권한을 묻습니다. 허용하지 않으면 배경만 찍힙니다.", "macOS asks for Screen Recording the first time. Without it only the wallpaper is captured.")) { capture() }
                .disabled(model.capturing || model.sending)
            if model.sending {
                AIDevPill(title: T("멈추기", "Stop"), symbol: "stop.fill") { model.stopSending() }
            } else {
                AIDevPill(title: T("보내기", "Send"), symbol: "paperplane.fill", role: .primary) { model.send() }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.pendingImage == nil)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let note = model.captureNote {
                Text(note).foregroundStyle(.orange)
                Text("·")
            }
            if let u = model.lastUsage {
                Text(T("마지막 답: 입력 \(AIDevFormat.tokens(u.usage.input + u.usage.cacheRead + u.usage.cacheWrite)) · 출력 \(AIDevFormat.tokens(u.usage.output))",
                       "Last answer: in \(AIDevFormat.tokens(u.usage.input + u.usage.cacheRead + u.usage.cacheWrite)) · out \(AIDevFormat.tokens(u.usage.output))"))
                if let c = u.usage.cost(model: u.model) { Text("· ≈ \(AIDevFormat.usd(c))") }
                Text("·")
            }
            Text(T("API 사용료는 Claude 구독과 별도 청구", "API usage is billed separately from a Claude subscription"))
            Spacer(minLength: 0)
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.white.opacity(0.45))
        .lineLimit(1)
    }
}

private struct AskAISettings: View {
    @State private var keyInput = ""
    @State private var stored = KeychainStore.get(AnthropicAPI.keychainAccount).map(AskAISettings.mask)
    @State private var modelText = ModuleDefaults(module: "askai").string("model", default: AnthropicAPI.defaultModel)
    @State private var confirmRemove = false

    static func mask(_ key: String) -> String { "sk-ant-…" + key.suffix(4) }

    var body: some View {
        Form {
            Section(T("Anthropic API 키", "Anthropic API key")) {
                HStack {
                    SecureField(T("sk-ant-로 시작하는 키", "Key starting with sk-ant-"), text: $keyInput)
                    Button(T("저장", "Save")) {
                        let k = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !k.isEmpty, KeychainStore.set(k, for: AnthropicAPI.keychainAccount) else { return }
                        stored = Self.mask(k)
                        keyInput = ""
                        ModuleDefaults(module: "askai").set(Int(Date().timeIntervalSince1970), "keyVersion")
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !keyInput.isEmpty, !keyInput.hasPrefix("sk-ant-") {
                    Text(T("Anthropic 키는 보통 sk-ant-로 시작합니다.", "Anthropic keys usually start with sk-ant-.")).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text(stored.map { T("저장됨: \($0)", "Saved: \($0)") } ?? T("저장된 키 없음", "No key saved")).foregroundStyle(.secondary)
                    Spacer()
                    if stored != nil {
                        Button(T("키 지우기", "Remove Key"), role: .destructive) { confirmRemove = true }
                    }
                }
                .confirmationDialog(T("API 키를 지울까요?", "Remove the API key?"), isPresented: $confirmRemove) {
                    Button(T("지우기", "Remove"), role: .destructive) {
                        KeychainStore.set(nil, for: AnthropicAPI.keychainAccount)
                        stored = nil
                        ModuleDefaults(module: "askai").set(Int(Date().timeIntervalSince1970), "keyVersion")
                    }
                }
            }
            Section(T("모델", "Model")) {
                TextField(T("모델 id", "Model id"), text: $modelText)
                    .onSubmit {
                        let m = modelText.trimmingCharacters(in: .whitespaces)
                        if AnthropicAPI.isValidModelID(m) { ModuleDefaults(module: "askai").set(m == AnthropicAPI.defaultModel ? nil : m, "model") }
                    }
                if !AnthropicAPI.isValidModelID(modelText.trimmingCharacters(in: .whitespaces)) {
                    Text(T("모델 id 형식이 아닙니다. 기본값 \(AnthropicAPI.defaultModel)을 사용합니다.", "Not a model id. Using the default \(AnthropicAPI.defaultModel).")).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("요금: API 사용료는 Claude 구독(Pro·Max)과 별개로 이 키의 Anthropic 콘솔 계정에 청구됩니다. 노치에 답마다 토큰 수와 추정 요금이 표시됩니다.",
                           "Billing: API usage is charged to this key's Anthropic Console account, separately from a Claude subscription (Pro, Max). The notch shows tokens and an estimated cost per answer."))
                    Text(T("보내는 내용: 노치에 입력한 질문, 같은 대화의 이전 질문과 답, '화면 영역'으로 고른 뒤 확인한 이미지뿐입니다. 받는 곳은 api.anthropic.com 하나입니다.",
                           "What is sent: the question you type, earlier turns of the same chat, and a screen area image only after you confirm it. The only endpoint is api.anthropic.com."))
                    Text(T("키는 이 Mac의 키체인에만 저장되고 로그나 설정 파일에 남지 않습니다.", "The key is kept only in this Mac's Keychain, never in logs or settings files."))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
