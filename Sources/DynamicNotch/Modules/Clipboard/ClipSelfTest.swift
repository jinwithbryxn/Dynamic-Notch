import AppKit

/// 클립보드 기능 자체 검사 (`--module-selftest=clipboard`).
/// 시스템 클립보드는 읽기만 하고(내용은 출력하지 않음), 쓰기 검사는 이름 붙인 개인 클립보드와 임시 폴더에서만 한다.
enum ClipSelfTest {
    static func run() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            out.append("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        // 1. 시스템 클립보드: 변경 번호와 형식 수만 읽는다
        let general = NSPasteboard.general
        out.append("general pasteboard: changeCount=\(general.changeCount), types=\(general.types?.count ?? 0), skip marker=\(ClipPasteboard.skipMarker(general) ?? "none")")

        // 2. 읽기 경로 (개인 클립보드)
        let pb = NSPasteboard(name: NSPasteboard.Name("com.dynamicnotch.clipboard.selftest.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        func put(_ s: String) { pb.clearContents(); pb.setString(s, forType: .string) }
        put("hello world"); check("read text", ClipPasteboard.read(pb)?.kind == .text)
        put("https://example.com/a?utm_source=x&id=3"); check("read link", ClipPasteboard.read(pb)?.kind == .link)
        put("#3A7BFF"); check("read color", ClipPasteboard.read(pb)?.kind == .color)
        put("   \n "); check("skip blank text", ClipPasteboard.read(pb) == nil)
        do {
            pb.clearContents()
            let pi = NSPasteboardItem()
            pi.setString("secret", forType: .string)
            pi.setData(Data(), forType: ClipPasteboard.concealedType)
            pb.writeObjects([pi])
            check("skip concealed", ClipPasteboard.skipMarker(pb) == ClipPasteboard.concealedType.rawValue)
            pb.clearContents()
            let t = NSPasteboardItem()
            t.setString("temp", forType: .string)
            t.setData(Data(), forType: ClipPasteboard.transientType)
            pb.writeObjects([t])
            check("skip transient", ClipPasteboard.skipMarker(pb) != nil)
        }
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff") as NSURL])
        let fileCap = ClipPasteboard.read(pb)
        check("read file", fileCap?.kind == .file && fileCap?.paths?.first?.hasSuffix("Tink.aiff") == true)

        let ocrImage = textImage("HELLO 2026", size: CGSize(width: 420, height: 120))
        let png = ocrImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        if let png {
            pb.clearContents()
            pb.setData(png, forType: .png)
            let cap = ClipPasteboard.read(pb)
            check("read image", cap?.kind == .image)
            let norm = cap?.rawImage.flatMap(ClipPasteboard.normalizeImage)
            check("normalize image", norm?.width == 420 && norm?.height == 120, "\(norm?.width ?? 0)x\(norm?.height ?? 0)")
        } else {
            check("render test image", false)
        }

        // 3. 글자 인식 (Vision, 기기 안)
        if let ocrImage {
            let start = Date()
            let text = ClipOCR.recognizeNow(ocrImage) ?? ""
            check("vision OCR", text.uppercased().contains("HELLO"), "\"\(text.replacingOccurrences(of: "\n", with: " "))\" in \(Int(Date().timeIntervalSince(start) * 1000)) ms, languages \(ClipOCR.languages.joined(separator: ","))")
        }

        // 4. 스마트 동작
        let blue = ClipColors.parse("#3A7BFF")
        check("color hex→rgb", blue.map { ClipColors.format($0, .rgb) } == "rgb(58, 123, 255)")
        check("color hex→hsl", blue.map { ClipColors.format($0, .hsl) } == "hsl(220, 100%, 61%)", blue.map { ClipColors.format($0, .hsl) } ?? "")
        check("color hex→SwiftUI", blue.map { ClipColors.format($0, .swiftUI) } == "Color(red: 0.227, green: 0.482, blue: 1.000)")
        check("color rgba→hex", ClipColors.parse("rgb(255 0 0 / 50%)").map { ClipColors.format($0, .hex) } == "#FF000080")
        check("color hsl→hex", ClipColors.parse("hsl(120, 100%, 50%)").map { ClipColors.format($0, .hex) } == "#00FF00")
        check("not a color", ClipColors.parse("123456") == nil && ClipColors.parse("#12345") == nil)
        let cleanCases: [(String, String?)] = [
            ("https://www.youtube.com/watch?v=abc&si=XYZ&utm_source=tw", "https://www.youtube.com/watch?v=abc"),
            ("https://example.com/?q=test&fbclid=1", "https://example.com/?q=test"),
            ("https://x.com/user/status/1?s=20&t=abc", "https://x.com/user/status/1"),
            ("https://example.com/search?s=keep", nil),
            ("https://open.spotify.com/track/1?si=abc", "https://open.spotify.com/track/1"),
        ]
        for (input, want) in cleanCases {
            let got = ClipLinkCleaner.cleanString(input)
            check("clean link \(URL(string: input)?.host ?? "")", got == want, got ?? "unchanged")
        }
        check("detect email", ClipDetect.email("someone@example.com") != nil && ClipDetect.email("not an email") == nil)
        check("detect phone", ClipDetect.phone("010-1234-5678") != nil && ClipDetect.phone("hello") == nil)
        check("math", ClipDetect.math("12*(3+4)") == 84 && ClipDetect.math("2^10 / 4") == 256)
        check("math ignores dates and phones", ClipDetect.math("2024-11-02") == nil && ClipDetect.math("010-1234-5678") == nil)
        check("pretty JSON", ClipDetect.prettyJSON("{\"a\":1}")?.contains("\n") == true && ClipDetect.prettyJSON("hello") == nil)

        // 5. 저장소 (임시 폴더에서만, 끝나면 이 검사가 만든 폴더를 지운다)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-clipboard-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = ClipStore(directory: tmp, readOnly: false)
        store.configure(persist: true, limit: 3)
        func text(_ s: String) -> ClipItem { var i = ClipItem(kind: .text); i.text = s; return i }
        let first = store.insert(text("one"), imageData: nil)
        store.update(first.id) { $0.pinned = true }
        for s in ["two", "three", "four", "five"] { store.insert(text(s), imageData: nil) }
        check("limit keeps pinned", store.items.count == 4 && store.items.contains { $0.id == first.id }, "\(store.items.map { $0.text ?? "" })")
        store.insert(text("four"), imageData: nil)
        check("duplicate moves to top", store.items.first?.text == "four" && store.items.count == 4)
        if let png {
            var img = ClipItem(kind: .image)
            img.digest = ClipStore.digest(png)
            img.ocrText = "HELLO 2026"
            let saved = store.insert(img, imageData: png)
            let path = tmp.appendingPathComponent("Images/\(saved.imageFile ?? "")").path
            let perms = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            check("image file 0600", perms == 0o600, String(perms, radix: 8))
            check("search OCR words", store.search("hello").contains { $0.id == saved.id })
            store.remove(saved.id)
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? -1
            check("removed image overwritten to 0 bytes", size == 0)
            var again = ClipItem(kind: .image)
            again.digest = "other"
            let reused = store.insert(again, imageData: png)
            check("free slot reused", reused.imageFile == saved.imageFile)
        }
        store.saveNow()
        store.waitForWrites()
        let dirPerms = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        check("store folder 0700", dirPerms == 0o700, String(dirPerms, radix: 8))
        let reload = ClipStore(directory: tmp, readOnly: true)
        reload.load()
        check("reload index", reload.items.map(\.id) == store.items.map(\.id), "\(reload.items.count) items")
        let list = store.addList("Work")
        if let id = store.items.first(where: { !$0.isSaved })?.id { store.toggle(id, in: list.id) }
        let cleared = store.clearHistory()
        check("clear keeps pinned and listed", store.items.allSatisfy(\.isSaved) && store.items.count == 2, "cleared \(cleared)")
        store.insert(text("memory only"), imageData: nil)
        store.configure(persist: false, limit: 3)
        store.saveNow()
        store.waitForWrites()
        check("persist off writes saved only", ClipStore.peekCounts(directory: tmp) == (2, 2))
        check("overflow count", ClipStore.overflow(items: store.items, limit: 0) == 1)

        // 5-1. 기록 흐름: 연속 복사 묶음, 같은 내용, 묶음 풀기 (임시 폴더의 모듈)
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-clipboard-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp2) }
        let m = ClipboardModule(storeDirectory: tmp2)
        m.store.configure(persist: true, limit: 40)
        let t0 = Date()
        func copy(_ s: String, _ dt: Double) { var i = ClipItem(kind: ClipColors.parse(s) != nil ? .color : .text, date: t0.addingTimeInterval(dt)); i.text = s; m.record(i, imageData: nil) }
        copy("alpha", 0); copy("beta", 1); copy("beta", 1.5); copy("#FF0000", 2)
        copy("gamma", 10)
        let burst = m.store.items.first { $0.kind == .burst }
        check("burst groups rapid copies", m.store.items.count == 2 && burst?.parts == ["alpha", "beta", "#FF0000"],
              "\(m.store.items.map { $0.kind.rawValue }) \(burst?.parts ?? [])")
        check("burst pastes joined text", burst?.text == "alpha\nbeta\n#FF0000")
        copy("alpha", 30)
        check("separate copy after window", m.store.items.first?.text == "alpha" && m.store.items.count == 3)
        if let burst { m.splitBurst(burst) }
        check("split burst", m.store.items.count == 4 && !m.store.items.contains { $0.kind == .burst } && m.store.items.contains { $0.kind == .color },
              "\(m.store.items.map { $0.text ?? "" })")
        m.store.saveNow()
        m.store.waitForWrites()

        // 6. 환경 (상태만 확인, 권한을 묻지 않음)
        out.append("accessibility trusted: \(AXIsProcessTrusted()) (paste into previous app \(AXIsProcessTrusted() ? "sends ⌘V" : "falls back to copy only"))")
        out.append(String(format: "input idle: %.0f s", ClipboardModule.idleSeconds()))
        let missing = ClipPrefs.sounds.filter { NSSound(named: NSSound.Name($0)) == nil }
        check("capture sounds available", missing.isEmpty, missing.joined(separator: ","))
        check("default shortcuts", ClipPrefs.defaultOpenShortcut.display == "⌃⌥C" && ClipPrefs.defaultPlainShortcut.display == "⌥⇧⌘V")
        let installed = ClipPrefs.defaultExcluded.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        out.append("excluded apps: \(ClipPrefs.defaultExcluded.count) defaults, installed here: \(installed.isEmpty ? "none" : installed.joined(separator: ", "))")
        out.append("store folder: \(ClipStore.defaultDirectory().path)")
        return out
    }

    /// 글자를 그린 흰 바탕 이미지 (OCR 검사용)
    static func textImage(_ s: String, size: CGSize) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 52), .foregroundColor: NSColor.black]
        (s as NSString).draw(at: NSPoint(x: 24, y: 30), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
