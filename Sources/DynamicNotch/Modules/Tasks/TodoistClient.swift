import Foundation

/// Todoist 작업 (읽기·추가·완료). 개인 API 토큰은 키체인 "todoist.token"에만 둔다.
/// REST API v2(https://api.todoist.com/rest/v2)는 2026-11 기준 410 Gone이라 통합 API v1을 쓴다.
struct TodoistTask: Decodable, Equatable {
    struct Due: Decodable, Equatable {
        var date: String?
        var datetime: String?
        var string: String?
    }
    var id: String
    var content: String
    var due: Due?

    /// 마감 시각과 시각 포함 여부
    var dueDate: (date: Date, hasTime: Bool)? {
        guard let due else { return nil }
        if let dt = due.datetime, let d = Self.parse(dt) { return (d, true) }
        guard let raw = due.date else { return nil }
        if raw.contains("T"), let d = Self.parse(raw) { return (d, true) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(raw.prefix(10))).map { ($0, false) }
    }

    private static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        // 시간대 없는 "floating" 시각은 이 Mac 시간대로
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(s.prefix(19)))
    }
}

enum TodoistError: LocalizedError {
    case noToken, http(Int), decode

    var errorDescription: String? {
        switch self {
        case .noToken: return T("Todoist 토큰이 없음", "No Todoist token")
        case .http(401), .http(403): return T("Todoist 토큰이 올바르지 않음", "Todoist token was rejected")
        case .http(let c): return T("Todoist 응답 \(c)", "Todoist responded \(c)")
        case .decode: return T("Todoist 응답을 읽지 못함", "Couldn't read the Todoist response")
        }
    }
}

final class TodoistClient {
    static let tokenAccount = "todoist.token"
    private static let base = URL(string: "https://api.todoist.com/api/v1/")!
    private var running: [URLSessionTask] = []

    static var hasToken: Bool { KeychainStore.has(tokenAccount) }

    func cancel() {
        running.forEach { $0.cancel() }
        running.removeAll()
    }

    /// 미완료 작업 (최대 100개)
    func list(token: String? = nil, completion: @escaping (Result<[TodoistTask], Error>) -> Void) {
        request("tasks?limit=100", method: "GET", body: nil, token: token) { result in
            completion(result.flatMap { data in
                struct Page: Decodable { var results: [TodoistTask] }
                if let page = try? JSONDecoder().decode(Page.self, from: data) { return .success(page.results) }
                if let list = try? JSONDecoder().decode([TodoistTask].self, from: data) { return .success(list) }
                return .failure(TodoistError.decode)
            })
        }
    }

    func add(_ content: String, due: PIMParsedDate?, completion: @escaping (Result<Void, Error>) -> Void) {
        var body: [String: Any] = ["content": content]
        if let due {
            if due.hasTime {
                let f = ISO8601DateFormatter()
                body["due_datetime"] = f.string(from: due.date)
            } else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd"
                body["due_date"] = f.string(from: due.date)
            }
        }
        request("tasks", method: "POST", body: body, token: nil) { completion($0.map { _ in () }) }
    }

    func close(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request("tasks/\(id)/close", method: "POST", body: nil, token: nil) { completion($0.map { _ in () }) }
    }

    func reopen(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        request("tasks/\(id)/reopen", method: "POST", body: nil, token: nil) { completion($0.map { _ in () }) }
    }

    private func request(_ path: String, method: String, body: [String: Any]?, token: String?,
                         completion: @escaping (Result<Data, Error>) -> Void) {
        let done: (Result<Data, Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
        guard let token = token ?? KeychainStore.get(Self.tokenAccount), !token.isEmpty,
              let url = URL(string: path, relativeTo: Self.base) else { done(.failure(TodoistError.noToken)); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let task = URLSession.shared.dataTask(with: req) { data, resp, error in
            if let error { done(.failure(error)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { done(.failure(TodoistError.http(code))); return }
            done(.success(data ?? Data()))
        }
        running.append(task)
        running.removeAll { $0.state == .completed }
        task.resume()
    }
}
