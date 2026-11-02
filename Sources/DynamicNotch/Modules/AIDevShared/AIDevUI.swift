import AppKit
import SwiftUI

// AI·개발자 기능 모듈들이 함께 쓰는 작은 화면 부품 (노치 안: 검은 배경, 흰 글자)

/// 작고 둥근 캡슐 버튼
struct AIDevPill: View {
    let title: String
    var symbol: String? = nil
    var role: ActivityAction.Role = .normal
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .foregroundStyle(role == .primary ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch role {
        case .primary: return .white
        case .destructive: return Color.red.opacity(0.55)
        case .normal: return Color.white.opacity(0.12)
        }
    }
}

/// 둥근 회색 상자
struct AIDevBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// 지원 안 됨 + 이유 + 대안
struct AIDevUnsupported: View {
    let title: String
    let reason: String
    let alternative: String?
    var body: some View {
        AIDevBox {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                Text(reason).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                if let alternative {
                    Text(alternative).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

enum AIDevFormat {
    /// 1,234,567 → "1.2M"
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1_000) }
        return "\(n)"
    }

    static func usd(_ v: Double) -> String {
        v >= 100 ? String(format: "$%.0f", v) : (v >= 1 ? String(format: "$%.2f", v) : String(format: "$%.3f", v))
    }

    /// 경과 시간 "1:05" / "12:03:09"
    static func elapsed(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "3시간 12분 후" / "in 3h 12m"
    static func until(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return T("\(d)일 \(h)시간 후", "in \(d)d \(h)h") }
        if h > 0 { return T("\(h)시간 \(m)분 후", "in \(h)h \(m)m") }
        return T("\(m)분 후", "in \(m)m")
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(date) ? "jmm" : "MMMd jmm")
        return f.string(from: date)
    }

    /// 숨은 문자를 보이게: 제어 문자·폭 없는 문자·양방향 제어 문자를 ⟨U+XXXX⟩로, 탭은 ⇥, 줄바꿈은 ↵
    static func revealHidden(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x0A: out += "↵\n"
            case 0x09: out += "⇥"
            case 0x00...0x1F, 0x7F, 0x80...0x9F,
                 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF, 0x00AD:
                out += String(format: "⟨U+%04X⟩", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func hasHidden(_ s: String) -> Bool { revealHidden(s) != s.replacingOccurrences(of: "\n", with: "↵\n") }
}

enum AIDevPasteboard {
    /// 비밀 값 복사: 클립보드 기록 앱이 남기지 않도록 숨김 표시를 붙인다 (nspasteboard.org 관례)
    static func copySecret(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                         NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        pb.setString(value, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }

    static func copy(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }
}

/// 자체 검사 도우미
enum AIDevTest {
    /// 메인 런루프를 돌리며 조건을 기다린다 (자체 검사는 메인 스레드에서 돈다)
    @discardableResult
    static func wait(_ timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    /// 검사용 폴더: $REVIEW_OUT/test/<이름> (없으면 임시 폴더). 실제 설정 파일 경로는 절대 쓰지 않는다.
    static func dir(_ name: String) -> URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let out = env["REVIEW_OUT"], !out.isEmpty {
            base = URL(fileURLWithPath: out).appendingPathComponent("test")
        } else {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("dmn-selftest")
        }
        let d = base.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: d)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 메인 런루프를 돌리면서 다른 스레드에서 왕복한다 (서버 처리기가 메인 스레드에서 돌기 때문)
    static func ask(port: UInt16, line: String, timeout: TimeInterval = 3) -> String? {
        final class Box { var value: String?; var done = false }
        let box = Box()
        DispatchQueue.global().async {
            let r = roundTrip(port: port, line: line, timeout: timeout)
            DispatchQueue.main.async { box.value = r; box.done = true }
        }
        wait(timeout + 1) { box.done }
        return box.value
    }

    /// 여러 줄을 한 번에 보내고 연결이 닫히거나 줄 수가 찰 때까지 받은 글자 전체
    static func askAll(port: UInt16, payload: String, expectLines: Int, timeout: TimeInterval = 3) -> String {
        final class Box { var value = ""; var done = false }
        let box = Box()
        DispatchQueue.global().async {
            var result = ""
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            if fd >= 0 {
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                let ok = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                if ok == 0 {
                    let data = Array((payload + "\n").utf8)
                    _ = data.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
                    var out = [UInt8]()
                    var buf = [UInt8](repeating: 0, count: 4096)
                    while out.filter({ $0 == 0x0A }).count < expectLines {
                        let n = read(fd, &buf, buf.count)
                        if n <= 0 { break }
                        out += buf[0..<n]
                    }
                    result = String(decoding: out, as: UTF8.self)
                }
                Darwin.close(fd)
            }
            DispatchQueue.main.async { box.value = result; box.done = true }
        }
        wait(timeout + 1) { box.done }
        return box.value
    }

    /// 짧은 TCP 클라이언트: 한 줄 보내고 한 줄 받는다 (메인 스레드에서 직접 부르지 않는다)
    static func roundTrip(port: UInt16, line: String, timeout: TimeInterval = 3) -> String? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { return nil }
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !out.contains(0x0A) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out += buf[0..<n]
        }
        return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
