import Foundation

/// 백그라운드에서 쓰는 동기 HTTP 받기 (주 스레드에서 부르지 않는다).
/// 200 응답만, 크기 제한 안에서만 돌려준다. 쿠키는 보내지도 저장하지도 않는다.
/// 앨범아트·가사·업데이트 확인이 함께 쓴다.
enum HTTPFetch {
    /// - timeout: 응답이 끊긴 채로 기다리는 시간 (URLRequest.timeoutInterval)
    /// - wait: 전체를 기다리는 최대 시간. 없으면 timeout + 1초. 넘기면 요청을 취소한다.
    static func data(_ url: URL, timeout: TimeInterval, maxBytes: Int, headers: [String: String] = [:],
                     wait: TimeInterval? = nil) -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= maxBytes { result = data }
            sem.signal()
        }
        task.resume()
        guard sem.wait(timeout: .now() + (wait ?? timeout + 1)) == .success else {
            task.cancel()
            return nil
        }
        return result
    }
}
