import AppKit
import Foundation

/// 네트워크 대신 응답을 돌려주는 가짜 연결 (검사 전용). 이 세션의 요청은 밖으로 안 나간다.
final class AskAIStubProtocol: URLProtocol {
    static var reply: (Int, String) = (200, "{}")
    static var seen: [(request: URLRequest, body: [String: Any])] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
        }
        Self.seen.append((request, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]))
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.reply.0, httpVersion: "HTTP/1.1", headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum AskAISelfTest {
    static func run() -> [String] {
        var out: [String] = []
        func check(_ ok: Bool, _ what: String) { out.append("\(ok ? "PASS" : "FAIL") \(what)") }
        let dummy = "sk-ant-api03-SELFTEST-DUMMY-not-a-real-key"
        out.append("no Anthropic API call is made: requests go to an in-process stub, the real Keychain is not read")

        // 1) 요청 만들기
        let msgs = [AnthropicAPI.userTurn(text: "안녕", imagePNG: nil)]
        if let r = try? AnthropicAPI.request(key: dummy, model: "claude-sonnet-5-5", messages: msgs),
           let body = r.httpBody.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            check(r.url?.absoluteString == "https://api.anthropic.com/v1/messages" && r.httpMethod == "POST", "POST https://api.anthropic.com/v1/messages")
            check(r.value(forHTTPHeaderField: "x-api-key") == dummy && r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21" && r.value(forHTTPHeaderField: "content-type") == "application/json",
                  "headers x-api-key, anthropic-version 2026-10-21, content-type")
            check(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01" && body["fallbacks"] as? String == "default", "sonnet-5-5 opts into fallbacks \"default\" with its beta header")
            check(body["model"] as? String == "claude-sonnet-5-5" && body["max_tokens"] as? Int == 16000 && body["temperature"] == nil && body["top_p"] == nil && body["thinking"] == nil,
                  "body: model, max_tokens 16000, no sampling params, default thinking")
            let content = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
            check(content.count == 1 && content[0]["type"] as? String == "text" && content[0]["text"] as? String == "안녕", "only the typed text is in the user turn")
        } else { out.append("FAIL request build") }
        if let r = try? AnthropicAPI.request(key: dummy, model: "claude-haiku-5-5", messages: msgs), let body = r.httpBody.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            check(r.value(forHTTPHeaderField: "anthropic-beta") == nil && body["fallbacks"] == nil, "haiku-5-5 sends no fallbacks")
        }
        check(AnthropicAPI.isValidModelID("claude-opus-5-5") && !AnthropicAPI.isValidModelID("claude opus") && !AnthropicAPI.isValidModelID(""), "model id validation")

        // 2) 응답 읽기
        let ok = #"{"model":"claude-sonnet-5-5","stop_reason":"end_turn","content":[{"type":"thinking","thinking":"","signature":"sig-abc"},{"type":"text","text":"답입니다"}],"usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":0}}"#
        if case .success(let rep) = AnthropicAPI.parse(data: Data(ok.utf8), status: 200, model: "claude-sonnet-5-5") {
            check(rep.text == "답입니다" && rep.rawContent.count == 2, "reads text blocks by type and keeps the raw content (thinking block included)")
            check(abs((rep.usage.cost(model: rep.model) ?? 0) - 0.007) < 0.000001, "cost estimate 1000 in + 500 out on sonnet-5-5 = $0.007")
        } else { out.append("FAIL parse success") }
        let refusal = #"{"stop_reason":"refusal","stop_details":{"category":"cyber"},"content":[{"type":"text","text":"partial"}],"usage":{}}"#
        check(AnthropicAPI.parse(data: Data(refusal.utf8), status: 200, model: "m").failureValue == .refused("cyber"), "refusal is handled before reading content (category cyber)")
        let cut = #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"long"}],"usage":{}}"#
        check((try? AnthropicAPI.parse(data: Data(cut.utf8), status: 200, model: "m").get().truncated) == true, "max_tokens is flagged as cut off")
        let e401 = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        check(AnthropicAPI.parse(data: Data(e401.utf8), status: 401, model: "m").failureValue == .badKey && AnthropicAPI.parse(data: Data(), status: 429, model: "m").failureValue == .rateLimited
              && AnthropicAPI.parse(data: Data(), status: 529, model: "m").failureValue == .overloaded && AnthropicAPI.parse(data: Data(), status: 404, model: "claude-x").failureValue == .badModel("claude-x"),
              "401, 429, 529 and 404 map to clear messages")

        // 3) 대화 흐름 (가짜 연결)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [AskAIStubProtocol.self]
        let m = AskAIModel()
        m.session = URLSession(configuration: cfg)
        m.modelID = { "claude-sonnet-5-5" }
        var key: String? = nil
        m.loadKey = { key }
        AskAIStubProtocol.seen = []
        m.draft = "질문 하나"
        m.send()
        check(AskAIStubProtocol.seen.isEmpty && m.turns.last?.role == .error && m.draft == "질문 하나", "no key: nothing is sent and the draft stays")
        key = dummy
        AskAIStubProtocol.reply = (200, ok)
        m.send()
        _ = AIDevTest.wait(3) { !m.sending }
        check(m.turns.last?.text == "답입니다" && m.messages.count == 2 && AskAIStubProtocol.seen.count == 1, "first turn: answer shown, conversation has 2 messages")
        m.draft = "두 번째"
        m.send()
        _ = AIDevTest.wait(3) { !m.sending }
        let second = AskAIStubProtocol.seen.last?.body["messages"] as? [[String: Any]] ?? []
        let assistantBlocks = second.count > 1 ? (second[1]["content"] as? [[String: Any]] ?? []) : []
        check(second.count == 3 && assistantBlocks.first?["type"] as? String == "thinking" && assistantBlocks.first?["signature"] as? String == "sig-abc",
              "second turn sends the earlier assistant content back unchanged (thinking + signature)")
        AskAIStubProtocol.reply = (401, e401)
        m.draft = "세 번째"
        m.send()
        _ = AIDevTest.wait(3) { !m.sending }
        check(m.messages.count == 4 && m.turns.last?.role == .error, "a failed turn is not added to the conversation")
        AskAIStubProtocol.reply = (200, refusal)
        m.draft = "네 번째"
        m.send()
        _ = AIDevTest.wait(3) { !m.sending }
        check(m.messages.count == 4 && m.turns.last?.text.contains("cyber") == true, "a refusal shows the category and is not added")
        check(!m.turns.contains { $0.text.contains(dummy) }, "the key never appears in the notch text")

        // 4) 화면 이미지: 줄이기 + 한 번 더 확인해야 보냄
        let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4000, pixelsHigh: 2000, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = big.representation(using: .png, properties: [:])!
        let attached = m.attach(png)
        check(attached && m.pendingImage?.size == CGSize(width: 1568, height: 784), "a 4000x2000 capture is scaled to 1568x784 (\(m.pendingImage.map { "\($0.data.count / 1024) KB \($0.mediaType)" } ?? "-"))")
        AskAIStubProtocol.reply = (200, ok)
        let before = AskAIStubProtocol.seen.count
        m.draft = "이 화면 뭐야"
        m.send()
        check(m.confirmingImage && AskAIStubProtocol.seen.count == before, "with an image the first Send only asks for confirmation")
        m.send()
        _ = AIDevTest.wait(3) { !m.sending }
        let imgTurn = (AskAIStubProtocol.seen.last?.body["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]] ?? []
        check(AskAIStubProtocol.seen.count == before + 1 && imgTurn.first?["type"] as? String == "image" && (imgTurn.first?["source"] as? [String: Any])?["type"] as? String == "base64" && imgTurn.last?["text"] as? String == "이 화면 뭐야",
              "after confirming, the image block goes first and the typed question last")
        m.stop()
        check(m.messages.isEmpty && m.turns.isEmpty && m.pendingImage == nil, "stop() clears the conversation and the pending image")
        return out
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let f) = self { return f }; return nil }
}
