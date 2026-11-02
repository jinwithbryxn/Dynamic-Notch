import AppKit
import SwiftUI

// 시스템·하드웨어 계열 모듈(시스템 모니터, 배터리, 기기, 화면, 주식, 포트)이 같이 쓰는 표시 도우미.
// 이름 충돌을 피하려고 모두 Sys 접두어를 붙인다.

enum SysFmt {
    /// 1000 단위 바이트 (Finder와 같은 기준)
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }

    /// 초당 바이트 → "1.2 MB/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var x = v
        var i = 0
        while x >= 1000, i < units.count - 1 { x /= 1000; i += 1 }
        return i == 0 ? "\(Int(x)) \(units[i])" : String(format: x < 10 ? "%.1f %@" : "%.0f %@", x, units[i])
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? String(format: "%.0f°F", celsius * 9 / 5 + 32) : String(format: "%.0f°C", celsius)
    }

    /// 분 → "4시간 12분" / "4h 12m"
    static func minutes(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h == 0 { return T("\(r)분", "\(r)m") }
        return T("\(h)시간 \(r)분", "\(h)h \(r)m")
    }

    /// 초 → "3시간 20분" (관측 시간 등)
    static func seconds(_ s: Double) -> String { minutes(Int(s / 60)) }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmmss")
        return f.string(from: date)
    }
}

/// 노치 안 둥근 카드 배경
struct SysCard<Content: View>: View {
    var padding: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// 작은 캡슐 버튼
struct SysPillButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .white
    var prominent = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(prominent ? Color.black : tint)
            .background(Capsule().fill(prominent ? tint : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// 원형 게이지 (0...1)
struct SysRing: View {
    var value: Double
    var tint: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, value))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// 가로 막대 (0...1)
struct SysBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: height)
    }
}

/// "지원 안 됨 + 이유 + 대안" 표시
struct SysUnsupported: View {
    let title: String
    let reason: String
    var alternative: String? = nil
    var symbol = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.yellow.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(reason).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                if let alternative {
                    Text(alternative).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 작은 소제목
struct SysHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
    }
}

/// 외부 명령 실행 (백그라운드 큐에서 부른다). 출력은 메모리로만 받는다.
enum SysCommand {
    struct Result { let status: Int32; let output: String }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 8) -> Result? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return Result(status: p.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }
}

/// 소리 목록 (시스템 기본 소리)
enum SysSounds {
    static let names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    static func play(_ name: String) {
        guard !name.isEmpty, let s = NSSound(named: NSSound.Name(name)) else { return }
        s.play()
    }
}
