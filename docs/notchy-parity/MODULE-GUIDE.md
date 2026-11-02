# 확장 기능(Module) 작성 규칙

Notchy 기능을 옮길 때 모든 기능은 이 규칙을 따르는 모듈로 만든다. 규약 코드는 `Sources/DynamicNotch/Modules/Core/`에 있다.

## 1. 구조

- 기능 하나 = `NotchModule`을 따르는 클래스 하나. 폴더는 `Sources/DynamicNotch/Modules/<이름>/`.
- 등록은 `Modules/Core/ModuleCatalog.swift`의 `makeAll()` 배열에 한 줄.
- 예시: `Modules/WorldClock/WorldClockModule.swift`.
- 모듈이 쓸 수 있는 것
  - `ModuleContext.center`: 노치 알림·라이브 활동 (`post`, `setPersistent`, `update`, `removePersistent`, `dismissTransient(kind:)`).
  - `ModuleContext.notice(...)`: 짧은 안내 카드.
  - `ModuleContext.openTab(id)`, `collapse()`, `focusInput()`.
  - `ModuleDefaults(module: id)`: 설정 저장 (키 `module.<id>.<이름>`). 바꾸면 본 앱의 `settingsChanged()`가 불린다.
  - `KeychainStore`: API 키·토큰. UserDefaults·로그·파일에 남기지 않는다.
  - `ModuleServices.previousApp`, `paste(_:)`, `pasteCurrentClipboard()`: 노치를 열기 전 앱에 붙여넣기 (손쉬운 사용 권한 필요, 없으면 클립보드에만).
  - `HotKeyCenter.shared.register(id, shortcut) { }`: 전역 단축키 (Carbon, 권한 불필요).
- 활동 종류(`ActivityKind`)에 확장 기능용 `notice, stopwatch, pomodoro, caffeinate, stocks, shell, privacy, system, agentApproval`이 있다. 상시 표시(`setPersistent`)는 종류마다 하나다.
- `NotchActivity.moduleTab`: 누르면 그 탭을 연다. `NotchActivity.actions`: 상세 카드 버튼.

## 2. 동작 원칙

- 실제 macOS 기능에 연결한다. 샘플·가짜 데이터를 실제 값처럼 보여 주지 않는다. 데이터가 없으면 빈 상태를 보여 준다.
- 못 하는 기능은 숨기지 말고, 탭이나 설정에 "지원 안 됨 + 이유 + 대안"을 보여 준다.
- `stop()`에서 타이머·감시·오디오 캡처·네트워크 요청·전역 단축키·이벤트 탭을 모두 멈춘다. `start()`는 여러 번 불려도 안전해야 한다.
- 기본값: 권한 요청, 네트워크, 백그라운드 감시, 셸·에이전트 설정 변경, 관리자 도우미가 필요한 기능은 `enabledByDefault = false`. 권한도 백그라운드 작업도 없는 탭만 `true`.
- 권한은 사용자가 기능을 켜거나 그 동작을 눌렀을 때만 요청한다.
- 네트워크는 기능이 켜져 있고 사용자가 그 화면·동작을 쓸 때만. 화면·클립보드 내용은 사용자가 요청한 동작에서만 외부로 보낸다.
- 다른 앱 설정 파일(`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.zshrc` 등)은 기존 내용과 합치고, 끌 때 이 앱이 넣은 부분만 표식으로 찾아 뺀다. 고치기 전에 백업한다.
- 사용자 데이터를 영구 삭제하지 않는다. 지우는 동작은 휴지통으로 보낸다.
- sudo, 시스템 설정 변경, 관리자 권한 도우미 설치는 하지 않는다. 필요한 기능은 "보류(관리자 도우미 필요)"로 둔다.
- 비공개 API는 `dlsym` 등으로 격리하고, 없으면 지원 안 됨 상태로 떨어진다.

## 3. 화면

- 노치 안은 검은 배경, 흰 글자, 어두운 화면 모드. 글꼴은 시스템(숫자는 `.rounded`, `.monospacedDigit()`).
- 탭 내용 크기 `tabContentSize`: 폭 360–640, 높이 120–300pt. 노치 도형이 이 크기에 맞춰 스프링으로 커진다.
- 보조 글자 `.secondary` 또는 `.white.opacity(0.6)`, 구분은 `Color.white.opacity(0.08)` 둥근 배경.
- 버튼은 작고 둥글게(`.buttonStyle(.plain)` + 캡슐 배경). 아이콘은 SF Symbols.
- 모든 문구는 `T("한국어", "English")`. 버튼·아이콘에는 `.help`와 접근성 이름.
- 동작 줄이기 설정(`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`)이면 큰 움직임 대신 페이드.
- 글자 입력 칸은 SwiftUI `TextField`를 쓰고, 탭이 나타날 때 `focusInput()` 후 `@FocusState`로 포커스.

## 4. 빌드와 검증 (설치 앱을 건드리지 않음)

- 빌드: `REVIEW_OUT=$HOME/Developer/Dynamic-Notch-build/<작업이름> scripts/review.sh build`
- 실행 파일: `"$REVIEW_OUT/Dynamic Notch Review.app/Contents/MacOS/DynamicNotchReview"`
  - `--list-modules`
  - `--module-selftest=<id>`: 실제 macOS 기능을 호출하되 화면·사용자 데이터·시스템 상태를 바꾸지 않는다.
  - `--render-tab=<id> --out=<png> [--start] [--wait=초]`: 탭 화면을 PNG로 그린다 (화면 녹화 권한 불필요).
- 금지: `scripts/review.sh start|stop`, `scripts/build.sh`, `/Applications` 쓰기, 설치된 앱 종료·실행, `pkill`, `sudo`.
- 최소 macOS 14.0. 새 API는 `#available`로 감싼다. Swift 5 모드, 외부 패키지 없음.
