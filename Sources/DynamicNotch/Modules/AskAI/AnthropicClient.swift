import AppKit
import Foundation

/// Claude API(Messages) 요청 만들기·응답 읽기. Swift 공식 SDK가 없어 HTTP로 직접 보낸다.
/// 키는 요청 헤더에만 넣고 로그·오류 문구에 남기지 않는다.
enum AnthropicAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let defaultModel = "claude-sonnet-5-5"
    /// 생각(thinking)도 이 한도에 들어간다
    static let maxTokens = 16000
    static let keychainAccount = "askai.anthropicKey"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static let system = """
    You are answering inside a small macOS notch panel. Lead with the answer and keep it short: \
    a few sentences, or a few bullets when listing. Reply in the language the user writes in.
    """

    /// 거절 시 서버가 다른 모델로 다시 돌리는 기능 (Opus 5·Sonnet 5 계열만)
    static func usesFallbacks(_ model: String) -> Bool {
        model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-sonnet-5")
    }

    static func isValidModelID(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 80 && s.range(of: #"^[a-z0-9][a-z0-9.\-]*$"#, options: .regularExpression) != nil
    }

    /// 사용자 한 턴: (이미지) + 글
    static func userTurn(text: String, imagePNG: Data?, mediaType: String = "image/png") -> [String: Any] {
        var content: [[String: Any]] = []
        if let imagePNG {
            content.append(["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": imagePNG.base64EncodedString()]])
        }
        content.append(["type": "text", "text": text])
        return ["role": "user", "content": content]
    }

    static func body(model: String, messages: [[String: Any]]) -> [String: Any] {
        var b: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system, "messages": messages]
        if usesFallbacks(model) { b["fallbacks"] = "default" }
        return b
    }

    static func request(key: String, model: String, messages: [[String: Any]]) throws -> URLRequest {
        var r = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        if usesFallbacks(model) { r.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body(model: model, messages: messages))
        return r
    }

    struct Usage: Equatable {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        func cost(model: String) -> Double? {
            guard let p = ClaudePricing.price(for: model) else { return nil }
            let mt = 1_000_000.0
            return (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * p.cacheRead + Double(cacheWrite) * p.input * 1.25) / mt
        }
    }

    struct Reply {
        let text: String
        let stopReason: String
        let model: String
        let usage: Usage
        /// 다음 요청에 그대로 돌려줄 assistant 내용 (thinking 블록 포함, 손대지 않음)
        let rawContent: [Any]
        var truncated: Bool { stopReason == "max_tokens" }
    }

    enum APIError: LocalizedError, Equatable {
        case noKey, badKey, forbidden, badModel(String), rateLimited, overloaded, tooLarge, refused(String?), server(Int, String), network(String), malformed
        var errorDescription: String? {
            switch self {
            case .noKey: return T("API 키가 없습니다. 설정에서 입력하세요.", "No API key. Add one in Settings.")
            case .badKey: return T("API 키가 맞지 않습니다 (401). 설정에서 키를 확인하세요.", "The API key was rejected (401). Check it in Settings.")
            case .forbidden: return T("이 키로는 이 요청을 할 수 없습니다 (403).", "This key isn't allowed to make this request (403).")
            case .badModel(let m): return T("모델 id를 찾을 수 없습니다: \(m). 설정에서 고치세요.", "Model not found: \(m). Fix it in Settings.")
            case .rateLimited: return T("요청 한도에 걸렸습니다 (429). 잠시 뒤 다시 시도하세요.", "Rate limited (429). Try again shortly.")
            case .overloaded: return T("Anthropic 서버가 바쁩니다. 잠시 뒤 다시 시도하세요.", "Anthropic's servers are busy. Try again shortly.")
            case .tooLarge: return T("요청이 너무 큽니다. 이미지를 빼거나 새 대화를 시작하세요.", "The request is too large. Drop the image or start a new chat.")
            case .refused(let c): return T("모델이 답을 거절했습니다", "The model declined to answer") + (c.map { " (\($0))" } ?? "")
            case .server(let code, let msg): return "HTTP \(code): \(msg)"
            case .network(let m): return T("연결 실패: ", "Connection failed: ") + m
            case .malformed: return T("응답을 읽지 못했습니다", "Couldn't read the response")
            }
        }
    }

    static func parse(data: Data, status: Int, model: String) -> Result<Reply, APIError> {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            let msg = String(((json?["error"] as? [String: Any])?["message"] as? String ?? "").prefix(300))
            switch status {
            case 401: return .failure(.badKey)
            case 403: return .failure(.forbidden)
            case 404: return .failure(.badModel(model))
            case 413: return .failure(.tooLarge)
            case 429: return .failure(.rateLimited)
            case 500, 502, 503, 529: return .failure(.overloaded)
            default: return .failure(.server(status, msg.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : msg))
            }
        }
        guard let json, let content = json["content"] as? [Any] else { return .failure(.malformed) }
        let stop = json["stop_reason"] as? String ?? ""
        // 거절이면 내용을 읽기 전에 멈춘다
        if stop == "refusal" { return .failure(.refused((json["stop_details"] as? [String: Any])?["category"] as? String)) }
        let text = content.compactMap { $0 as? [String: Any] }.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        let u = json["usage"] as? [String: Any] ?? [:]
        let usage = Usage(input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0,
                          cacheRead: u["cache_read_input_tokens"] as? Int ?? 0, cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0)
        return .success(Reply(text: text, stopReason: stop, model: json["model"] as? String ?? model, usage: usage, rawContent: content))
    }

    /// 화면 캡처를 API에 맞게 줄인다 (긴 변 1568px 이하, 5MB 미만)
    static func prepareImage(_ data: Data) -> (data: Data, mediaType: String, size: CGSize)? {
        guard let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, 1568 / max(w, h))
        let nw = max(1, Int((w * scale).rounded())), nh = max(1, Int((h * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let scaled = ctx.makeImage() else { return nil }
        let out = NSBitmapImageRep(cgImage: scaled)
        if let png = out.representation(using: .png, properties: [:]), png.count < 3_500_000 { return (png, "image/png", CGSize(width: nw, height: nh)) }
        guard let jpg = out.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        return (jpg, "image/jpeg", CGSize(width: nw, height: nh))
    }
}
