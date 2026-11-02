import SwiftUI

/// 노치 확장 기능 하나.
/// 확장 패널의 탭 화면, 명령 팔레트 동작, 설정 화면을 낼 수 있다.
/// 기능이 꺼지면 `stop()`에서 타이머·감시·오디오 캡처·네트워크 요청을 모두 멈춰야 한다.
///
/// 새 기능을 붙이는 방법: `Modules/<이름>/` 폴더에 이 규약을 따르는 클래스를 만들고 `ModuleCatalog.makeAll()`에 한 줄 더한다.
protocol NotchModule: AnyObject {
    /// 저장·설정에 쓰는 고정 이름 (예: "clipboard"). 바꾸면 사용자 설정이 초기화된다.
    var id: String { get }
    /// 탭·설정에 보이는 이름 (T("한국어", "English"))
    var title: String { get }
    /// SF Symbol 이름
    var symbol: String { get }
    /// 처음 설치했을 때 켜 둘지
    var enabledByDefault: Bool { get }

    /// 기능이 켜질 때 본 앱 프로세스에서만 불린다. 여러 번 불려도 안전해야 한다.
    func start(context: ModuleContext)
    /// 기능이 꺼질 때. 시작한 일을 모두 멈춘다.
    func stop()

    /// 확장 패널 탭 화면. nil이면 탭이 없다.
    func tabView() -> AnyView?
    /// 탭 화면 내용 크기(pt). 노치 도형이 이 크기에 맞춰 커진다.
    var tabContentSize: CGSize { get }

    /// 명령 팔레트에 늘 보이는 동작
    func paletteActions() -> [PaletteAction]
    /// 입력한 글자에 맞춰 즉석 결과를 낸다 (계산기·단위 변환·검색 등). 빠르게 돌아와야 한다(메인 스레드).
    func paletteResults(for query: String) -> [PaletteAction]

    /// 설정 창의 이 기능 화면. 설정 도우미 프로세스에서 그려진다 (본 앱과 다른 프로세스).
    func settingsView() -> AnyView?
    /// 설정 도우미가 이 기능의 설정을 바꿨을 때 본 앱에서 불린다.
    func settingsChanged()

    /// 홈 대시보드 카드 (약 210×68pt). nil이면 카드가 없다.
    func homeCard() -> AnyView?

    /// 진행 중인 작업(내려받기·녹음·실행 중인 명령 등)이 있어 앱이 스스로 다시 시작하면 안 되는지
    var isBusy: Bool { get }

    /// 개발·검증용 자체 검사 (`--module-selftest=<id>`). 실제 macOS 기능을 호출해 결과를 한 줄씩 돌려준다.
    /// 화면이나 사용자 데이터를 바꾸는 검사는 하지 않는다.
    func selfTest() -> [String]
}

extension NotchModule {
    var enabledByDefault: Bool { true }
    func tabView() -> AnyView? { nil }
    var tabContentSize: CGSize { CGSize(width: 420, height: 220) }
    func paletteActions() -> [PaletteAction] { [] }
    func paletteResults(for query: String) -> [PaletteAction] { [] }
    func settingsView() -> AnyView? { nil }
    func settingsChanged() {}
    func selfTest() -> [String] { ["no self test"] }
    var isBusy: Bool { false }
    func homeCard() -> AnyView? { nil }
}

/// 기능이 본 앱에 요청할 수 있는 일
struct ModuleContext {
    /// 라이브 활동·알림 게시 (`post`, `setPersistent`, `update`, `removePersistent`)
    let center: ActivityCenter
    /// 확장 패널을 열고 이 탭(기능 id)으로 간다
    let openTab: (String) -> Void
    /// 확장 패널을 닫는다
    let collapse: () -> Void
    /// 노치 창을 키 창으로 만들어 글자 입력을 받는다 (입력 칸이 있는 탭)
    let focusInput: () -> Void
}

/// 명령 팔레트 한 줄
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    let symbol: String
    /// 검색에 쓰는 추가 단어 (한국어·영어 별칭)
    var keywords: [String] = []
    /// 실행. 끝나면 팔레트가 닫힌다.
    let run: () -> Void
}

/// 기능별 설정 저장소. 키는 "module.<기능 id>.<이름>"으로 저장된다.
/// 설정 도우미에서 값을 바꾸면 본 앱의 해당 기능 `settingsChanged()`가 불린다.
struct ModuleDefaults {
    let module: String
    static let changedNotification = Notification.Name("com.dynamicnotch.app.moduleSettingsChanged")

    private func key(_ name: String) -> String { "module.\(module).\(name)" }

    func bool(_ name: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key(name)) as? Bool ?? value
    }
    func int(_ name: String, default value: Int) -> Int {
        UserDefaults.standard.object(forKey: key(name)) as? Int ?? value
    }
    func double(_ name: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: key(name)) as? Double ?? value
    }
    func string(_ name: String, default value: String) -> String {
        UserDefaults.standard.string(forKey: key(name)) ?? value
    }
    func strings(_ name: String, default value: [String]) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(name)) ?? value
    }
    func data(_ name: String) -> Data? { UserDefaults.standard.data(forKey: key(name)) }

    /// 값을 저장하고 다른 프로세스(본 앱·설정 도우미)에 알린다.
    func set(_ value: Any?, _ name: String) {
        if let value { UserDefaults.standard.set(value, forKey: key(name)) } else { UserDefaults.standard.removeObject(forKey: key(name)) }
        DistributedNotificationCenter.default().postNotificationName(
            Self.changedNotification, object: module, userInfo: nil, deliverImmediately: true)
    }
}
