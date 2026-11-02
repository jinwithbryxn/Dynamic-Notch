import AppKit
import CoreImage
import SwiftUI
import Vision

/// 기기 안 Vision 처리: 글자 인식(OCR)과 QR·바코드 읽기. 네트워크를 쓰지 않는다.
enum CPVision {
    /// 인식 언어: 한국어·영어 우선, 지원 목록에 있는 것만
    static func languages(for request: VNRecognizeTextRequest) -> [String] {
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["ko-KR", "en-US", "ja-JP", "zh-Hans"]
        let picked = wanted.filter { supported.contains($0) }
        return picked.isEmpty ? ["en-US"] : picked
    }

    /// 동기 글자 인식 (백그라운드 스레드에서 부른다). 줄 단위로 위→아래 순서.
    static func recognizeText(_ image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages(for: request)
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let obs = (request.results ?? []).sorted {
            // 위쪽(큰 y)부터, 같은 줄이면 왼쪽부터
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01 ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return obs.compactMap { $0.topCandidates(1).first?.string }
    }

    /// 동기 바코드 읽기 (QR·EAN·Code128 등). 내용 문자열 목록.
    static func detectBarcodes(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var seen = Set<String>()
        return (request.results ?? []).compactMap { $0.payloadStringValue }.filter { seen.insert($0).inserted }
    }

    static func async<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try work() }
            DispatchQueue.main.async { completion(r) }
        }
    }
}

/// 자체 검사용 이미지 만들기 (화면을 찍지 않는다)
enum CPTestImages {
    /// 흰 바탕에 검은 글자 줄들
    static func text(_ lines: [String], width: Int = 900, lineHeight: Int = 80) -> CGImage? {
        let height = lineHeight * lines.count + 40
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        // 뒤집힌 좌표에서 그리기 위해 변환
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .medium),
                                                    .foregroundColor: NSColor.black]
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 30, y: 20 + i * lineHeight), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// CIQRCodeGenerator로 만든 QR (10배 확대, 여백 포함)
    static func qr(_ payload: String) -> CGImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(payload.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let padded = out.composited(over: CIImage(color: .white).cropped(to: out.extent.insetBy(dx: -40, dy: -40)))
        return CIContext().createCGImage(padded, from: padded.extent)
    }

    /// 단색 + 격자 무늬 (픽셀 처리 검사용)
    static func checker(width: Int = 400, height: Int = 300, cell: Int = 10) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for y in stride(from: 0, to: height, by: cell) {
            for x in stride(from: 0, to: width, by: cell) {
                let on = ((x / cell) + (y / cell)) % 2 == 0
                ctx.setFillColor(on ? CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1) : CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
        return ctx.makeImage()
    }

    /// 한 픽셀 색 (위쪽 원점 좌표, 0–255 RGBA)
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        var buf = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 원하는 픽셀이 (0,0)에 오도록 이미지를 옮겨 그린다 (CG 원점은 아래쪽)
        let h = image.height
        ctx.draw(image, in: CGRect(x: -x, y: -(h - 1 - y), width: image.width, height: h))
        return (Int(buf[0]), Int(buf[1]), Int(buf[2]), Int(buf[3]))
    }

    /// 화면에 띄우지 않은 창에서 SwiftUI 화면을 PNG로 그린다 (DMN_TEST_OUT이 있을 때만)
    static func renderView<V: View>(_ view: V, size: CGSize, name: String) -> String? {
        guard ProcessInfo.processInfo.environment["DMN_TEST_OUT"] != nil else { return nil }
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .darkGray
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return write(rep.cgImage, name)
    }

    /// 자체 검사 결과 PNG를 남길 폴더 (환경 변수 DMN_TEST_OUT이 있을 때만)
    static func write(_ image: CGImage?, _ name: String) -> String? {
        guard let dir = ProcessInfo.processInfo.environment["DMN_TEST_OUT"], let image else { return nil }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return CPImageIO.savePNG(image, to: url) ? url.path : nil
    }
}
