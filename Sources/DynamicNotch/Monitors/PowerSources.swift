import Foundation
import IOKit.ps

/// 전원 목록 읽기. 전원 하나마다 IOPSGetPowerSourceDescription 사전 하나를 돌려준다.
/// 배터리 표시·배터리 상태·블루투스 기기 배터리·잠금 화면 카드가 함께 쓴다.
enum PowerSources {
    /// 내장 배터리·UPS (공개 API)
    static func system() -> [[String: Any]] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return [] }
        return descriptions(info)
    }

    /// macOS 배터리 위젯이 쓰는 액세서리 전원 목록 (비공개 IOPSCopyPowerSourcesByType, 액세서리 = 4).
    /// AirPods(좌·우·케이스), 블루투스 LE 마우스·키보드 등 배터리 서비스를 가진 기기가 이름으로 나온다. 함수가 없으면 빈 목록.
    static func accessories() -> [[String: Any]] {
        guard let byType, let info = byType(4)?.takeRetainedValue() else { return [] }
        return descriptions(info)
    }

    private typealias ByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    private static let byType: ByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let p = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return nil }
        return unsafeBitCast(p, to: ByType.self)
    }()

    private static func descriptions(_ info: CFTypeRef) -> [[String: Any]] {
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        return list.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    }
}
