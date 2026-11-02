import Foundation

/// 읽기 전용 캘린더 구독 (.ics 링크 또는 CalDAV 계정).
/// 주소·비밀번호는 키체인에만 두고, 이름·색·사용자 이름만 설정에 저장한다.
struct CalSubscription: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case ics, caldav }
    var id: String
    var name: String
    var kind: Kind
    var colorHex: String
    var username: String?

    var urlAccount: String { "calendar.sub.\(id).url" }
    var passwordAccount: String { "calendar.sub.\(id).password" }

    static func load(_ defaults: ModuleDefaults) -> [CalSubscription] {
        defaults.data("subscriptions").flatMap { try? JSONDecoder().decode([CalSubscription].self, from: $0) } ?? []
    }

    static func save(_ list: [CalSubscription], _ defaults: ModuleDefaults) {
        defaults.set(try? JSONEncoder().encode(list), "subscriptions")
    }

    /// 주소를 정리한다 (webcal:// → https://). 잘못된 주소면 nil.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        if s.lowercased().hasPrefix("webcals://") { s = "https://" + s.dropFirst("webcals://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

enum CalFeedError: LocalizedError {
    case badURL, http(Int), notCalendar, insecure, noCalendars, missingPassword

    var errorDescription: String? {
        switch self {
        case .badURL: return T("주소가 올바르지 않음", "Invalid address")
        case .http(let code):
            if code == 401 || code == 403 { return T("인증 실패 (\(code))", "Authentication failed (\(code))") }
            return T("서버 응답 \(code)", "Server responded \(code)")
        case .notCalendar: return T("캘린더(.ics) 내용이 아님", "Not calendar (.ics) data")
        case .insecure: return T("CalDAV는 https 주소만 받음", "CalDAV requires an https address")
        case .noCalendars: return T("일정 캘린더를 찾지 못함", "No event calendars found")
        case .missingPassword: return T("비밀번호가 키체인에 없음", "Password missing from Keychain")
        }
    }
}

/// 구독 하나를 읽어 VEVENT 목록을 돌려준다. 완료는 메인 스레드에서 부른다.
final class CalFeedLoader {
    private var icsTask: URLSessionTask?
    private var dav: CalDAVClient?

    func cancel() {
        icsTask?.cancel()
        icsTask = nil
        dav?.cancel()
        dav = nil
    }

    /// directURL: 개발용 검사 피드처럼 키체인을 거치지 않는 주소
    func load(_ sub: CalSubscription, directURL: URL? = nil, from: Date, to: Date, completion: @escaping (Result<CalICS.Feed, Error>) -> Void) {
        let done: (Result<CalICS.Feed, Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
        guard let url = directURL ?? KeychainStore.get(sub.urlAccount).flatMap(CalSubscription.normalize) else {
            done(.failure(CalFeedError.badURL)); return
        }
        switch sub.kind {
        case .ics:
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.setValue("text/calendar, */*;q=0.5", forHTTPHeaderField: "Accept")
            icsTask = URLSession.shared.dataTask(with: req) { data, resp, error in
                if let error { done(.failure(error)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                guard (200..<300).contains(code), let data else { done(.failure(CalFeedError.http(code))); return }
                let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                guard text.contains("BEGIN:VCALENDAR") else { done(.failure(CalFeedError.notCalendar)); return }
                done(.success(CalICS.parse(text)))
            }
            icsTask?.resume()
        case .caldav:
            guard url.scheme?.lowercased() == "https" else { done(.failure(CalFeedError.insecure)); return }
            guard let password = KeychainStore.get(sub.passwordAccount) else { done(.failure(CalFeedError.missingPassword)); return }
            let client = CalDAVClient(base: url, user: sub.username ?? "", password: password)
            dav = client
            client.fetch(from: from, to: to) { result in
                done(result.map { CalICS.Feed(name: sub.name, events: $0) })
            }
        }
    }
}

// MARK: - CalDAV (읽기 전용)

/// 최소 CalDAV 읽기: 주소가 캘린더 모음이면 바로 읽고, 아니면
/// current-user-principal → calendar-home-set → 캘린더 목록 순으로 찾아 각 캘린더의 VEVENT를 REPORT로 받는다.
final class CalDAVClient: NSObject, URLSessionTaskDelegate {
    private let base: URL
    private let user: String
    private let password: String
    private var session: URLSession?
    private var cancelled = false

    init(base: URL, user: String, password: String) {
        self.base = base
        self.user = user
        self.password = password
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func cancel() {
        cancelled = true
        session?.invalidateAndCancel()
        session = nil
    }

    func fetch(from: Date, to: Date, completion: @escaping (Result<[CalICS.Event], Error>) -> Void) {
        propfind(base, depth: 0) { [weak self] result in
            guard let self, !self.cancelled else { return }
            switch result {
            case .failure(let e):
                // 서버 루트면 .well-known 주소로 한 번 더 (인증 실패는 그대로 알린다)
                var authFailed = false
                if case CalFeedError.http(let code) = e, code == 401 || code == 403 { authFailed = true }
                if !authFailed, self.base.path.isEmpty || self.base.path == "/", let wk = URL(string: "/.well-known/caldav", relativeTo: self.base)?.absoluteURL {
                    self.propfind(wk, depth: 0) { r2 in
                        switch r2 {
                        case .failure: completion(.failure(e))
                        case .success(let root): self.continueFrom(root, at: wk, from: from, to: to, completion: completion)
                        }
                    }
                } else {
                    completion(.failure(e))
                }
            case .success(let root):
                self.continueFrom(root, at: self.base, from: from, to: to, completion: completion)
            }
        }
    }

    private func continueFrom(_ root: CalXMLNode, at url: URL, from: Date, to: Date,
                              completion: @escaping (Result<[CalICS.Event], Error>) -> Void) {
        if Self.isCalendar(root.first("resourcetype")) {
            report([url], from: from, to: to, completion: completion)
            return
        }
        if let home = root.first("calendar-home-set")?.first("href")?.text, let homeURL = resolve(home) {
            listCalendars(homeURL, from: from, to: to, completion: completion)
            return
        }
        guard let principal = root.first("current-user-principal")?.first("href")?.text, let pURL = resolve(principal) else {
            completion(.failure(CalFeedError.noCalendars)); return
        }
        propfind(pURL, depth: 0) { [weak self] r in
            guard let self, !self.cancelled else { return }
            guard case .success(let node) = r, let home = node.first("calendar-home-set")?.first("href")?.text,
                  let homeURL = self.resolve(home) else { completion(.failure(CalFeedError.noCalendars)); return }
            self.listCalendars(homeURL, from: from, to: to, completion: completion)
        }
    }

    private func listCalendars(_ home: URL, from: Date, to: Date, completion: @escaping (Result<[CalICS.Event], Error>) -> Void) {
        propfind(home, depth: 1) { [weak self] r in
            guard let self, !self.cancelled else { return }
            guard case .success(let node) = r else { completion(.failure(CalFeedError.noCalendars)); return }
            let urls: [URL] = node.all("response").compactMap { resp in
                guard Self.isCalendar(resp.first("resourcetype")), let href = resp.first("href")?.text else { return nil }
                let comps = resp.all("comp").compactMap { $0.attributes["name"]?.uppercased() }
                if !comps.isEmpty, !comps.contains("VEVENT") { return nil }
                return self.resolve(href)
            }
            guard !urls.isEmpty else { completion(.failure(CalFeedError.noCalendars)); return }
            self.report(Array(urls.prefix(20)), from: from, to: to, completion: completion)
        }
    }

    private func report(_ urls: [URL], from: Date, to: Date, completion: @escaping (Result<[CalICS.Event], Error>) -> Void) {
        var remaining = urls
        var events: [CalICS.Event] = []
        var firstError: Error?
        func next() {
            guard !cancelled else { return }
            guard !remaining.isEmpty else {
                if events.isEmpty, let firstError { completion(.failure(firstError)) } else { completion(.success(events)) }
                return
            }
            let url = remaining.removeFirst()
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let body = """
            <?xml version="1.0" encoding="utf-8"?>
            <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
              <d:prop><c:calendar-data/></d:prop>
              <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">
                <c:time-range start="\(f.string(from: from))" end="\(f.string(from: to))"/>
              </c:comp-filter></c:comp-filter></c:filter>
            </c:calendar-query>
            """
            send(url, method: "REPORT", depth: 1, body: body) { r in
                switch r {
                case .success(let node):
                    for data in node.all("calendar-data") {
                        events.append(contentsOf: CalICS.parse(data.text).events)
                    }
                case .failure(let e):
                    if firstError == nil { firstError = e }
                }
                next()
            }
        }
        next()
    }

    private func propfind(_ url: URL, depth: Int, completion: @escaping (Result<CalXMLNode, Error>) -> Void) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:resourcetype/><d:displayname/><d:current-user-principal/><c:calendar-home-set/><c:supported-calendar-component-set/></d:prop>
        </d:propfind>
        """
        send(url, method: "PROPFIND", depth: depth, body: body, completion: completion)
    }

    private func send(_ url: URL, method: String, depth: Int, body: String, completion: @escaping (Result<CalXMLNode, Error>) -> Void) {
        guard let session, !cancelled else { return }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = method
        req.httpBody = Data(body.utf8)
        req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(String(depth), forHTTPHeaderField: "Depth")
        req.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { data, resp, error in
            if let error { completion(.failure(error)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 207 || (200..<300).contains(code), let data, let node = CalXMLNode.parse(data) else {
                completion(.failure(CalFeedError.http(code))); return
            }
            completion(.success(node))
        }.resume()
    }

    private func resolve(_ href: String) -> URL? {
        URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL
    }

    private static func isCalendar(_ resourcetype: CalXMLNode?) -> Bool {
        resourcetype?.children.contains { $0.name == "calendar" } == true
    }

    // 리디렉션에서도 메서드·본문·헤더를 유지한다 (같은 호스트일 때만 인증 헤더 유지)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest, let newURL = request.url else { completionHandler(request); return }
        var r = original
        r.url = newURL
        if newURL.host != original.url?.host || newURL.scheme?.lowercased() != "https" {
            r.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(r)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        if (method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest),
           challenge.previousFailureCount == 0, challenge.protectionSpace.receivesCredentialSecurely {
            completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .none))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// 아주 작은 XML 트리 (이름은 네임스페이스를 뺀 로컬 이름)
final class CalXMLNode {
    let name: String
    var attributes: [String: String]
    var children: [CalXMLNode] = []
    var text = ""

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    /// 자손 중 이름이 같은 첫 노드
    func first(_ name: String) -> CalXMLNode? {
        for c in children {
            if c.name == name { return c }
            if let f = c.first(name) { return f }
        }
        return nil
    }

    /// 자손 중 이름이 같은 모든 노드
    func all(_ name: String) -> [CalXMLNode] {
        var out: [CalXMLNode] = []
        for c in children {
            if c.name == name { out.append(c) }
            out.append(contentsOf: c.all(name))
        }
        return out
    }

    static func parse(_ data: Data) -> CalXMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let root = CalXMLNode(name: "#root")
        private var stack: [CalXMLNode] = []

        override init() {
            super.init()
            stack = [root]
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = CalXMLNode(name: elementName, attributes: attributeDict)
            stack.last?.children.append(node)
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if stack.count > 1 { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }
    }
}
