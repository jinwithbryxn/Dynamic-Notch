import AppKit
import AVFoundation
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// 변환 결과 이미지 형식
enum FTImageFormat: String, CaseIterable, Identifiable {
    case jpeg, png, tiff, pdf, heic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        case .heic: return "HEIC"
        }
    }
    var ext: String { self == .jpeg ? "jpg" : rawValue }
    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .pdf: return .pdf
        case .heic: return .heic
        }
    }
}

/// 결과를 둘 곳
enum FTOutputMode: String, CaseIterable, Identifiable {
    case besideSource, downloads
    var id: String { rawValue }
    var label: String { self == .besideSource ? T("원본 옆", "Next to the original") : T("다운로드 폴더", "Downloads folder") }
}

/// 읽어 낸 QR·바코드 하나
struct FTCode: Identifiable, Equatable {
    var id: String { symbology + "|" + payload }
    let payload: String
    let symbology: String

    /// 웹·메일·전화·FaceTime·문자만 열기를 제안한다 (Wi-Fi·연락처 등은 복사만)
    var openableURL: URL? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        return ["http", "https", "mailto", "tel", "facetime", "facetime-audio", "sms"].contains(scheme) ? url : nil
    }
}

enum FTError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case locked(String)
    case tool(String)
    case nothing

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return T("\(name) 파일을 읽을 수 없음", "Can't read \(name)")
        case .unsupported(let what): return what
        case .locked(let name): return T("\(name)에 암호가 걸려 있어 합칠 수 없음", "\(name) is password-protected")
        case .tool(let message): return message
        case .nothing: return T("처리할 파일이 없음", "Nothing to process")
        }
    }
}

/// 파일 변환 엔진. 모두 동기 함수라 백그라운드 큐에서 부른다 (GIF만 async).
/// 결과는 항상 새 파일이며 원본과 기존 파일은 덮어쓰지 않는다.
enum FTEngine {
    // MARK: 파일 종류

    static func type(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
    }
    static func isPDF(_ url: URL) -> Bool { type(of: url)?.conforms(to: .pdf) == true }
    static func isImage(_ url: URL) -> Bool { type(of: url)?.conforms(to: .image) == true && !isPDF(url) }
    static func isVideo(_ url: URL) -> Bool {
        guard let t = type(of: url) else { return false }
        return t.conforms(to: .movie) || ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased())
    }
    static func isZip(_ url: URL) -> Bool {
        type(of: url)?.conforms(to: .zip) == true || url.pathExtension.lowercased() == "zip"
    }

    // MARK: 결과 위치

    /// 원본 옆이나 다운로드 폴더. 쓸 수 없으면 임시 폴더로 (결과를 노치에서 바로 끌어낼 수 있음).
    static func write(_ data: Data, source: URL, base: String, ext: String, mode: FTOutputMode) throws -> URL {
        let preferred = mode == .besideSource ? source.deletingLastPathComponent() : FAKit.downloadsFolder
        do {
            return try FAKit.writeNew(data, in: preferred, base: base, ext: ext)
        } catch {
            return try FAKit.writeNew(data, in: try fallbackFolder(), base: base, ext: ext)
        }
    }

    /// 원본 옆에 쓸 수 없을 때 쓰는 이 기능 전용 임시 폴더
    static func fallbackFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DynamicNotch File Tools", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func preferredFolder(for source: URL, mode: FTOutputMode) -> URL {
        mode == .besideSource ? source.deletingLastPathComponent() : FAKit.downloadsFolder
    }

    private static func baseName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    // MARK: 이미지 읽기

    /// 방향 정보를 반영한 이미지. maxPixel을 주면 긴 변을 그 크기로 줄인다.
    static func loadImage(_ url: URL, maxPixel: Int? = nil) -> (image: CGImage, properties: [CFString: Any])? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let full = max(w, h)
        let target = min(maxPixel ?? full, full > 0 ? full : (maxPixel ?? 4096))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, target),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return (image, props)
    }

    static func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let o = p[kCGImagePropertyOrientation] as? Int ?? 1
        return o >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    /// 투명 부분을 흰 배경에 합친다 (JPEG는 투명을 담지 못함)
    private static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    /// 이미지 하나를 그 형식으로 인코딩한 데이터
    static func encode(_ image: CGImage, as format: FTImageFormat, quality: Double, properties: [CFString: Any] = [:]) -> Data? {
        if format == .pdf { return pdfData(image, properties: properties) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        // 원본 메타데이터는 남기되 방향은 이미 반영했으므로 1로
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let v = properties[key] { props[key] = v }
        }
        props[kCGImagePropertyOrientation] = 1
        if format == .jpeg || format == .heic { props[kCGImageDestinationLossyCompressionQuality] = quality }
        let img = format == .jpeg ? flattened(image) : image
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// 이미지 한 장짜리 PDF (해상도 정보가 있으면 실제 크기로)
    private static func pdfData(_ image: CGImage, properties: [CFString: Any]) -> Data? {
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * 72 / dpi, height: Double(image.height) * 72 / dpi)
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return out as Data
    }

    // MARK: M-F-009 이미지 변환

    static func convertImage(_ url: URL, to format: FTImageFormat, quality: Double, mode: FTOutputMode) throws -> URL {
        try autoreleasepool {
            guard let (image, props) = loadImage(url) else { throw FTError.unreadable(url.lastPathComponent) }
            guard let data = encode(image, as: format, quality: quality, properties: props) else {
                throw FTError.unsupported(T("\(format.label)로 저장할 수 없음", "Can't save as \(format.label)"))
            }
            return try write(data, source: url, base: baseName(url), ext: format.ext, mode: mode)
        }
    }

    // MARK: M-F-010 이미지 압축·크기 줄이기

    /// 압축 목표 (원본보다 작은 값만 보여 준다)
    static let compressTargets: [Int] = [200_000, 500_000, 1_000_000, 2_000_000, 5_000_000]
    /// 긴 변 줄이기 (원본보다 작은 값만)
    static let resizeTargets: [Int] = [3840, 2560, 1920, 1280, 1024, 800]

    /// 목표 용량 이하가 될 때까지 품질을 낮추고, 그래도 크면 크기를 줄인다. HEIC는 HEIC로, 나머지는 JPEG로.
    static func compressImage(_ url: URL, targetBytes: Int, mode: FTOutputMode) throws -> (url: URL, bytes: Int) {
        try autoreleasepool {
            guard var (image, props) = loadImage(url, maxPixel: 8192) else { throw FTError.unreadable(url.lastPathComponent) }
            let format: FTImageFormat = type(of: url)?.conforms(to: .heic) == true ? .heic : .jpeg
            var best: Data?
            for _ in 0..<6 {
                // 품질 이분 탐색 (0.05–0.95)
                var lo = 0.05, hi = 0.95
                for _ in 0..<7 {
                    let q = (lo + hi) / 2
                    guard let d = encode(image, as: format, quality: q, properties: props) else { break }
                    if d.count <= targetBytes { best = d; lo = q } else { hi = q }
                }
                if best == nil, let d = encode(image, as: format, quality: 0.05, properties: props), d.count <= targetBytes { best = d }
                if best != nil { break }
                // 가장 낮은 품질로도 크면 크기를 줄여 다시
                let smallest = encode(image, as: format, quality: 0.05, properties: props)?.count ?? targetBytes * 2
                let scale = max(0.3, min(0.9, sqrt(Double(targetBytes) / Double(smallest)) * 0.95))
                let nextMax = Int(Double(max(image.width, image.height)) * scale)
                guard nextMax >= 64, let smaller = loadImage(url, maxPixel: nextMax) else { break }
                image = smaller.image
                props = smaller.properties
            }
            guard let data = best else {
                throw FTError.unsupported(T("목표 용량까지 줄일 수 없음", "Couldn't reach the target size"))
            }
            let out = try write(data, source: url, base: baseName(url) + T(" (압축)", " (compressed)"), ext: format.ext, mode: mode)
            return (out, data.count)
        }
    }

    /// 긴 변을 maxPixel로 줄인 새 파일. 형식은 원본을 따른다 (못 쓰는 형식이면 PNG).
    static func resizeImage(_ url: URL, longSide: Int, quality: Double, mode: FTOutputMode) throws -> URL {
        try autoreleasepool {
            guard let (image, props) = loadImage(url, maxPixel: longSide) else { throw FTError.unreadable(url.lastPathComponent) }
            let t = type(of: url)
            let format: FTImageFormat = t?.conforms(to: .jpeg) == true ? .jpeg
                : t?.conforms(to: .heic) == true ? .heic
                : t?.conforms(to: .tiff) == true ? .tiff : .png
            guard let data = encode(image, as: format, quality: quality, properties: props) else {
                throw FTError.unsupported(T("저장할 수 없음", "Can't save the image"))
            }
            return try write(data, source: url, base: baseName(url) + " (\(longSide)px)", ext: format.ext, mode: mode)
        }
    }

    // MARK: M-F-011 PDF 합치기

    /// 목록 순서대로 PDF 페이지와 이미지(한 장에 한 페이지)를 합친다. 기존 PDF 페이지는 다시 그리지 않는다.
    static func mergePDFs(_ urls: [URL], mode: FTOutputMode) throws -> (url: URL, pages: Int) {
        try autoreleasepool {
            let inputs = urls.filter { isPDF($0) || isImage($0) }
            guard inputs.count >= 2, let first = inputs.first else { throw FTError.nothing }
            let merged = PDFDocument()
            var sources: [PDFDocument] = []   // 합치는 동안 원본 문서를 살려 둔다
            for url in inputs {
                if isPDF(url) {
                    guard let doc = PDFDocument(url: url) else { throw FTError.unreadable(url.lastPathComponent) }
                    if doc.isLocked { throw FTError.locked(url.lastPathComponent) }
                    sources.append(doc)
                    for i in 0..<doc.pageCount {
                        if let page = doc.page(at: i) { merged.insert(page, at: merged.pageCount) }
                    }
                } else {
                    guard let (image, _) = loadImage(url),
                          let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    else { throw FTError.unreadable(url.lastPathComponent) }
                    merged.insert(page, at: merged.pageCount)
                }
            }
            guard let data = merged.dataRepresentation() else {
                throw FTError.unsupported(T("PDF를 만들 수 없음", "Couldn't create the PDF"))
            }
            let pages = merged.pageCount
            sources.removeAll()
            let out = try write(data, source: first, base: baseName(first) + T(" (합침)", " (merged)"), ext: "pdf", mode: mode)
            return (out, pages)
        }
    }

    // MARK: M-F-012 동영상 → GIF

    /// 앞 8초를 초당 12장, 긴 변 최대 480px로 (비율 유지)
    static func videoToGIF(_ url: URL, mode: FTOutputMode, seconds maxSeconds: Double = 8, fps: Double = 12,
                           longSide: CGFloat = 480) async throws -> (url: URL, frames: Int) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw FTError.unsupported(T("영상 트랙이 없음", "No video track")) }
        let seconds = min(maxSeconds, CMTimeGetSeconds(duration))
        guard seconds.isFinite, seconds > 0 else { throw FTError.unreadable(url.lastPathComponent) }
        let count = max(1, Int((seconds * fps).rounded(.down)))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: longSide, height: longSide)
        let tol = CMTime(value: 1, timescale: CMTimeScale(fps * 2))
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter = tol

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.gif.identifier as CFString, count, nil) else {
            throw FTError.unsupported(T("GIF를 만들 수 없음", "Can't create a GIF"))
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = 1.0 / fps
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                          kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        var added = 0
        for i in 0..<count {
            try Task.checkCancellation()
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let (image, _) = try? await gen.image(at: t) else { continue }
            CGImageDestinationAddImage(dest, image, frameProps)
            added += 1
        }
        guard added > 0, CGImageDestinationFinalize(dest) else {
            throw FTError.unsupported(T("GIF를 만들 수 없음", "Can't create a GIF"))
        }
        let saved = try write(out as Data, source: url, base: baseName(url), ext: "gif", mode: mode)
        return (saved, added)
    }

    // MARK: M-F-013 ZIP 압축·해제 (/usr/bin/ditto)

    /// 리소스 포크·확장 속성 없이 만들어 __MACOSX·._ 파일이 생기지 않는다.
    static let dittoZipFlags = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl"]

    static func zip(_ urls: [URL], mode: FTOutputMode, processes: FAProcessGroup) throws -> URL {
        guard let first = urls.first else { throw FTError.nothing }
        let fm = FileManager.default
        let work = try fallbackFolder().appendingPathComponent("zip-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }   // 이 기능이 만든 임시 폴더만 지운다
        let tmpZip = work.appendingPathComponent("out.zip")
        let base: String
        let args: [String]
        if urls.count == 1 {
            base = first.hasDirectoryPath || (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                ? first.lastPathComponent : baseName(first)
            args = dittoZipFlags + ["--keepParent", first.path, tmpZip.path]
        } else {
            // 여러 개는 임시 폴더에 복제(APFS에서는 공간을 더 쓰지 않음)한 뒤 그 내용을 묶는다
            let stage = work.appendingPathComponent("stage", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            for u in urls {
                let dest = FAKit.uniqueURL(in: stage, base: baseName(u), ext: u.pathExtension)
                try fm.copyItem(at: u, to: dest)
            }
            base = T("아카이브", "Archive")
            args = dittoZipFlags + [stage.path, tmpZip.path]
        }
        guard let r = processes.run("/usr/bin/ditto", args, timeout: 600), r.ok else {
            throw FTError.tool(T("압축 실패", "Zip failed"))
        }
        // 큰 압축도 메모리에 올리지 않게 임시 파일을 옮긴다
        do {
            return try FAKit.moveNew(tmpZip, in: preferredFolder(for: first, mode: mode), base: base, ext: "zip")
        } catch {
            return try FAKit.moveNew(tmpZip, in: try fallbackFolder(), base: base, ext: "zip")
        }
    }

    /// 압축 파일 안 경로 목록 (/usr/bin/zipinfo)
    static func zipEntries(_ url: URL, processes: FAProcessGroup) -> [String]? {
        guard let r = processes.run("/usr/bin/zipinfo", ["-1", url.path], timeout: 60), r.ok else { return nil }
        return r.outText.split(separator: "\n").map(String.init)
    }

    /// 원본 옆 새 폴더에 푼다. 안에 항목이 하나뿐이면 그 항목을 바로 꺼낸다.
    /// 압축 파일 밖으로 나가는 경로(절대 경로, ..)가 있으면 풀지 않는다.
    static func unzip(_ url: URL, mode: FTOutputMode, processes: FAProcessGroup) throws -> URL {
        guard let entries = zipEntries(url, processes: processes) else {
            throw FTError.unreadable(url.lastPathComponent)
        }
        let unsafe = entries.contains { e in e.hasPrefix("/") || e.split(separator: "/").contains("..") }
        if unsafe { throw FTError.unsupported(T("압축 파일 밖으로 나가는 경로가 있어 풀지 않음", "The archive has paths outside its folder; not extracted")) }
        let fm = FileManager.default
        // 같은 볼륨 안의 숨은 임시 폴더에 먼저 풀고 옮긴다 (옮기기가 빠르고, 이름 충돌을 피함)
        var parent = preferredFolder(for: url, mode: mode)
        var stage = parent.appendingPathComponent(".dmn-unzip-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        } catch {
            parent = try fallbackFolder()
            stage = parent.appendingPathComponent(".dmn-unzip-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        }
        guard let r = processes.run("/usr/bin/ditto", ["-x", "-k", url.path, stage.path], timeout: 600), r.ok else {
            try? fm.removeItem(at: stage)   // 이 기능이 방금 풀던 임시 폴더
            throw FTError.tool(T("압축 해제 실패", "Unzip failed"))
        }
        let all = (try? fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)) ?? []
        let items = all.filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }
        // 안에 항목이 하나뿐이면 그 항목을 바로 꺼낸다
        if items.count == 1, all.count == 1, let only = items.first {
            let target = try FAKit.moveNew(only, in: parent, base: only.deletingPathExtension().lastPathComponent, ext: only.pathExtension)
            try? fm.removeItem(at: stage)   // 비어 있는 임시 폴더
            return target
        }
        return try FAKit.moveNew(stage, in: parent, base: baseName(url), ext: "")
    }

    // MARK: M-F-014 QR·바코드 인식

    static func detectCodes(in image: CGImage) throws -> [FTCode] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        var seen = Set<String>()
        return (request.results ?? []).compactMap { obs -> FTCode? in
            guard let payload = obs.payloadStringValue, !payload.isEmpty else { return nil }
            let code = FTCode(payload: payload, symbology: obs.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""))
            return seen.insert(code.id).inserted ? code : nil
        }
    }

    static func detectCodes(inFile url: URL) throws -> [FTCode] {
        try autoreleasepool {
            guard let (image, _) = loadImage(url, maxPixel: 4096) else { throw FTError.unreadable(url.lastPathComponent) }
            return try detectCodes(in: image)
        }
    }

    /// 클립보드의 이미지 (사용자가 버튼을 눌렀을 때만 읽는다)
    static func clipboardImage() -> CGImage? {
        let pb = NSPasteboard.general
        for t in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")] {
            if let data = pb.data(forType: t), let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return img
            }
        }
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first,
           isImage(url) {
            return loadImage(url, maxPixel: 4096)?.image
        }
        return nil
    }

    /// 화면 영역을 골라 찍는다 (/usr/sbin/screencapture -i). 취소하면 nil. 찍은 임시 파일은 읽은 뒤 바로 지운다.
    static func captureRegion(processes: FAProcessGroup) -> CGImage? {
        let tmp = (try? fallbackFolder())?.appendingPathComponent("qr-\(UUID().uuidString).png")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("qr-\(UUID().uuidString).png")
        _ = processes.run("/usr/sbin/screencapture", ["-i", "-x", "-o", "-t", "png", tmp.path], timeout: 300)
        defer { try? FileManager.default.removeItem(at: tmp) }   // 이 기능이 만든 임시 캡처
        guard FileManager.default.fileExists(atPath: tmp.path) else { return nil }
        return loadImage(tmp, maxPixel: 4096)?.image
    }
}
