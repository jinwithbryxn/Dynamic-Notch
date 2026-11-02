import AppKit
import Vision

/// 이미지 글자 인식 (Apple Vision, 기기 안에서만 처리. 네트워크·권한 없음)
enum ClipOCR {
    private static let queue = DispatchQueue(label: "dmn.clipboard.ocr", qos: .utility)

    /// 인식에 쓸 언어 (이 Mac이 지원하는 것만)
    static var languages: [String] {
        let wanted = ["ko-KR", "en-US", "ja-JP", "zh-Hans"]
        let request = VNRecognizeTextRequest()
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
        let pick = wanted.filter { supported.contains($0) }
        return pick.isEmpty ? ["en-US"] : pick
    }

    /// 백그라운드에서 인식하고 메인 스레드로 결과를 돌려준다 (글자가 없으면 빈 문자열, 실패하면 nil)
    static func recognize(_ data: Data, completion: @escaping (String?) -> Void) {
        queue.async {
            let text = recognizeNow(data)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// 지금 스레드에서 인식한다
    static func recognizeNow(_ data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return recognizeNow(cg)
    }

    static func recognizeNow(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
