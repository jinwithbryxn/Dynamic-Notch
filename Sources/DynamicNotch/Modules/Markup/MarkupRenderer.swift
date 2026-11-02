import AppKit
import CoreImage

/// 마크업 도구
enum MarkupTool: String, CaseIterable, Identifiable {
    case arrow, rect, ellipse, line, highlight, text, pixelate, redact
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .pixelate: return "square.grid.3x3.fill"
        case .redact: return "rectangle.fill"
        }
    }

    var title: String {
        switch self {
        case .arrow: return T("화살표", "Arrow")
        case .rect: return T("사각형", "Rectangle")
        case .ellipse: return T("타원", "Ellipse")
        case .line: return T("직선", "Line")
        case .highlight: return T("형광펜", "Highlighter")
        case .text: return T("글자", "Text")
        case .pixelate: return T("모자이크", "Pixelate")
        case .redact: return T("가림", "Redact")
        }
    }
}

/// 도형 하나. 좌표는 원본 이미지 픽셀 기준(위쪽 원점).
struct MarkupShape: Identifiable, Equatable {
    var id = UUID()
    var tool: MarkupTool
    var rgba: [CGFloat]           // 0–1
    var width: CGFloat            // 픽셀
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []    // 형광펜
    var text: String = ""
    var fontSize: CGFloat = 32

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var cgColor: CGColor { CGColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3]) }
}

/// 원본 해상도로 합성한다. 미리보기는 줄인 원본과 scale(줄인 비율)을 넘긴다.
enum MarkupRenderer {
    static let ci = CIContext(options: [.cacheIntermediates: false])

    static func render(base: CGImage, shapes: [MarkupShape], scale: CGFloat = 1) -> CGImage? {
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        // 위쪽 원점 좌표로 뒤집는다
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        defer { NSGraphicsContext.restoreGraphicsState() }

        for s in shapes {
            draw(s, in: ctx, base: base, scale: scale)
        }
        return ctx.makeImage()
    }

    private static func scaled(_ p: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }
    private static func scaled(_ r: CGRect, _ k: CGFloat) -> CGRect {
        CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
    }

    private static func draw(_ s: MarkupShape, in ctx: CGContext, base: CGImage, scale k: CGFloat) {
        let lw = max(1, s.width * k)
        let a = scaled(s.start, k), b = scaled(s.end, k)
        let r = scaled(s.rect, k)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(s.cgColor)
        ctx.setFillColor(s.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch s.tool {
        case .rect:
            ctx.stroke(r)
        case .ellipse:
            ctx.strokeEllipse(in: r)
        case .line:
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        case .arrow:
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(lw * 4, 12 * k)
            // 몸통은 머리 밑까지만
            let neck = CGPoint(x: b.x - cos(angle) * head * 0.8, y: b.y - sin(angle) * head * 0.8)
            ctx.move(to: a); ctx.addLine(to: neck); ctx.strokePath()
            let left = CGPoint(x: b.x - cos(angle - .pi / 7) * head, y: b.y - sin(angle - .pi / 7) * head)
            let right = CGPoint(x: b.x - cos(angle + .pi / 7) * head, y: b.y - sin(angle + .pi / 7) * head)
            ctx.move(to: b); ctx.addLine(to: left); ctx.addLine(to: right); ctx.closePath(); ctx.fillPath()
        case .highlight:
            let pts = (s.points.isEmpty ? [s.start, s.end] : s.points).map { scaled($0, k) }
            guard let first = pts.first else { return }
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(s.cgColor.copy(alpha: 0.4) ?? s.cgColor)
            ctx.setLineWidth(lw * 3)
            ctx.move(to: first)
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            if pts.count == 1 { ctx.addLine(to: first) }
            ctx.strokePath()
        case .text:
            guard !s.text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(6, s.fontSize * k), weight: .bold),
                .foregroundColor: NSColor(cgColor: s.cgColor) ?? .red,
            ]
            (s.text as NSString).draw(at: a, withAttributes: attrs)
        case .redact:
            ctx.fill(r)
        case .pixelate:
            guard r.width >= 2, r.height >= 2,
                  let crop = base.cropping(to: r.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))) else { return }
            let block = max(6, min(r.width, r.height) / 10)
            let input = CIImage(cgImage: crop)
            let out = input.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block, kCIInputCenterKey: CIVector(x: 0, y: 0)])
                .cropped(to: input.extent)
            guard let img = ci.createCGImage(out, from: input.extent) else { return }
            let dest = r.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            // 뒤집힌 좌표에서 이미지는 거꾸로 그려지므로 그 자리만 다시 뒤집는다
            ctx.translateBy(x: dest.minX, y: dest.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: dest.size))
        }
    }

    /// 미리보기용으로 긴 변을 maxSide 이하로 줄인다
    static func downscale(_ image: CGImage, maxSide: CGFloat) -> (CGImage, CGFloat) {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxSide else { return (image, 1) }
        let k = maxSide / longest
        let w = Int(CGFloat(image.width) * k), h = Int(CGFloat(image.height) * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (image, 1) }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return (image, 1) }
        return (out, CGFloat(w) / CGFloat(image.width))
    }
}

// MARK: - 워터마크

struct WatermarkOptions: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case text, image }
    enum Position: String, Codable, CaseIterable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight, tile
    }

    var kind: Kind = .text
    var text: String = "© Dynamic Notch"
    var colorHex: String = "#FFFFFF"
    var imagePath: String = ""
    var position: Position = .bottomRight
    /// 크기: 짧은 변에 대한 비율 (글자는 글자 크기, 이미지는 폭)
    var size: Double = 0.06
    var opacity: Double = 0.5
    var rotation: Double = 0     // 도
}

enum WatermarkRenderer {
    static func color(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .white }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// 워터마크 한 장 (글자 또는 이미지)을 만든다
    static func mark(_ o: WatermarkOptions, shortSide: CGFloat, markImage: CGImage?) -> CGImage? {
        switch o.kind {
        case .text:
            guard !o.text.isEmpty else { return nil }
            let font = NSFont.systemFont(ofSize: max(6, shortSide * CGFloat(o.size)), weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(o.colorHex)]
            let str = NSAttributedString(string: o.text, attributes: attrs)
            let size = str.size()
            let w = max(1, Int(ceil(size.width))), h = max(1, Int(ceil(size.height)))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            str.draw(at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            return ctx.makeImage()
        case .image:
            guard let src = markImage else { return nil }
            let width = max(4, shortSide * CGFloat(o.size))
            let height = width * CGFloat(src.height) / CGFloat(max(1, src.width))
            guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(src, in: CGRect(x: 0, y: 0, width: Int(width), height: Int(height)))
            return ctx.makeImage()
        }
    }

    static func render(base: CGImage, options o: WatermarkOptions, markImage: CGImage?) -> CGImage? {
        let w = CGFloat(base.width), h = CGFloat(base.height)
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        let short = min(w, h)
        guard let mark = mark(o, shortSide: short, markImage: markImage) else { return ctx.makeImage() }
        let mw = CGFloat(mark.width), mh = CGFloat(mark.height)
        let margin = short * 0.03
        ctx.setAlpha(CGFloat(o.opacity))

        func place(center c: CGPoint) {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(o.rotation) * .pi / 180)
            ctx.draw(mark, in: CGRect(x: -mw / 2, y: -mh / 2, width: mw, height: mh))
            ctx.restoreGState()
        }

        // CG 좌표(아래쪽 원점)로 중심점을 정한다
        let left = margin + mw / 2, right = w - margin - mw / 2, midX = w / 2
        let top = h - margin - mh / 2, bottom = margin + mh / 2, midY = h / 2
        switch o.position {
        case .topLeft: place(center: CGPoint(x: left, y: top))
        case .top: place(center: CGPoint(x: midX, y: top))
        case .topRight: place(center: CGPoint(x: right, y: top))
        case .left: place(center: CGPoint(x: left, y: midY))
        case .center: place(center: CGPoint(x: midX, y: midY))
        case .right: place(center: CGPoint(x: right, y: midY))
        case .bottomLeft: place(center: CGPoint(x: left, y: bottom))
        case .bottom: place(center: CGPoint(x: midX, y: bottom))
        case .bottomRight: place(center: CGPoint(x: right, y: bottom))
        case .tile:
            let stepX = mw + short * 0.12, stepY = mh + short * 0.12
            var row = 0
            var y = mh / 2
            while y < h + mh {
                var x = (row % 2 == 0 ? mw / 2 : mw / 2 + stepX / 2)
                while x < w + mw { place(center: CGPoint(x: x, y: y)); x += stepX }
                y += stepY
                row += 1
            }
        }
        return ctx.makeImage()
    }
}
