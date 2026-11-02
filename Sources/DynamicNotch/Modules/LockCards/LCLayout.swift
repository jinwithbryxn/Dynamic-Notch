import AppKit

enum LCPlacement: String, CaseIterable, Identifiable {
    case leftMiddle, leftBottom, rightMiddle, rightBottom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .leftMiddle: return T("왼쪽 가운데", "Left, middle")
        case .leftBottom: return T("왼쪽 아래", "Left, bottom")
        case .rightMiddle: return T("오른쪽 가운데", "Right, middle")
        case .rightBottom: return T("오른쪽 아래", "Right, bottom")
        }
    }
    var isLeft: Bool { self == .leftMiddle || self == .leftBottom }
}

enum LCStyle: String, CaseIterable, Identifiable {
    case cards, strip
    var id: String { rawValue }
    var label: String { self == .cards ? T("카드", "Cards") : T("한 줄", "Single strip") }
}

/// 잠금 화면 카드 배치. 좌표는 화면 왼쪽 위 기준(pt).
/// 가리면 안 되는 곳: 메뉴 막대(배터리·Wi-Fi·입력기), 큰 시계, 오른쪽 위 잠금 화면 알림,
/// 아래 가운데 로그인 영역(사진·이름·암호 칸·Touch ID 안내·힌트), 기존 음악 카드 자리.
/// 겹치면 카드 수를 줄이고, 하나도 못 놓으면 표시하지 않는다.
enum LCLayout {
    static let margin: CGFloat = 48
    static let cardSize = CGSize(width: 250, height: 60)
    static let spacing: CGFloat = 8
    static let stripHeight: CGFloat = 44

    static func exclusionZones(in s: CGSize) -> [(name: String, rect: CGRect)] {
        [
            ("menuBar", CGRect(x: 0, y: 0, width: s.width, height: 44)),
            ("clock", CGRect(x: s.width * 0.22, y: 0, width: s.width * 0.56, height: max(300, s.height * 0.36))),
            ("lockNotifications", CGRect(x: s.width - 400, y: 0, width: 400, height: s.height * 0.45)),
            ("login", CGRect(x: s.width / 2 - 260, y: s.height - 330, width: 520, height: 330)),
            // LockScreenManager의 음악 카드(380×208, 로그인 영역 300pt 위)와 여유
            ("mediaCard", CGRect(x: s.width / 2 - 205, y: s.height - 300 - 208 - 12, width: 410, height: 220)),
        ]
    }

    static func stackSize(count: Int, style: LCStyle, screenWidth: CGFloat) -> CGSize {
        switch style {
        case .cards:
            let n = CGFloat(max(1, count))
            return CGSize(width: cardSize.width, height: n * cardSize.height + (n - 1) * spacing)
        case .strip:
            // 가운데 음악 카드 자리(폭 410) 앞에서 멈춘다
            let width = min(CGFloat(max(1, count)) * 104 + 24, screenWidth / 2 - 205 - margin - 8)
            return CGSize(width: max(140, width), height: stripHeight)
        }
    }

    /// 놓을 자리. 겹치거나 화면을 벗어나면 nil.
    static func frame(size: CGSize, screen s: CGSize, placement: LCPlacement) -> CGRect? {
        let x = placement.isLeft ? margin : s.width - margin - size.width
        var y: CGFloat
        switch placement {
        case .leftMiddle, .rightMiddle: y = (s.height - size.height) / 2
        case .leftBottom, .rightBottom: y = s.height - margin - size.height
        }
        // 오른쪽은 잠금 화면 알림 구역 아래에서 시작
        if !placement.isLeft, let note = exclusionZones(in: s).first(where: { $0.name == "lockNotifications" }) {
            y = max(y, note.rect.maxY + 16)
        }
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        guard rect.minX >= 0, rect.maxX <= s.width, rect.minY >= 44, rect.maxY <= s.height - 16 else { return nil }
        guard !exclusionZones(in: s).contains(where: { $0.rect.intersects(rect) }) else { return nil }
        return rect
    }

    /// 들어갈 만큼 카드를 줄여 자리를 찾는다. (놓을 카드 수, 자리)
    static func fit(count: Int, style: LCStyle, screen: CGSize, placement: LCPlacement) -> (Int, CGRect)? {
        guard count > 0 else { return nil }
        for n in stride(from: count, through: 1, by: -1) {
            if let r = frame(size: stackSize(count: n, style: style, screenWidth: screen.width), screen: screen, placement: placement) {
                return (n, r)
            }
        }
        return nil
    }

    /// 화면 좌표(왼쪽 위 기준) → AppKit 창 좌표
    static func appKitFrame(_ r: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + r.minX, y: screenFrame.maxY - r.maxY, width: r.width, height: r.height)
    }

    /// 자체 검사: 여러 화면 크기 × 배치 × 모양 × 카드 수에서 자리가 금지 구역과 겹치지 않는지
    static func check() -> (combos: Int, placed: Int, trimmed: Int, hidden: Int, violations: Int) {
        let screens = [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 1512, height: 982),
                       CGSize(width: 1728, height: 1117), CGSize(width: 1920, height: 1080), CGSize(width: 2560, height: 1440),
                       CGSize(width: 1024, height: 768)]
        var combos = 0, placed = 0, trimmed = 0, hidden = 0, violations = 0
        for s in screens {
            for p in LCPlacement.allCases {
                for style in LCStyle.allCases {
                    for n in 1...LCCard.allCases.count {
                        combos += 1
                        guard let (k, r) = fit(count: n, style: style, screen: s, placement: p) else { hidden += 1; continue }
                        placed += 1
                        if k < n { trimmed += 1 }
                        let bad = exclusionZones(in: s).contains { $0.rect.intersects(r) }
                            || r.minX < 0 || r.maxX > s.width || r.minY < 0 || r.maxY > s.height
                        if bad { violations += 1 }
                    }
                }
            }
        }
        return (combos, placed, trimmed, hidden, violations)
    }
}
