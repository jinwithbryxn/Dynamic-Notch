import SwiftUI

/// 아이폰 다이내믹 아일랜드(Apple HIG "Live Activities")의 크기·모서리·여백 규칙을 이 노치에 옮긴 기준값.
/// HIG의 수치는 아이폰 기준(작은 표시 높이 36.67pt)이라, MacBook 노치 높이 32pt에 맞춰 0.873배로 환산한다.
/// HIG가 숫자를 주지 않는 모서리 반경은 아이폰 화면 모서리와 동심인 반경(약 44pt)을 같은 비율로 줄였다.
enum Island {
    /// HIG Specifications의 작은 표시 높이 (pt)
    static let referenceHeight: CGFloat = 36.67
    /// MacBook 노치 높이(32pt) 기준 환산 비율
    static let scale: CGFloat = 32 / referenceHeight

    /// 작은 표시의 아래쪽 모서리: 아일랜드처럼 양끝이 반원인 알약 (노치 높이의 절반)
    static func compactRadius(notchHeight: CGFloat) -> CGFloat { (notchHeight / 2).rounded() }
    /// 펼친 카드·확장 화면의 아래쪽 모서리 (44 × 0.873)
    static let expandedRadius: CGFloat = 38
    /// 확장 화면 안쪽 여백 (옆·아래 같게)
    static let panelMargin: CGFloat = 22
    /// 바깥 모서리 안쪽에 놓인 요소의 모서리: 여백만큼 줄인 동심 반경
    static func concentric(_ outer: CGFloat, inset: CGFloat) -> CGFloat { max(4, outer - inset) }
    /// 화면이 어두운 모드일 때 아일랜드 둘레에 보이는 가는 선 (HIG key line). 머리카락 굵기로 옅게.
    static let keylineOpacity: Double = 0.07
    static let keylineWidth: CGFloat = 0.5
}

/// 글자 크기 단계. iOS 기본 글자 크기(caption2 11pt … large title 34pt)에 `Island.scale`을 곱해 0.5pt 단위로 맞췄다.
/// HIG: 크고 중간 굵기 이상의 글자를 쓰고, 작은 글자는 아껴 쓴다. 그래서 `Font.island`의 기본 굵기는 medium이다.
/// 글자는 SF Pro, 숫자(시간·퍼센트·카운터)는 `design: .rounded`(SF Pro Rounded)로 쓴다. SF Pro semibold 숫자는 딱딱하고 투박해 보였다.
/// 17.5pt 이상의 큰 숫자(스톱워치·세계 시계 등)는 원래의 가는 굵기를 그대로 쓴다.
enum IslandText: CGFloat, CaseIterable {
    case caption2 = 9.5     // iOS 11
    case caption = 10.5     // iOS 12
    case footnote = 11.5    // iOS 13
    case subhead = 13       // iOS 15
    case callout = 14       // iOS 16
    case headline = 15      // iOS 17
    case title3 = 17.5      // iOS 20
    case title2 = 19        // iOS 22
    case title1 = 24.5      // iOS 28
    case largeTitle = 29.5  // iOS 34

    /// 이 단계가 옮겨 온 iOS 글자 크기 (자체 검사용)
    var iosSize: CGFloat {
        switch self {
        case .caption2: return 11
        case .caption: return 12
        case .footnote: return 13
        case .subhead: return 15
        case .callout: return 16
        case .headline: return 17
        case .title3: return 20
        case .title2: return 22
        case .title1: return 28
        case .largeTitle: return 34
        }
    }
}

extension Font {
    /// 아일랜드 글자: 애플 기본 글꼴(SF Pro), 기본 굵기 medium
    static func island(_ text: IslandText, _ weight: Font.Weight = .medium, design: Font.Design = .default) -> Font {
        .system(size: text.rawValue, weight: weight, design: design)
    }
}
