import AppKit
import AVFoundation
import CoreImage
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// 파일 도구 자체 검사: 검사용 파일을 직접 만들어 임시 폴더(또는 DMN_SELFTEST_DIR) 안에서만 변환한다.
/// 사용자 파일·클립보드·화면은 건드리지 않는다.
enum FTSelfTest {
    static func run(processes: FAProcessGroup) -> [String] {
        var lines: [String] = []
        func check(_ name: String, _ body: () throws -> String) {
            do { lines.append("ok   \(name): \(try body())") }
            catch { lines.append("FAIL \(name): \(error.localizedDescription)") }
        }
        struct Fail: LocalizedError { let errorDescription: String? ; init(_ s: String) { errorDescription = s } }

        let fm = FileManager.default
        let keep = ProcessInfo.processInfo.environment["DMN_SELFTEST_DIR"]
        let root = keep.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fm.temporaryDirectory.appendingPathComponent("dmn-filetools-selftest", isDirectory: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let dir = root.appendingPathComponent("filetools-\(stamp)", isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { return ["FAIL cannot create test folder: \(error.localizedDescription)"] }
        lines.append("dir \(dir.path)")
        let writers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        lines.append("ImageIO writers: heic=\(writers.contains(UTType.heic.identifier)) gif=\(writers.contains(UTType.gif.identifier)) pdf=\(writers.contains(UTType.pdf.identifier))")

        // 투명 배경이 있는 검사 이미지
        let sample = dir.appendingPathComponent("sample.png")
        guard let img = makeImage(width: 1200, height: 800), let png = FTEngine.encode(img, as: .png, quality: 1),
              (try? png.write(to: sample)) != nil else { return lines + ["FAIL cannot make the sample image"] }

        // M-F-009 변환
        for f in FTImageFormat.allCases {
            check("convert \(f.label)") {
                let out = try FTEngine.convertImage(sample, to: f, quality: 0.9, mode: .besideSource)
                if f == .pdf {
                    guard let doc = PDFDocument(url: out), doc.pageCount == 1 else { throw Fail("not a 1-page PDF") }
                } else {
                    guard let src = CGImageSourceCreateWithURL(out as CFURL, nil),
                          (CGImageSourceGetType(src) as String?) == f.type.identifier,
                          FTEngine.pixelSize(out) == CGSize(width: 1200, height: 800) else { throw Fail("wrong type or size") }
                }
                return "\(out.lastPathComponent) \(FAKit.bytes(FAKit.fileSize(out)))"
            }
        }
        check("never overwrite") {
            let again = try FTEngine.convertImage(sample, to: .jpeg, quality: 0.9, mode: .besideSource)
            guard again.lastPathComponent == "sample 2.jpg" else { throw Fail("got \(again.lastPathComponent)") }
            return again.lastPathComponent
        }

        // M-F-010 압축·크기 줄이기
        let noisy = dir.appendingPathComponent("noisy.jpg")
        if let n = makeNoise(width: 2400, height: 1600), let d = FTEngine.encode(n, as: .jpeg, quality: 0.95) { try? d.write(to: noisy) }
        lines.append("noisy source \(FAKit.bytes(FAKit.fileSize(noisy)))")
        for target in [500_000, 200_000] {
            check("compress \(FAKit.bytes(Int64(target)))") {
                let r = try FTEngine.compressImage(noisy, targetBytes: target, mode: .besideSource)
                guard r.bytes <= target, FAKit.fileSize(r.url) == Int64(r.bytes) else { throw Fail("\(r.bytes) bytes") }
                let px = FTEngine.pixelSize(r.url) ?? .zero
                return "\(r.url.lastPathComponent) \(FAKit.bytes(Int64(r.bytes))) \(Int(px.width))x\(Int(px.height))"
            }
        }
        check("resize long side 800") {
            let out = try FTEngine.resizeImage(noisy, longSide: 800, quality: 0.9, mode: .besideSource)
            let px = FTEngine.pixelSize(out) ?? .zero
            guard Int(max(px.width, px.height)) == 800 else { throw Fail("\(px)") }
            return "\(out.lastPathComponent) \(Int(px.width))x\(Int(px.height))"
        }

        // M-F-011 PDF 합치기 (2쪽 + 1쪽 + 이미지 1장 = 4쪽, 글자가 그대로 남는지)
        check("merge PDFs") {
            let a = dir.appendingPathComponent("a.pdf"), b = dir.appendingPathComponent("b.pdf")
            guard let da = makePDF(["Page A1", "Page A2"]), let db = makePDF(["Page B1"]) else { throw Fail("make pdf") }
            try da.write(to: a)
            try db.write(to: b)
            let r = try FTEngine.mergePDFs([a, b, sample], mode: .besideSource)
            guard let doc = PDFDocument(url: r.url), doc.pageCount == 4, r.pages == 4 else { throw Fail("pages \(r.pages)") }
            let t1 = doc.page(at: 0)?.string ?? "", t3 = doc.page(at: 2)?.string ?? ""
            guard t1.contains("A1"), t3.contains("B1") else { throw Fail("text lost: '\(t1)' '\(t3)'") }
            return "\(r.url.lastPathComponent) \(r.pages) pages, text kept"
        }

        // M-F-012 동영상 → GIF (10초짜리를 만들어 앞 8초 × 12fps = 96장, 긴 변 480px인지)
        check("video to GIF") {
            let mov = dir.appendingPathComponent("clip.mov")
            guard makeMovie(mov, width: 640, height: 360, seconds: 10, fps: 10) else { throw Fail("make movie") }
            let sema = DispatchSemaphore(value: 0)
            var result: Result<(url: URL, frames: Int), Error> = .failure(Fail("timeout"))
            Task.detached {
                do { result = .success(try await FTEngine.videoToGIF(mov, mode: .besideSource)) } catch { result = .failure(error) }
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 120)
            let r = try result.get()
            guard let src = CGImageSourceCreateWithURL(r.url as CFURL, nil) else { throw Fail("unreadable gif") }
            let frames = CGImageSourceGetCount(src)
            let px = FTEngine.pixelSize(r.url) ?? .zero
            let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let delay = (p?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
            guard frames == 96, Int(max(px.width, px.height)) == 480 else { throw Fail("frames \(frames) size \(px)") }
            return "\(r.url.lastPathComponent) \(frames) frames \(Int(px.width))x\(Int(px.height)) delay \(delay)s \(FAKit.bytes(FAKit.fileSize(r.url)))"
        }

        // M-F-013 ZIP (__MACOSX·._ 없음) 와 풀기
        check("zip files") {
            let jpg = dir.appendingPathComponent("sample.jpg")
            let z = try FTEngine.zip([sample, jpg], mode: .besideSource, processes: processes)
            guard let entries = FTEngine.zipEntries(z, processes: processes) else { throw Fail("zipinfo") }
            let junk = entries.filter { $0.contains("__MACOSX") || ($0 as NSString).lastPathComponent.hasPrefix("._") }
            guard entries.count == 2, junk.isEmpty else { throw Fail("entries \(entries)") }
            return "\(z.lastPathComponent) entries \(entries)"
        }
        var folderZip: URL?
        check("zip folder with xattr") {
            let folder = dir.appendingPathComponent("Folder", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let a = folder.appendingPathComponent("a.txt"), b = folder.appendingPathComponent("b.txt")
            try Data("alpha".utf8).write(to: a)
            try Data("beta".utf8).write(to: b)
            _ = processes.run("/usr/bin/xattr", ["-w", "com.example.dmn", "x", a.path])
            let z = try FTEngine.zip([folder], mode: .besideSource, processes: processes)
            folderZip = z
            guard let entries = FTEngine.zipEntries(z, processes: processes) else { throw Fail("zipinfo") }
            let junk = entries.filter { $0.contains("__MACOSX") || ($0 as NSString).lastPathComponent.hasPrefix("._") }
            guard entries.contains("Folder/a.txt"), junk.isEmpty else { throw Fail("entries \(entries)") }
            return "\(z.lastPathComponent) entries \(entries)"
        }
        check("unzip") {
            guard let z = folderZip else { throw Fail("no zip") }
            let out = try FTEngine.unzip(z, mode: .besideSource, processes: processes)
            let text = try String(contentsOf: out.appendingPathComponent("a.txt"), encoding: .utf8)
            guard text == "alpha", out.lastPathComponent == "Folder 2" else { throw Fail("\(out.lastPathComponent) '\(text)'") }
            return "\(out.lastPathComponent)/a.txt = \(text)"
        }

        // M-F-014 QR (파일에서 읽기, 열기 허용 규칙)
        check("QR from file") {
            let payload = "https://example.com/dmn-selftest?x=1"
            let qr = dir.appendingPathComponent("qr.png")
            guard let q = makeQR(payload), let d = FTEngine.encode(q, as: .png, quality: 1) else { throw Fail("make qr") }
            try d.write(to: qr)
            let codes = try FTEngine.detectCodes(inFile: qr)
            guard codes.count == 1, codes[0].payload == payload, codes[0].openableURL != nil else { throw Fail("\(codes)") }
            return "\(codes[0].symbology) '\(codes[0].payload)' openable"
        }
        check("QR open rules") {
            let ok = ["https://a.b", "mailto:x@y.z", "tel:123", "sms:123", "facetime:x@y.z"].allSatisfy { FTCode(payload: $0, symbology: "QR").openableURL != nil }
            let blocked = ["WIFI:S:home;T:WPA;P:pw;;", "javascript:alert(1)", "file:///etc/hosts", "BEGIN:VCARD"].allSatisfy { FTCode(payload: $0, symbology: "QR").openableURL == nil }
            guard ok, blocked else { throw Fail("ok=\(ok) blocked=\(blocked)") }
            return "web/mail/tel/sms/facetime open; wifi/js/file/vcard copy only"
        }
        lines.append("screencapture present=\(fm.isExecutableFile(atPath: "/usr/sbin/screencapture")) (not run in selftest)")
        lines.append("clipboard: not read in selftest")
        if keep == nil { try? fm.removeItem(at: dir) }   // 검사가 만든 임시 폴더
        return lines
    }

    // MARK: 검사용 파일 만들기

    private static func context(_ w: Int, _ h: Int, alpha: Bool) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    static func makeImage(width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width, height, alpha: true) else { return nil }
        let colors = [CGColor(red: 1, green: 0.4, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.3, blue: 1, alpha: 0.6)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        ctx.clear(CGRect(x: 40, y: 40, width: 200, height: 200))   // 투명 구멍
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: width / 2 - 150, y: height / 2 - 150, width: 300, height: 300))
        return ctx.makeImage()
    }

    static func makeNoise(width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width, height, alpha: false), let data = ctx.data else { return nil }
        arc4random_buf(data, ctx.bytesPerRow * height)
        return ctx.makeImage()
    }

    static func makePDF(_ pages: [String]) -> Data? {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for text in pages {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 36)]))
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    static func makeQR(_ text: String) -> CGImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        // 둘레에 흰 여백
        let padded = out.composited(over: CIImage(color: .white).cropped(to: out.extent.insetBy(dx: -48, dy: -48)))
        return CIContext().createCGImage(padded, from: padded.extent)
    }

    /// 색이 바뀌는 H.264 동영상
    static func makeMovie(_ url: URL, width: Int, height: Int, seconds: Int, fps: Int32) -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let total = seconds * Int(fps)
        for i in 0..<total {
            var waited = 0
            while !input.isReadyForMoreMediaData && waited < 5000 { usleep(1000); waited += 1 }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buffer = pb else { return false }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let v = UInt8((i * 255) / max(1, total - 1))
                memset(base, Int32(v), CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            if !adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps)) { return false }
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        _ = sema.wait(timeout: .now() + 60)
        return writer.status == .completed
    }
}
