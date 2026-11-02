# 현재 앱 기능 목록 (Dynamic Notch 1.2.2 + 로컬 커스텀)

## 1. 기준

- 저장소: `/Users/me/Developer/Dynamic-Notch`, 브랜치 `notchy-parity`
- 기준 커밋: `50ebc7b` (업스트림 1.2.2 `8105e6f` 위에 로컬 커스텀을 옮긴 커밋). 작성 시점 HEAD는 `0290f93`이다. 이 커밋은 `docs/notchy-parity/BASELINE.md`와 `scripts/review.sh`만 더하므로 앱 소스는 `50ebc7b`와 같다.
- 작성일: 2026-11-02
- 작성 방법: 읽기 전용 조사다. `Sources/` 아래 Swift 소스 전부, `Sources/MediaRemoteAdapter/`, `Resources/Info.plist`, `scripts/`, `~/.local/bin/notch-agent-done`, `~/.local/share/dynamic-notch-agent/`, `~/.claude/settings.json`, `~/.codex/config.toml`, `~/Library/Logs/notch-agent-done.log`를 읽었다. 사용자 설정값은 `defaults read com.dynamicnotch.app`로 읽기만 했다. 빌드·실행·설치를 하지 않았고 어떤 설정 파일도 바꾸지 않았다.
- 근거 표기: 경로는 `Sources/DynamicNotch/` 기준 상대 경로이고, 숫자는 `50ebc7b` 기준 줄 번호다. 저장소 밖 파일은 전체 경로로 적는다.
- 확인 수준: 코드를 읽어서 확인한 내용이다. 실제 화면에서 다시 보지 않았다. 코드만으로 단정할 수 없는 내용은 "추정"이라고 적는다.

## 2. 기능 표

표는 110행이다. 실제로 있는 기능이 106행이고, 비교용으로 "없음"을 확인한 행이 4행(C045, C049, C051, C066)이다. 설정 항목 열의 값은 `Settings/AppSettings.swift`의 기본값이며(초기화 278-389, 다시 읽기 391-506), 로컬에서 바꾼 기본값은 따로 표시한다.

### 노치 UI·공통

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C001 | 노치 상태 4단계 | idle(빈 노치); compact(노치 양옆 날개에 아이콘·값); detail(아래로 펼친 카드); expanded(큰 팝업); 표시 중인 활동과 그 presentation으로 기본 상태를 정하고, 확장 중이면 expanded가 우선 | — | SwiftUI, NSPanel | Notch/NotchViewModel.swift:4-6, 154-168; Notch/NotchRootView.swift:92-122 |
| C002 | 노치 모양·전환 애니메이션 | NotchShape의 반경을 애니메이션; 열기 spring(bounce 0.2), 닫기 spring(bounce 0.08), 팝업 0.42초; 열 때 눌림·늘어남(squash/stretch); 누르는 동안 6% 줄어드는 반응; compact에서 활동 종류가 바뀌면 0.24초 접었다가 다시 펼침 | — | SwiftUI animatableData | Notch/NotchShape.swift; Notch/NotchViewModel.swift:170-221, 307-373 |
| C003 | 호버 미리보기 | 빈 노치에 마우스를 올리면 몸통이 노치 폭+2×(topRadius+1), 높이+4pt로 커짐(로컬 변경); 내용은 보여 주지 않음 | `hoverPreview`=true | 전역 마우스 이동 모니터 | Notch/NotchViewModel.swift:224-232; Notch/NotchController.swift:156-163, 207-227 |
| C004 | 호버로 열기 | 노치 위에 0.35초 머물면 expanded 팝업을 엶; 잠금 중이거나 닫은 지 0.3초가 안 됐으면 열지 않음 | `hoverToOpen`=false | 전역 마우스 이동 모니터 | Notch/NotchController.swift:207-240 |
| C005 | 호버 중 알림 시간 멈춤 | 마우스가 노치 위에 있는 동안 일회성 알림의 만료 타이머를 멈추고, 벗어나면 남은 시간(최소 1.5초)으로 재개; `ignoresHoverPause` 알림(녹화 완료 카드)은 예외 | — | — | Activity/ActivityCenter.swift:16-27, 168-173; Notch/NotchController.swift:207-227 |
| C006 | 클릭 통과·노치 영역 판정 | 패널은 720×300pt 고정(가운데 맞춤 때문에 최대 1pt 넓어짐, 로컬 변경); 노치 도형(-4pt 여유) 밖에서는 ignoresMouseEvents로 아래 앱에 클릭이 전달됨; 확장 중에는 아래 점 영역 30pt까지 포함 | — | NSPanel(borderless, nonactivating, 레벨 mainMenu+3) | Notch/NotchPanel.swift:5-24; Notch/NotchGeometry.swift:5; Notch/NotchController.swift:130-145, 207-227; Notch/NotchViewModel.swift:297-304 |
| C007 | 짧은 클릭 | 표시 중인 활동에 따라 다름: 배터리→시스템 설정 배터리; 타이머→타이머 팝업; 음악→재생 앱 열기; 다운로드→마지막 완료 파일을 Finder에 표시; 녹화 중 왼쪽→정지·저장, 오른쪽→녹화 팝업, 녹화가 끝난 뒤→저장 파일 표시; 전화→접힌 수신 카드를 다시 펼치거나 통화 팝업; AirDrop→파일 표시; 스크린샷→카드 안 버튼만 반응; 에이전트→에이전트를 돌린 앱 열기; 그 밖→알림 닫기; 빈 노치는 반응 없음 | — | NSWorkspace | App/AppDelegate.swift:383-413; Notch/NotchController.swift:283-293 |
| C008 | 길게 누르기 | 누른 채로 정해진 시간이 지나면 햅틱과 함께 확장; 6pt 넘게 움직이면 취소; 빈 노치→홈; 타이머·음악·녹화·전화·다운로드·AI 사용량→각자 팝업; 컴팩트 알림→상세 카드로 바꿈; 상시 항목→팝업을 열고 다른 상시 항목을 넘겨 봄(AI 사용량 상시는 홈 사용량 페이지); 상세 알림·HUD·잠금 표시는 길게 누르기 없음 | `longPressDuration`=0.35 | — | Notch/NotchController.swift:256-281; App/AppDelegate.swift:342-371; Notch/NotchViewModel.swift:447-462, 488-496 |
| C009 | 포스 클릭 | 포스 터치 2단계에서 길게 누르기를 기다리지 않고 바로 확장; 1단계 압력은 누름 반응 크기에 반영 | `forceTouchEnabled`=true | NSEvent pressure | Notch/NotchController.swift:295-305 |
| C010 | 우클릭 메뉴 | 노치 우클릭 시 메뉴바 메뉴와 같은 메뉴(설정, 권한 관리, 알림 미리보기, 홈 열기, 업데이트 확인, 다시 시작, 종료) | — | NSMenu | Notch/NotchController.swift:307-309; App/AppDelegate.swift:56, 429-453 |
| C011 | 팝업 닫기 | 팝업 바깥 클릭; 두 손가락 위로 40pt 넘게 쓸기; 알림을 길게 눌러 연 팝업은 그 알림이 사라지면 자동으로 닫힘(타이머·음악 제외, 녹화는 완료 화면까지 유지) | — | 전역 마우스 다운 모니터 | Notch/NotchController.swift:183-189, 346-350; App/AppDelegate.swift:145-148, 373-381; Notch/NotchViewModel.swift:435-445 |
| C012 | 팝업 페이지 넘기기 | 두 손가락 가로 스크롤에 내용이 따라오고 50pt를 넘으면 다음·이전 페이지; 아래 점으로 위치 표시; 타이머 칸 위 세로 스크롤은 값 조절이 먼저 가져감 | — | NSEvent 스크롤(정밀 델타만) | Notch/NotchController.swift:313-358; Notch/NotchViewModel.swift:520-571; Features/Home/HomeView.swift:115-136 |
| C013 | 접힌 노치 제스처 | 음악 표시 중 두 손가락 좌우 50pt→다음·이전 곡; 상세 알림 위로 30pt→알림을 올려 보냄(전화 수신이면 거절하지 않고 접음); 상시 항목 위로 30pt→숨김, 아래로→다시 표시; 숨긴 동안 새 상시 항목이 생기면 숨김 해제 | — | NSEvent 스크롤 | Notch/NotchController.swift:362-396; Activity/ActivityCenter.swift:38-59, 132-133 |
| C014 | 홈 화면 | 빈 노치를 길게 누르거나 메뉴 "홈 열기"로 엶; 카메라·타이머·AI 사용량·메모·일정·트레이 페이지를 정해진 순서로 넘김; 끈 페이지는 빠지고, 남은 페이지가 없으면 유효한 페이지로 보정 | `homeOrder`=["camera","timer","usage","memo","calendar","tray"], `homeDisabled`=[], `trayMode`=on | — | Notch/NotchViewModel.swift:9-50, 104-119, 469-479; Features/Home/HomeView.swift:5-56; Notch/NotchRootView.swift:126-190; Settings/SettingsView.swift:438-490 |
| C015 | 상시 항목 넘겨 보기 | 상시 항목에서 연 팝업은 다른 상시 항목을 점·스와이프로 넘겨 봄; 전용 페이지가 없는 활동은 PersistentInfoPage(아이콘·제목·값)로 표시 | — | — | Notch/NotchViewModel.swift:499-517; Features/Home/HomeView.swift:68-112; Notch/NotchRootView.swift:183-188 |
| C016 | 크기 규칙 | compact 폭=노치+날개×2(기본 60, 컴팩트 56, 음악 46, 타이머 64); detail=max(노치+150, 330)×(노치+58), 큰 카드는 max(노치+190, 390)×detailHeight; expanded=페이지별(사용량·메모 usageSize, 카메라 cameraSize, 나머지 expandedBaseSize); 모두 720×300 패널 안에 들어가야 함 | — | — | Notch/NotchViewModel.swift:224-294; Activity/NotchActivity.swift:23-47 |
| C017 | 표시 화면 선택 | 내장 화면(위쪽 safe area가 있는 화면) 또는 주 화면(`NSScreen.screens.first`); 노치가 없는 화면에는 190pt 가상 노치를 그림; 한 번에 한 화면에만 표시 | `displayTarget`=builtIn | NSScreen | Notch/NotchGeometry.swift:8-30; Settings/SettingsView.swift:211-282 |
| C018 | 모든 Space·전체 화면 위 표시 | canJoinAllSpaces, stationary, fullScreenAuxiliary, ignoresCycle; 전체 화면 앱 위에도 떠 있고 자동 숨김 기능은 없음 | — | NSWindow collectionBehavior | Notch/NotchPanel.swift:5-24 |
| C019 | 노치 안 키보드 입력 | 입력 칸(타이머 숫자, 메모 등)을 누를 때만 키 창이 됨; ⌘X/C/V/A/Z, ⇧⌘Z를 키 위치(keyCode)로 처리해 한글 입력 상태에서도 동작; 닫을 때 키 포커스를 돌려줌 | — | NSPanel canBecomeKey | Notch/NotchPanel.swift:22-55; Notch/NotchController.swift:69-74 |
| C020 | 잠금 화면 노치 | 화면이 잠기면 본 패널을 숨기고 잠금용 패널을 SkyLight 전용 Space(레벨 400)에 띄워 자물쇠 표시; 잠금 해제 때 1.2초 열림 애니메이션 뒤 교체; 화면보호기 처리 | `lockNotchEnabled`=true | 비공개 SkyLight(SLSSpaceCreate 등), `com.apple.screenIsLocked` 분산 알림 | Features/LockScreen/SkyLight.swift; Features/LockScreen/LockScreenManager.swift:44-157; Notch/NotchController.swift:76-126; Activity/ActivityViews.swift:145 |
| C021 | 알림 우선순위·대기열 | 일회성 알림은 한 번에 하나; 같은 종류는 내용만 바꾸고 시간을 다시 셈; 더 낮은 우선순위는 대기열(최대 4개, 넘치면 낮은 것부터 버림); 같거나 높은 우선순위는 지금 알림을 대체하고 기존 알림은 버림; 우선순위 HUD 100, 전화 95, 잠금 90, 배터리 부족 85, 스크린샷 70, 정보 50, 녹화 40, 타이머 35, 다운로드 30, 음악 20, 고정 10 | — | — | Activity/NotchActivity.swift:7-20; Activity/ActivityCenter.swift:69-87, 117-126 |
| C022 | 상시 항목 순서 | 여러 상시 항목 중 맨 앞 하나만 접힌 노치에 보임; 설정 "우선순위" 페이지에서 순서를 바꾸면 5초 뒤 반영 | `persistentOrder`=["call","recording","timer","airdrop","download","media","aiUsage","hotspot","focusPinned"] | — | Activity/ActivityCenter.swift:30-51; App/AppDelegate.swift:98-115; Notch/NotchViewModel.swift:192-197; Settings/SettingsView.swift:294-326 |
| C023 | 알림 기본 표시 시간 | 표시 시간을 따로 정하지 않은 일회성 알림에 적용; detailThenCompact 알림은 상세로 보였다가 컴팩트로 바뀜 | `transientDuration`=2.5 | — | Activity/ActivityCenter.swift:150-173; Activity/NotchActivity.swift:40-47 |
| C024 | 설정 창 | 같은 실행 파일을 `--helper=settings`로 따로 띄운 창; 21개 페이지(일반, 우선순위, 상호작용, 기본 기능, 네트워크, 블루투스, 집중 모드, 전화, 음악, 다운로드, AirDrop, 스크린샷, 녹화, 배터리, HUD, 잠금 화면, AI 사용량, 에이전트, 테스트, 권한, 정보); 유리 질감 배경; 본 앱이 끝나면 같이 끝남 | `settingsBlur`=1.0, `settingsTransparency`=0.35 | 보조 프로세스 | Settings/SettingsView.swift:4-66; App/HelperApp.swift:52-108; App/AppDelegate.swift:496-519 |
| C025 | 메뉴바 아이콘 | capsule.fill 아이콘과 메뉴(설정 ⌘,, 권한 관리, 알림 미리보기, 홈 열기, 업데이트 확인, 다시 시작 ⌘R, 종료 ⌘Q) | `showStatusItem`=true | NSStatusBar | App/AppDelegate.swift:417-453 |
| C026 | 알림 미리보기 | 메뉴와 설정 "테스트" 페이지에서 Wi-Fi 4종, VPN 2종, 핫스팟, 오프라인, 블루투스 3종, 집중 모드 2종, HUD 3종, 배터리 3종, 음악 2종, 다운로드, AirDrop 2종, 스크린샷, 녹화, 타이머 완료, 일정, 전화 2종, 잠금, AI 사용량, 에이전트 완료를 가짜 데이터로 띄움; 모양(컴팩트·상세) 지정; 모두 중지 | — | — | Features/Preview/FeaturePreview.swift:8-31, 59, 113-232; Settings/SettingsView.swift:859-895 |
| C027 | 권한 관리·온보딩 | 첫 실행 때 권한 안내 창; 13개 권한(손쉬운 사용, 입력 모니터링, 화면 녹화, 카메라, 캘린더 전체 접근, 블루투스, 위치, 자동화(Music·Spotify), 집중 모드, 전체 디스크 접근, 파일, 알림, 로그인 항목)의 상태 표시와 요청·시스템 설정 열기; 창이 열린 동안 1초마다 새로고침 | `onboardingDone`=false | 각 권한 API | Permissions/PermissionsManager.swift:37-252; Permissions/PermissionsView.swift:123-145; App/AppDelegate.swift:155 |
| C028 | 햅틱 | 확장·제스처·타이머 값 변경 때 트랙패드 햅틱; 약함=alignment, 강함=levelChange | `hapticStrength`=weak | NSHapticFeedbackManager | Notch/NotchPanel.swift:114-122; Features/Timer/TimerController.swift:117 |
| C029 | 언어 | 시스템·한국어·영어; 바꾸면 다시 시작이 필요하다고 안내 | `language`=system | — | Settings/AppSettings.swift:109, 283; Settings/L10n.swift; Settings/SettingsView.swift:211-222 |

### 음악·오디오

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C030 | 재생 정보 수집 | MediaRemote를 쓰는 dylib을 Apple 서명 `/usr/bin/perl`에 불러와 JSON 줄로 받음; 어댑터가 죽으면 간격을 늘려 가며(최대 60초) 다시 띄움; Music·Spotify 분산 알림으로 보강하고 AppleScript로 검증; 소스 필터는 모든 미디어·Apple Music·Spotify | `mediaSource`=all | 비공개 MediaRemote, AppleScript(자동화 권한) | Features/Media/MediaController.swift:4-44, 89-255; Sources/MediaRemoteAdapter/adapter.m; Sources/MediaRemoteAdapter/run.pl |
| C031 | 접힌 노치 음악 표시 | 재생 곡을 상시 항목(날개 46)으로 표시: 왼쪽 앨범 아트, 오른쪽 재생 상태 파형, 앨범 아트에서 뽑은 강조색; 클릭→재생 앱 열기; 두 손가락 좌우→다음·이전 곡 | — | — | Features/Media/MediaController.swift:361-373, 412-418; Notch/NotchRootView.swift:74-89; App/AppDelegate.swift:390-391 |
| C032 | 곡 바뀜 팝업 | 곡이 바뀌면 잠깐 상세 카드; 앱 시작 4초 안에는 띄우지 않음; 앨범 아트가 늦게 오면 최대 0.8초 기다림; 기본은 신뢰 목록의 음악 앱만 | `mediaShowTrackChange`=true, `mediaTrackChangeMusicOnly`=true | — | Features/Media/MediaController.swift:374-409 |
| C033 | 일시정지 후 숨김 | 일시정지하고 정해진 초가 지나면 음악 상시 항목을 내림 | `mediaHideAfterPause`=30 | — | Features/Media/MediaController.swift:327-360 |
| C034 | 음악 팝업 | 앨범 아트(뒤집기 애니메이션), 흐르는 제목·아티스트, 0.5초마다 갱신하는 진행 막대와 드래그 이동, 이전·재생/일시정지·다음, 즐겨찾기, 출력 기기 버튼 | — | — | Features/Media/MediaPage.swift:6-131, 177-409; Notch/NotchViewModel.swift:377-406 |
| C035 | 재생 제어 | 재생/일시정지·다음·이전·위치 이동을 어댑터 표준 입력 명령(toggle, next, prev, seek, refresh)으로 보내고, 안 되면 미디어 키 이벤트를 합성; 3초 넘게 들었으면 "이전"은 곡 처음으로 | — | MediaRemote, CGEvent(NX_SYSDEFINED) | Features/Media/MediaController.swift:422-472, 524-548 |
| C036 | 즐겨찾기 | Apple Music 곡만 favorited(이전 macOS는 loved)를 읽고 바꿈; 다른 앱은 버튼 상태 없음 | — | AppleScript(Music) | Features/Media/MediaController.swift:477-515 |
| C037 | 출력 기기 선택 | 짧게 누르면 출력 기기 메뉴; 연결 안 된 블루투스 오디오는 연결한 뒤 최대 10초 기다려 선택; 0.4초 길게 누르면 볼륨 줄을 열고 닫음 | — | CoreAudio, IOBluetooth | Features/Media/OutputRoute.swift:7-386; Features/Media/MediaPage.swift:124 |
| C038 | 볼륨 줄 | 팝업 안 볼륨 슬라이더 | — | CoreAudio | Features/Media/MediaPage.swift:136-172 |
| C039 | 음악 테스트 모드 | 미리보기용 가짜 재생 정보로 음악 화면을 시험 | — | — | Features/Media/MediaController.swift:550-662 |
| C040 | 잠금 화면 음악 카드 | 잠금 중 재생 정보가 있으면 380×208 카드를 화면보호기 레벨로 띄우고 SkyLight로 잠금 Space에 옮김; 재생 제어·볼륨·출력 기기 목록 | `lockMediaWidget`=true, `lockWidgetBottom`=false(읽는 코드 없음) | 비공개 SkyLight | Features/LockScreen/LockScreenManager.swift:173-236; Features/LockScreen/LockMediaViews.swift:71-110, 269-300, 399-450 |
| C041 | 잠금 화면 전체 화면·가사 | 카드를 키우면 전체 화면 플레이어; 앨범 아트 배경 회전; 동기 가사 표시와 탭으로 위치 이동; 가사는 Apple Music 곡만, Music 앱 가사→(동의했을 때) LRCLIB 순으로 찾고 디스크에 캐시 | `lyricsEnabled`=true, `lyricsOnline`=false, `lyricsSize`=1 | `https://lrclib.net/api/get`, AppleScript(Music) | Features/LockScreen/LockMediaViews.swift:112-222, 310-396; Features/LockScreen/LyricsProvider.swift:38-168 |

### 타이머·집중

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C042 | 타이머 설정 | 홈 타이머 페이지에서 시·분·초 칸 입력 또는 두 손가락 세로 스크롤(12pt마다 한 단계, 햅틱); 처음 값 0:05:00 | 내부 값 `timerDraft`=[0,5,0] | — | Features/Timer/TimerController.swift:41-120; Features/Home/HomeView.swift:139-332 |
| C043 | 타이머 실행 | 시작·일시정지·재개·취소; 0.25초마다 갱신; 실행 중 상시 항목(날개 64)으로 남은 시간; 클릭→타이머 팝업; 홈에서 타이머 페이지를 끄면 진행 중인 타이머를 취소 | — | — | Features/Timer/TimerController.swift:133-193; App/AppDelegate.swift:317-320, 388-389 |
| C044 | 타이머 완료 알림 | 상세 카드 6초, 우선순위 85, Glass 소리, 노치 흔들림 | — | NSSound | Features/Timer/TimerController.swift:195-218; Notch/NotchViewModel.swift:464-467 |
| C045 | 뽀모도로·스톱워치 | 없음. 1회 카운트다운 타이머만 있다 | — | — | 해당 코드 없음 |

### 일정·할 일·메모

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C046 | 일정 페이지 | 홈 일정 페이지에 남은 일정 중 앞의 3개; 누르면 캘린더 앱(`ical://`); 홈에서 일정 페이지를 끄면 감시 중지 | — | EventKit 전체 접근 | Features/Home/CameraAndCalendar.swift:139-233, 259-304; App/AppDelegate.swift:317-320 |
| C047 | 일정 시작 전 알림 | 시작 N분 전 상세 카드 6초; 다음 알림 시각에 맞춰 깨어남; 앞의 3개 일정만 검사하므로 4번째 이후 일정은 알림이 늦거나 빠질 수 있음 | `calendarAlertMinutes`=10 | EventKit | Features/Home/CameraAndCalendar.swift:193-250 |
| C048 | 메모 | 홈 메모 페이지; 오른쪽 1/3 목록과 제목·본문 편집; 입력이 0.8초 멈추면 저장; 빈 메모는 자동 삭제; 우클릭 삭제는 바로 영구 삭제(휴지통 아님); 저장 위치 `~/Library/Application Support/DynamicNotch/Memos/<uuid>.json`; 페이지를 닫고 5초 뒤 메모리에서 내림 | — | 파일 시스템 | Features/Memo/MemoStore.swift; Features/Memo/MemoPage.swift:6-345 |
| C049 | 미리 알림·할 일 | 없음. 미리 알림(EventKit reminder) 연동과 할 일 목록이 없다 | — | — | 해당 코드 없음 |

### 클립보드·텍스트

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C050 | 클립보드 감시(스크린샷 한정) | 0.5초마다 클립보드 변경 횟수를 보고 새 이미지가 스크린샷이면 카드 표시; 다른 클립보드 내용은 다루지 않음 | `screenshotSource`=both(로컬 기본값) | NSPasteboard | Features/Screenshot/ScreenshotMonitor.swift:56-101 |
| C051 | 클립보드 기록·텍스트 도구 | 없음. 클립보드 기록, 텍스트 변환, 붙여넣기 도구가 없다. 텍스트 입력 기능은 메모(C048)뿐이다 | — | — | 해당 코드 없음 |

### 파일·선반(트레이·AirDrop)

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C052 | 파일 드래그 감지 | 파일을 끌고 노치 아래 가로 ±300pt × 세로 dragZoneHeight 영역에 들어오면 팝업을 열고 드롭 영역을 보여 줌 | `dragZoneHeight`=120, `trayMode`≠off | 전역 마우스 드래그 모니터, 드래그 대지 | Notch/NotchController.swift:165-205; Notch/NotchViewModel.swift:574-587; App/AppDelegate.swift:90 |
| C053 | 드롭 영역·파일 선택 | 트레이 페이지에 "트레이 보관"과 "AirDrop" 두 영역; 영역을 누르면 `--pick=airdrop\|tray` 보조 프로세스가 파일 선택 창을 띄우고 NUL 구분 경로를 돌려줌 | — | NSOpenPanel(보조 프로세스) | Features/Tray/TrayStore.swift:232-326; Features/Tray/FilePicker.swift |
| C054 | 트레이 보관 | 파일을 보안 범위 북마크로 보관; 원본 복사를 켜면 `~/Library/Application Support/Dynamic Notch/Tray`에 복사본을 둠; 목록은 UserDefaults `trayItems`에 저장 | `trayKeepCopies`=false | 보안 범위 북마크 | Features/Tray/TrayStore.swift:40-71 |
| C055 | 트레이 항목 조작 | ⌘·⇧ 다중 선택; 다른 앱에 끌어 놓기에 성공하면 트레이에서 빠짐; 우클릭 메뉴(열기, Finder에서 보기, AirDrop, 트레이에서 빼기); 모두 지우기 | — | NSDraggingSource | Features/Tray/TrayStore.swift:75-110, 328-508 |
| C056 | 트레이 자동 정리 | 정한 일수가 지난 항목을 지움; 앱을 시작할 때만 실행 | `trayCleanupDays`=0(끔) | — | Features/Tray/TrayStore.swift:45-51, 113-120 |
| C057 | 트레이 모드 | 사용(홈 페이지+드래그), 노치에서 가림(드래그만), 끄기(둘 다 끔) | `trayMode`=on | — | Settings/AppSettings.swift:83-91, 252-261; Notch/NotchController.swift:193 |
| C058 | AirDrop 보내기 | 드롭하거나 고른 파일을 AirDrop 공유로 보냄; 진행을 상시 항목으로 표시 | `airdropStyle`=ring | NSSharingService(AirDrop) | Features/Tray/TrayStore.swift:149-228; Settings/SettingsView.swift:625-648 |
| C059 | AirDrop 받기 감지 | 감시 폴더에 새로 생긴 파일의 quarantine 확장 속성에 sharingd가 있으면 AirDrop 수신으로 표시; 클릭→Finder 표시 | — | 확장 속성, 다운로드 폴더 접근 | Monitors/DownloadMonitor.swift:109-160; App/AppDelegate.swift:402-403 |
| C060 | 다운로드 진행 표시 | 파일 권한을 요청한 뒤에만 시작; 감시 폴더에 생긴 진행 중 파일을 NSProgress로 구독; 시작 때 2.5초 상세 카드, 진행 중에는 상시 항목; 진행 중일 때만 0.5초 폴링; Safari 다운로드 정보 읽기; 브라우저 이름 표시; 클릭→마지막 완료 파일 표시; 다운로드 팝업 | `downloadEnabled`=true, `downloadStyle`=ring, `downloadFolders`="", `downloadFolder`=~/Downloads | NSProgress 파일 구독, DispatchSource | Monitors/DownloadMonitor.swift:48-444; Settings/SettingsView.swift:605-620 |

### 화면 캡처·녹화

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C061 | 스크린샷 감지 | 클립보드 이미지와 저장 파일을 둘 다 감지(로컬 기본값); 파일은 NSMetadataQuery와 스크린샷 폴더 감시(로컬 추가)로 찾고, 확장 속성으로 스크린샷인지와 저장이 끝났는지 확인하며 같은 파일은 한 번만 표시 | `screenshotEnabled`=true, `screenshotSource`=both(업스트림 clipboard), `screenshotFolder`="" | NSMetadataQuery, DispatchSource, 스크린샷 저장 위치 설정 읽기 | Features/Screenshot/ScreenshotMonitor.swift:40-182 |
| C062 | 스크린샷 카드 | `--imgtool=thumb` 보조 프로세스로 만든 썸네일을 높이 96 상세 카드로 표시; 복사, 저장(PNG·JPEG, 폴더 지정), 휴지통으로 삭제, 끌어서 놓기; 정한 초가 지나면 자동으로 닫힘 | `screenshotJPEG`=false, `screenshotAutoClose`=10 | NSWorkspace recycle, NSItemProvider | Features/Screenshot/ScreenshotMonitor.swift:207-433; Features/Screenshot/ImageTool.swift |
| C063 | 화면 녹화 감지 | 1.5초(캡처 도구 실행 중엔 0.4초)마다 검사; 화면을 캡처하는 쪽이 있고(로컬 조건) 녹화 도구 UI 상태가 맞거나 `screencapture -v`가 돌면 녹화로 봄; 두 번 연속 맞아야 시작; 스크린샷 직후는 무시 | `recordingEnabled`=true | 비공개 SkyLight(SLSIsScreenWatcherPresent), sysctl 프로세스 목록, CGWindowListCopyWindowInfo | Monitors/RecordingMonitor.swift:25-104, 193-247 |
| C064 | 녹화 표시·정지 | 녹화 중 상시 항목(빨간 점·경과 시간) 또는 짧은 알림; 노치 왼쪽 클릭→⌃⌘Esc를 합성해 정지; 끝나면 저장 파일을 0.5초 간격 30번까지 찾아 1.8초 완료 카드(호버해도 멈추지 않음); 녹화 팝업 | `recordingStyle`=persistent, `recordingFolder`=~/Desktop | CGEvent 키 합성 | Monitors/RecordingMonitor.swift:106-158, 266-330; App/AppDelegate.swift:394-399 |
| C065 | 카메라 거울 | 홈 카메라 페이지에서 카메라 미리보기; 좌우 반전; 페이지를 떠나면 세션 중지 | `cameraMirror`=true | 카메라 권한, AVCaptureSession | Features/Home/CameraAndCalendar.swift:9-134 |

### 실행·검색·입력

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C066 | 앱 실행·검색·명령 팔레트·전역 단축키 | 없음. 전역 단축키 등록(RegisterEventHotKey, 전역 keyDown 모니터)이 없고 검색·명령 실행 화면도 없다. 키 입력은 노치 안 입력 칸(C019)에서만 받는다 | — | — | 해당 코드 없음; Notch/NotchPanel.swift:22 |

### 시스템·하드웨어

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C067 | 충전기 연결 알림 | 전원 연결·해제 알림(2초 디바운스) | `batteryChargerAlert`=true | IOKit 전원 소스 런루프 | Monitors/BatteryMonitor.swift:26-35, 73-80, 99-146 |
| C068 | 배터리 부족 알림 | 기준 % 이하로 내려가면 알림(우선순위 85); 기준+5% 위로 올라가면 다시 알릴 수 있게 됨 | `batteryLowAlert`=true, `batteryLowThreshold`=20 | IOKit | Monitors/BatteryMonitor.swift:82-88 |
| C069 | 완충 알림 | IsCharged이거나, 충전이 멈췄을 때 80% 이상이면 알림 | `batteryFullAlert`=true | IOKit | Monitors/BatteryMonitor.swift:90-94 |
| C070 | 배터리 알림 모양·클릭 | 컴팩트·상세 선택; 클릭→시스템 설정 배터리 | `batteryStyle`=compact | 시스템 설정 URL | App/AppDelegate.swift:386-387; Settings/SettingsView.swift:703-724 |
| C071 | Wi-Fi 전원 알림 | Wi-Fi 켜짐·꺼짐 | `netWifiPower`=true | CoreWLAN | Monitors/NetworkMonitor.swift:36-80, 190-243 |
| C072 | Wi-Fi 연결 알림 | 연결(SSID)·해제; 0.6초 디바운스; 잠자기 해제 직후 조용한 구간 | `netWifiConnection`=true | CoreWLAN, NWPathMonitor, 위치 권한(SSID) | Monitors/NetworkMonitor.swift:36-116, 190-243 |
| C073 | VPN 알림 | SC 서비스, 주소가 붙은 터널 인터페이스, 범위 지정 프록시, 알려진 VPN 앱 이름으로 연결 판단 | `netVPN`=true | SCDynamicStore | Monitors/NetworkMonitor.swift:118-186 |
| C074 | 핫스팟 표시 | SSID 목록이나 비싼(expensive) Wi-Fi 경로로 판단해 알림; 상시 고정 선택(설정을 바꿔도 다음 네트워크 이벤트 때 반영) | `netHotspot`=true, `hotspotPinned`=false, `hotspotSSIDs`="" | NWPathMonitor | Monitors/NetworkMonitor.swift:102-116, 268-282 |
| C075 | 오프라인 알림 | 연결이 끊기면 2초 확인 뒤 상세 알림 | 별도 키 없음 | NWPathMonitor | Monitors/NetworkMonitor.swift:190-243 |
| C076 | 네트워크 알림 시간·모양 | 표시 시간(0이면 기본값), 컴팩트·상세 | `netDuration`=0, `netStyle`=compact | — | Monitors/NetworkMonitor.swift:247-266; Settings/SettingsView.swift:494-516 |
| C077 | 블루투스 연결 알림 | 기기가 연결되면 이름과 기기 모양 기호 표시; 앱 시작 3초 안, 페어링 안 된 기기, 휴대폰·태블릿, 차단 목록은 건너뜀; 기호는 system_profiler 정보로 고르고 `btSymbolCache`에 캐시 | `btEnabled`=true, `btStyle`=compact | IOBluetooth, CoreBluetooth 권한, system_profiler | Monitors/BluetoothMonitor.swift:50-141, 219-265, 406-464 |
| C078 | 블루투스 배터리 | 연결 1.2초 뒤 배터리를 읽고, 없으면 0.6·1.8·3.6·6초에 다시 시도; 액세서리 배터리(비공개 IOPS)→HID→system_profiler 순; 퍼센트 또는 아이콘 | `btBattery`=percent | 비공개 IOPSCopyPowerSourcesByType(4), IOKit HID | Monitors/BluetoothMonitor.swift:157-217, 300-404 |
| C079 | 블루투스 차단 목록·연결 해제 | 차단 목록의 기기는 알리지 않음; 연결 해제 알림은 없음(`btShowDisconnect`는 읽는 코드가 없음) | `btBlocklist`="", `btShowDisconnect`=false | — | Monitors/BluetoothMonitor.swift:128-148 |
| C080 | 집중 모드 변경 알림 | `~/Library/DoNotDisturb/DB`를 감시(못 읽으면 5초 폴링)해 모드 켜짐·꺼짐 알림; 제외 목록; DB를 못 읽으면 INFocusStatusCenter로 켜짐 여부만 | `focusEnabled`=true, `focusDuration`=0, `focusExcluded`="", `focusStyle`=compact | 전체 디스크 접근, 집중 모드 상태 권한 | Monitors/FocusMonitor.swift:27-123, 141-277 |
| C081 | 집중 모드 상시 표시 | 켜진 모드를 상시 항목으로 고정(설정은 다음 폴링 때 반영) | `focusPinned`=false | 위와 같음 | Monitors/FocusMonitor.swift:126-137 |
| C082 | 음량 HUD | 음량 키를 가로채 시스템 HUD 대신 노치에 표시; ⌥⇧를 누르면 1/64 단위, 기본 1/16; 출력 기기 아이콘 | `hudVolume`=true, `hudOutputIcon`=true | 손쉬운 사용 권한, CGEvent 탭(NX_SYSDEFINED), CoreAudio | Monitors/HUDMonitor.swift:30-154, 258-321 |
| C083 | 화면 밝기 HUD | 밝기 키를 가로채 조절·표시; 다른 경로로 바뀐 밝기도 표시 | `hudDisplay`=true, `hudDisplayExternal`=true | 비공개 DisplayServices | Monitors/HUDMonitor.swift:158-166, 193-236, 325-422 |
| C084 | 키보드 밝기 HUD | 키보드 밝기 키를 가로채 조절·표시; 다른 경로로 바뀐 밝기도 표시 | `hudKeyboard`=true, `hudKeyboardExternal`=true | 비공개 CoreBrightness KeyboardBrightnessClient | Monitors/HUDMonitor.swift:170-236, 325-422 |
| C085 | HUD 모양 | 스타일, 표시 시간; HUD 설정을 모두 꺼도 이벤트 탭은 그대로 설치돼 있음 | `hudStyle`=bar, `hudDuration`=1.5 | — | Monitors/HUDMonitor.swift:240-253; Settings/SettingsView.swift:729-765 |

### 알림·통화·개인정보

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C086 | 전화 수신 카드 | 연속성 전화·FaceTime 수신 때 높이 64 상세 카드(최대 120초)에 거절·받기; TelephonyUtilities로 처리하고 0.6초 안에 안 되면 알림 배너 버튼을 접근성으로 누름; 위로 쓸면 접어서 "수신" 상시 항목으로 | `callEnabled`=true | 비공개 TelephonyUtilities(TUCallCenter), 손쉬운 사용 권한(AX 관찰자) | Monitors/CallMonitor.swift:94-156, 160-360, 367-493; Features/Call/CallViews.swift:91-92 |
| C087 | 통화 중 표시 | 통화 중 상시 항목(파형·경과 시간); 통화 팝업에서 음소거·종료; 통화 중 1초 폴링 | `callEnabled`=true | 위와 같음 | Monitors/CallMonitor.swift:294-360; Features/Call/CallViews.swift:124-128 |
| C088 | 전화 미리보기 | 가짜 번호 010-0000-0000으로 30초 동안 수신·통화 화면 시험 | — | — | Monitors/CallMonitor.swift:49-92 |
| C089 | 잠금 화면 곡 정보 숨김 | 잠금 중 카드에서 제목·아티스트를 숨김 | `lockHideTrackInfo`=false | — | Features/LockScreen/LockMediaViews.swift:71-110; Settings/SettingsView.swift:828-855 |
| C090 | 가사 온라인 조회 동의 | 기본은 꺼짐; 잠금 전체 화면의 버튼이나 설정으로 켜야 LRCLIB에 곡 정보를 보냄 | `lyricsOnline`=false | 네트워크 | Features/LockScreen/LockMediaViews.swift:188-205; Features/LockScreen/LyricsProvider.swift:82-109 |
| C091 | 시스템 알림 권한 | 권한 페이지에서 알림 권한을 요청하지만 시스템 알림을 보내는 코드는 없음 | — | UNUserNotificationCenter(권한 요청만) | Permissions/PermissionsManager.swift:200-252 |

### AI·개발자

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C092 | AI 서비스 로그인 | Claude·ChatGPT·Gemini 웹 로그인 창(WKWebView, 기본 데이터 저장소, Safari UA); 로그아웃은 그 서비스의 쿠키·데이터 삭제; 연결한 서비스 기록 | `aiConnected`="" | WebKit | Features/Usage/UsageWeb.swift:15-31, 342-396; Features/Usage/AIUsage.swift:5-69; Settings/SettingsView.swift:768-826 |
| C093 | 사용량 가져오기 | `--usage-fetch=` 보조 프로세스가 화면 없는 웹뷰로 호출(claude `/api/organizations`→`/usage`, chatgpt `/api/auth/session`→`/backend-api/wham/usage`, gemini 페이지 글자); 보조 프로세스 90초 제한, 본 앱 120초 감시; 주기적으로 갱신하고 화면이 덮인 동안(잠금 등) 멈춤 | `aiRefreshMinutes`=5(1·2·5·10 중) | 네트워크, WebKit | Features/Usage/UsageWeb.swift:36-337; Features/Usage/AIUsage.swift:156-260 |
| C094 | 사용량 페이지 | 홈 사용량 페이지에 서비스별 5시간·주간 사용률과 초기화 시각; 페이지가 보이면 새로고침 | — | — | Features/Usage/AIUsage.swift:217, 358-486 |
| C095 | 사용량 상시 표시 | 고른 서비스의 사용량을 상시 항목으로(왼쪽 5시간, 오른쪽 주간 또는 초기화 시각); 텍스트·그림 스타일; 길게 누르면 홈 사용량 페이지 | `aiUsagePinned`=false, `aiUsageStyle`=text, `aiUsageService`=claude | — | Features/Usage/AIUsage.swift:279-357; Notch/NotchViewModel.swift:488-496 |
| C096 | 에이전트 완료 알림(업스트림 경로) | Claude Code Stop 훅이나 Codex notify가 `<앱 실행 파일> --agent-done=<claude 또는 codex>`를 부르면 마지막 사용자 요청·작업 폴더·GUI 부모 앱을 찾아 `com.dynamicnotch.app.agent` 분산 알림을 보냄; 본 앱은 상세 7초 또는 컴팩트 5초(우선순위 50)로 표시; 클릭→에이전트를 돌린 앱 열기; 이전 Codex notify를 `--chain … --end-chain`으로 이어서 실행 | `agentAlerts`=true, `agentStyle`=detail(로컬; 업스트림 compact) | 분산 알림, 부모 프로세스 조회 | Features/Agent/AgentNotify.swift:5-163; App/main.swift:6-8; App/AppDelegate.swift:406-409 |
| C097 | 에이전트 훅 연결 버튼 | 설정 "에이전트" 페이지에서 Claude Code·Codex를 각각 연결·해제; 연결 여부는 설정 파일에 `--agent-done=<출처>` 글자가 있는지로 판단; 바꾸기 전에 `*.dynamicnotch.bak` 백업 | — | `~/.claude/settings.json`, `~/.codex/config.toml` 쓰기 | Features/Agent/AgentNotify.swift:171-308; Settings/SettingsView.swift:1095-1156 |
| C098 | 로컬 에이전트 명령 경로(로컬 추가) | 명령 채널로 받은 `agent:<claude 또는 codex>\|<프로젝트>`를 에이전트 알림으로 표시; 프로젝트 이름은 줄바꿈을 빼고 40자까지; 아이콘은 Claude 앱 아이콘, Codex는 ChatGPT 앱 안의 Codex 그림(화면 모드별)을 72px로 캐시; 열 대상 앱이 없어 부제는 "작업 완료" | `agentAlerts`, `agentStyle` | 분산 알림 `com.dynamicnotch.app.command` | App/AppDelegate.swift:179, 189-233; Features/Agent/AgentNotify.swift:144-146 |
| C099 | 개발용 명령 | DEV 빌드에서만 `scripts/notchctl`로 테스트 활동·화면·키 입력 등을 실행 | — | 분산 알림 | App/AppDelegate.swift:236-315; scripts/notchctl |

### 앱 관리·업데이트

| ID | 기능 | 세부 동작 | 설정 항목 (기본값) | 필요한 권한·API | 근거 |
|---|---|---|---|---|---|
| C100 | 자동 업데이트 | 시작 30초 뒤, 이후 1시간마다(24시간에 한 번) GitHub Releases(`jinwithbryxn/Dynamic-Notch`)를 확인; 새 버전이면 zip을 받아 SHA-256, codesign 무결성, 번들 ID, 버전을 확인한 뒤 앱이 끝나면 교체하고 기존 앱을 `.Dynamic Notch.app.old`로 남긴 채 다시 실행 | `autoUpdate`=true(현재 사용자 값 0) | 네트워크, `/bin/sh` 스크립트 | App/Updater.swift:11-184 |
| C101 | 수동 업데이트 확인 | 메뉴 "업데이트 확인…"; 최신이거나 실패하면 노치로 알림 | — | — | App/AppDelegate.swift:450, 466; App/Updater.swift:39-59 |
| C102 | 업데이트 완료 안내 | 업데이트 뒤 첫 실행 때 노치로 새 버전 안내 | — | — | App/Updater.swift:147-154; App/AppDelegate.swift:128-135 |
| C103 | 다시 시작 | 메뉴 ⌘R 또는 명령 채널 `restart`; `sh`로 잠시 뒤 다시 엶 | — | `/bin/sh`, `open` | App/AppDelegate.swift:469-479 |
| C104 | 메모리 지킴이 | 300초마다 메모리 확인; 한도를 넘으면 캐시를 비우고 5초 뒤 다시 보고, 그래도 넘으면 노치가 쉬는 때를 20초마다 최대 30분 기다려 다시 시작 | `memoryGuard`=true, `memoryLimitMB`=70(70–150) | task_info | App/MemoryGuard.swift; App/AppDelegate.swift:136-144, 332-339 |
| C105 | 메모리 반환 | 알림을 닫는 등 마지막 호출 3초 뒤 malloc_zone_pressure_relief | — | malloc | App/MemoryTrim.swift |
| C106 | 보조 프로세스 | 같은 실행 파일을 `--helper=settings`, `--helper=permissions`, `--helper=onboarding`, `--usage-fetch=`, `--pick=`, `--imgtool=`, `--agent-done=`로 다시 실행해 창과 무거운 작업을 본 앱 밖에서 처리; 설정 창 쪽은 본 앱이 끝나면 함께 끝남 | — | — | App/main.swift:6-40; App/HelperApp.swift:9-70 |
| C107 | 설정 동기화 | 설정 창이 값을 저장하면 `com.dynamicnotch.app.settingsChanged` 분산 알림을 보내고 본 앱이 전부 다시 읽음 | — | UserDefaults, 분산 알림 | Settings/AppSettings.swift:391-521; App/AppDelegate.swift:159-186 |
| C108 | 이전 앱 설정 옮기기 | `com.local.notchisland` 설정을 한 번 복사(`onboardingDone` 제외) | — | UserDefaults | App/Migration.swift:20 |
| C109 | 명령 채널 허용 목록 | 배포 빌드는 `preview:<id>[@style]`, `agent:…`(로컬 추가), `restart`만 받고 나머지는 DEV 빌드 전용 | — | 분산 알림(보낸 쪽 확인 불가) | App/AppDelegate.swift:165-186 |
| C110 | 로그인 시 실행 | 권한 페이지에서 로그인 항목 등록·해제 | — | SMAppService.mainApp | Permissions/PermissionsManager.swift:181, 240-248 |

## 3. 상태 관리 구조

### 3.1 흐름

1. 감시기(Monitors/*, Features/*Controller)가 시스템 사건을 받아 `ActivityCenter`에 활동(`NotchActivity`)을 올린다. 일회성은 `post`, 상시는 `setPersistent`/`removePersistent`, 값만 바꿀 때는 `update`를 쓴다 (Activity/ActivityCenter.swift:69-147).
2. `ActivityCenter.displayed`가 지금 노치에 보일 활동 하나를 고른다. 순서는 `lockActivity ?? transient ?? topPersistent`이다 (Activity/ActivityCenter.swift:30-33).
3. `NotchViewModel`이 `displayed`와 그 presentation, `showingDetail`, 확장 여부로 상태(idle/compact/detail/expanded)를 정하고 크기를 계산한다 (Notch/NotchViewModel.swift:154-294).
4. `NotchRootView`가 상태별 화면을 그리고, `NotchShape`가 크기와 반경을 spring으로 옮긴다 (Notch/NotchRootView.swift:23-190; Notch/NotchViewModel.swift:315-349).
5. `NotchController`가 마우스·스크롤·클릭을 받아 `NotchViewModel`과 `AppDelegate`의 클릭·길게 누르기 처리로 넘긴다 (Notch/NotchController.swift:156-396; App/AppDelegate.swift:342-413).

### 3.2 종류와 우선순위

- 활동 종류(`ActivityKind`)는 lock, battery, timer, calendar, media, download, airdrop, screenshot, recording, network, hotspot, bluetooth, focus, focusPinned, hud, demo, call, aiUsage, agent의 19개다 (Activity/NotchActivity.swift:3-5).
- 우선순위 상수는 HUD 100, 전화 95, 잠금 90, 배터리 부족 85, 스크린샷 70, 정보 50, 녹화 40, 타이머 35, 다운로드 30, 음악 20, 고정 10이다 (Activity/NotchActivity.swift:7-20). 우선순위는 일회성 알림끼리의 대체·대기에만 쓰인다.
- 상시 항목끼리는 우선순위가 아니라 `persistentOrder` 설정 순서로 정렬한다 (Activity/ActivityCenter.swift:47-51).

### 3.3 만료와 대기

- 일회성 알림은 `transient` 하나뿐이다. 표시 시간은 활동의 `duration`, 없으면 `transientDuration`(2.5초)이다 (Activity/ActivityCenter.swift:150-153).
- 같은 종류가 다시 오면 같은 카드의 내용만 바꾸고 시간을 다시 센다. 더 낮은 우선순위는 `pending`에 넣는다. 대기열은 우선순위순으로 최대 4개이고 넘치면 낮은 것을 버린다. 같거나 높은 우선순위가 오면 지금 알림을 바로 대체하며, 대체된 알림은 대기열로 돌아가지 않고 사라진다 (Activity/ActivityCenter.swift:69-87).
- 알림이 닫히면 대기열 맨 앞이 이어서 뜬다 (Activity/ActivityCenter.swift:117-126).
- 마우스가 노치 위에 있으면 만료 타이머가 멈추고, 벗어나면 최소 1.5초를 남겨 재개한다 (Activity/ActivityCenter.swift:16-27).
- presentation은 compact, detail, detailThenCompact(정한 시간 동안 상세 뒤 컴팩트) 세 가지다 (Activity/NotchActivity.swift:40-47; Activity/ActivityCenter.swift:155-167).

### 3.4 동시에 진행되는 라이브 활동

- 상시 항목은 종류별 사전(`persistent[kind]`)이라 여러 개가 동시에 살아 있을 수 있다. 하지만 접힌 노치에는 `topPersistent` 하나만 보인다.
- 나머지 상시 항목은 상시 항목을 길게 눌러 연 팝업에서 점·스와이프로만 볼 수 있다 (Notch/NotchViewModel.swift:499-517).
- 두 번째 항목을 작은 원으로 보여 주려던 `secondary` 속성은 정의만 있고 쓰는 곳이 없다 (Activity/ActivityCenter.swift:60-65).
- 두 손가락 위로 쓸면 상시 항목 전체를 숨긴다(`persistentHidden`). 새 상시 항목이 생기면 숨김이 풀린다 (Activity/ActivityCenter.swift:38-59, 130-133).

### 3.5 확장 화면과 페이지

- 확장 화면은 `ExpandedPage`가 `.home` 또는 `.activity(kind)`인 두 갈래다 (Notch/NotchViewModel.swift:52-55).
- 홈은 `HomeOption`(camera, timer, usage, memo, calendar, tray)을 `homeOrder`대로, 꺼진 것을 빼고 나열한다 (Notch/NotchViewModel.swift:9-50, 104-119).
- 활동 페이지는 `AppDelegate.pagedKinds`(timer, media, recording, call, download, aiUsage)만 전용 화면이 있고, 그 밖은 PersistentInfoPage로 대신한다 (App/AppDelegate.swift:342; Notch/NotchRootView.swift:126-190).
- 다운로드 페이지는 지금 `displayed`가 다운로드일 때만 그려진다 (Notch/NotchRootView.swift:179-182).
- 페이지 이동은 두 손가락 가로 스크롤 50pt이고, 아래 점은 표시용이다 (Notch/NotchController.swift:313-358).

### 3.6 애니메이션

- 열기 spring bounce 0.2, 닫기 0.08, 팝업 전환 0.42초 (Notch/NotchViewModel.swift:337-349).
- 열 때 squash/stretch (Notch/NotchViewModel.swift:353-373).
- compact에서 활동이 바뀌면 0.24초 접었다 다시 펼침 (Notch/NotchViewModel.swift:170-221).
- 음악 앨범 아트는 노치 날개와 팝업 사이를 이어서 움직인다(`mediaArtRect`, `mediaArtPageShift`) (Notch/NotchViewModel.swift:377-406; Notch/NotchRootView.swift:74-89).

### 3.7 새 기능을 붙이는 자리

- **새 라이브 활동** (5곳):
  1. `ActivityKind`에 종류를 더하고 필요하면 우선순위 상수를 정한다 (Activity/NotchActivity.swift:3-20).
  2. 감시기를 만들어 `center.post`나 `center.setPersistent`를 부르게 하고 `AppDelegate`에서 연결한다 (App/AppDelegate.swift:5-187).
  3. 상시 항목이면 `persistentOrder` 기본값과 설정 "우선순위" 페이지에 넣는다 (Settings/AppSettings.swift; Settings/SettingsView.swift:294-326).
  4. 전용 확장 화면이 필요하면 `pagedKinds`, `handleClick`, `NotchRootView.activityPage`를 고친다 (App/AppDelegate.swift:342-413; Notch/NotchRootView.swift:126-190).
  5. 시험용으로 `PreviewID`에 미리보기를 더한다 (Features/Preview/FeaturePreview.swift:8-31).
- **새 홈 페이지(탭)** (6곳):
  1. `HomeOption` 열거형과 그 key·제목·기호 (Notch/NotchViewModel.swift:9-50).
  2. `defaultHomeOrder`.
  3. `HomePages`/`NotchFeatures` 구조 (Notch/NotchRootView.swift:6-15, 126-190).
  4. `HomePager`의 분기 (Features/Home/HomeView.swift:5-56).
  5. `targetSize`/`popupSize`의 크기 (Notch/NotchViewModel.swift:224-275).
  6. 설정 "기본 기능" 페이지 (Settings/SettingsView.swift:438-490).

### 3.8 확장할 때 부딪히는 한계

- **여러 라이브 활동 동시 표시**: 접힌 노치는 활동 하나만 그린다. 좌우 날개를 서로 다른 활동에 나눠 주는 구조가 없고, `secondary`는 쓰이지 않는다. 일회성 알림이 오면 상시 항목은 가려진다. 높은 우선순위 알림이 오면 지금 알림은 대기열로 가지 않고 사라진다.
- **호버 미리보기(peek)**: 지금은 크기만 조금 키운다(C003). 내용을 보여 주는 중간 상태가 `NotchState`에 없다. `hoverToOpen`은 바로 전체 팝업을 연다. 미리보기 내용을 넣으려면 상태 하나를 새로 만들거나 detail 상태를 호버용으로 재사용해야 한다.
- **탭**: 탭 막대가 없고 점·스와이프만 있다. `ExpandedPage`와 `HomeOption`이 닫힌 열거형이라 탭 하나를 더하면 약 6곳을 고쳐야 한다. 패널이 720×300pt로 고정이라 카메라 페이지가 이미 점 영역을 합쳐 약 290pt를 쓴다. 더 큰 탭 화면은 패널 크기부터 바꿔야 한다 (Notch/NotchGeometry.swift:5; Notch/NotchViewModel.swift:280-304).
- **명령 팔레트**: 전역 단축키가 없다. 패널은 nonactivating이고 입력 칸을 누를 때만 키 창이 된다(`becomesKeyOnlyIfNeeded`). 단축키로 노치를 열고 바로 글자를 받으려면 단축키 등록, 키 창 전환, 포커스 반환을 새로 만들어야 한다 (Notch/NotchPanel.swift:22-55).
- **빠른 설정(노치 안 토글)**: 설정 화면은 별도 보조 프로세스에 있다. 본 앱이 값을 바꾸면 UserDefaults에는 저장된다. 하지만 `save`는 보조 프로세스일 때만 변경 알림을 보내므로, 열린 설정 창에는 바뀐 값이 바로 반영되지 않는다 (Settings/AppSettings.swift:514-521). 또 `hotspotPinned`, `focusPinned`, `trayCleanupDays`처럼 다음 사건이나 다음 실행 때 반영되는 설정이 있다. 그래서 토글을 눌러도 바로 바뀌지 않는 항목이 생긴다.

## 4. 로컬 커스텀 변경

### 4.1 소스 변경 (`8105e6f` → `50ebc7b`, 7개 파일, +132/−14)

| 파일 | 변경 | 근거 |
|---|---|---|
| App/AppDelegate.swift | 명령 채널에 `agent:` 명령 추가, `postAgentDone`(설정 `agentAlerts` 확인, 출처 claude·codex만, 프로젝트 이름 40자), `agentIcon`(Claude `com.anthropic.claudefordesktop`, Codex `com.openai.codex` 안의 `icon-codex-dark-color.png`·`icon-codex-light.png`, 72px 캐시) | App/AppDelegate.swift:166-167, 179, 189-233 |
| Features/Agent/AgentNotify.swift | 작업 내용·대상 앱이 없으면 부제를 "작업 완료"로(클릭해서 열 대상이 없으므로 "눌러서 열기"를 빼기) | Features/Agent/AgentNotify.swift:144-146 |
| Features/Screenshot/ScreenshotMonitor.swift | 스크린샷 폴더 감시(DispatchSource) 추가, 파일 확장 속성으로 스크린샷 여부 확인, 저장 완료 확인, 같은 파일 중복 표시 방지 | Features/Screenshot/ScreenshotMonitor.swift:29-31, 73-77, 116, 123-180 |
| Monitors/RecordingMonitor.swift | 화면을 캡처하는 쪽이 있을 때만 캡처 UI 창을 보고 녹화로 판단(⌘⇧4 영역 선택 화면을 녹화로 오인하던 문제) | Monitors/RecordingMonitor.swift:191, 195 |
| Notch/NotchController.swift | 노치 가운데가 0.5pt에 걸리면 창 폭을 늘려 가운데를 맞춤 | Notch/NotchController.swift:135-139 |
| Notch/NotchViewModel.swift | 호버 미리보기 몸통 폭을 노치+14에서 노치+2×(topRadius+1)로 | Notch/NotchViewModel.swift:228-231 |
| Settings/AppSettings.swift | 기본값 `agentStyle` compact→detail, `screenshotSource` clipboard→both (초기화와 다시 읽기 두 곳씩) | Settings/AppSettings.swift:355, 379, 472, 496 |

현재 사용자 설정값(`defaults read com.dynamicnotch.app`)은 `autoUpdate`=0이고, `agentStyle`과 `screenshotSource`는 저장된 값이 없어 위의 로컬 기본값을 따른다.

### 4.2 외부 구성 요소

**`~/.local/bin/notch-agent-done`** (JXA 스크립트, 314줄)

- 첫 인자가 `claude`이면 Claude Code Stop 훅, `codex`이면 Codex notify로 동작한다.
- 보내는 명령은 `com.dynamicnotch.app.command` 분산 알림의 `agent:<출처>|<프로젝트>`다. 프로젝트 이름에서 `\r`, `\n`, `|`를 빼고 40자로 자른다 (86-90행).
- 프로젝트 이름은 작업 폴더 이름이다. `.claude/worktrees` 경로는 "저장소 · worktree" 꼴로 줄인다.
- **Claude 경로**: 아래 둘 중 하나라도 남아 있으면 보내지 않고 로그에 "skipped, still running"을 남긴다.
  - claude 프로세스의 자식 중 shell-snapshots가 들어간 명령(백그라운드 셸)
  - `subagents/agent-*.meta.json` 중 백그라운드이고 끝나지 않은 하위 에이전트(30분 넘게 조용하면 끝난 것으로 봄)
- **Codex 경로**: 먼저 이전 notify(SkyComputerUseClient `turn-ended`, 27-30행)를 실행한다. 그다음 `agent-turn-complete` 사건만 다룬다.
  - `~/.codex/state_<n>.sqlite`를 `/usr/bin/sqlite3 -readonly`로 읽는다. 읽을 수 없으면 `sessions/YYYY/MM/DD` 기록 파일을 본다.
  - 위에서 찾은 기록으로 주 스레드와 하위 에이전트가 아직 진행 중인지 확인한다.
  - 대화가 아닌 스레드는 건너뛴다. 최근 6시간 안의 기록만 본다.
- 로그는 `~/Library/Logs/notch-agent-done.log`(100KB에서 교체)다. 2026-11-02 기준 Codex 관련 줄이 284개 있다. 마지막 줄은 `2026-11-02T03:00:38.176Z codex me [01a0c6e2-c9ec Codex Desktop] posted`이다.

**Claude Stop 훅** (`~/.claude/settings.json` 8-18행, 권한 0600)

```json
"Stop": [{"hooks": [{"type": "command", "command": "/Users/me/.local/bin/notch-agent-done claude 2>/dev/null || true", "timeout": 10, "async": true}]}]
```

**Codex notify** (`~/.codex/config.toml` 6행, 권한 0600, 수정 시각 11월 1일 10:26)

```toml
notify = ["/Users/me/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient", "turn-ended", "--previous-notify", "[\"\\/Users\\/me\\/.local\\/bin\\/notch-agent-done\",\"codex\"]"]
```

- 백업 `~/.codex/config.toml.bak-notch-20261027`의 3행은 `notify = [".../SkyComputerUseClient", "turn-ended"]`이다. notch-agent-done이 들어가기 전 상태다.
- `docs/notchy-parity/BASELINE.md`는 notify 값을 `["/Users/me/.local/bin/notch-agent-done","codex"]`로 적었는데, 실제 설정과 다르다. 실제로는 SkyComputerUseClient가 맨 앞이고, notch-agent-done은 `--previous-notify` 인자로 들어 있다.
- 추정(확인 안 함): 지금 구성에서는 한 턴에 SkyComputerUseClient `turn-ended`가 두 번 실행될 수 있다.
  1. Codex가 SkyComputerUseClient를 부른다.
  2. SkyComputerUseClient가 `--previous-notify`로 notch-agent-done을 부른다.
  3. notch-agent-done이 이전 notify로 SkyComputerUseClient를 다시 부른다.

### 4.3 앱 안 "연결·해제" 버튼을 누르면 생기는 일

`AgentHooks.isInstalled`는 설정 파일에 `--agent-done=<출처>` 글자가 있는지만 본다 (Features/Agent/AgentNotify.swift:184-187). 지금 두 설정 파일 모두 그 글자가 없으므로 설정 창은 Claude Code·Codex 둘 다 "연결 안 됨"으로 보여 준다.

- **Claude 연결**:
  - `hooks.Stop`에 `"<앱 실행 파일>" --agent-done=claude` 훅을 하나 더 붙인다 (Features/Agent/AgentNotify.swift:221-230). 그러면 Stop마다 업스트림 경로(백그라운드 작업이 남아 있어도 바로 알림)와 notch-agent-done 경로(다 끝났을 때만 알림)가 둘 다 돈다. 알림이 겹치고, 기다려야 할 때도 알림이 뜬다.
  - 파일은 JSONSerialization으로 다시 써진다(prettyPrinted, atomic, Features/Agent/AgentNotify.swift:214-219). 키 순서와 서식이 바뀐다. 파일 권한 0600이 유지되는지는 확인하지 않았다.
  - 바꾸기 전에 `settings.json.dynamicnotch.bak`을 만든다 (Features/Agent/AgentNotify.swift:197-202).
- **Claude 해제**: `--agent-done=claude`가 들어간 훅만 지운다 (232-245행). notch-agent-done 훅은 남지만, 이때도 파일 전체를 다시 쓴다.
- **Codex 연결**: 지금 notify 전체를 이전 notify로 감싼다 (280-295행). 결과는 `[<앱 실행 파일>, "--agent-done=codex", "--chain", <SkyComputerUseClient>, "turn-ended", "--previous-notify", <notch-agent-done JSON>, "--end-chain"]`이다. 업스트림 경로가 먼저 알림을 보낸 뒤 기존 체인이 돌아 notch-agent-done도 알림을 보내므로 Codex 알림이 겹친다. 업스트림 경로에는 하위 에이전트 대기가 없다.
- **Codex 해제**: `--chain … --end-chain` 사이를 원래 notify로 되돌린다 (297-307행).

정리하면 지금 로컬 구성(notch-agent-done 경로)을 유지하는 동안에는 설정 창의 연결 버튼을 누르면 안 된다. 업스트림을 따라갈 때는 이 버튼을 숨기거나, `isInstalled`가 notch-agent-done도 연결로 인식하게 바꿔야 한다.

## 5. 빌드·배포

### 5.1 `scripts/build.sh` (79줄)

- 옵션: `--dev`(`-DDEV`, notchctl 명령 허용), `--zip`, `--install`, `--run`.
- 빌드: `swift build -c release --arch arm64`(경로 접두사 매핑 포함).
- 앱 조립: Info.plist·아이콘·lproj 복사, clang으로 `libMRAdapter.dylib` 빌드.
- 서명: `codesign --force --deep --sign - --requirements "=designated => identifier \"com.dynamicnotch.app\""`, 즉 ad-hoc 서명에 지정 요구 조건으로 번들 ID를 고정한다.
- `--zip`: zip과 `.sha256` 파일을 만든다. 업데이터가 이 해시 파일을 확인한다.
- `--install`(67-73행): `pkill -x DynamicNotch` 뒤 `rm -rf "/Applications/Dynamic Notch.app"`, 그다음 `cp -R`. 설치된 앱을 백업 없이 지운다.
- `--run`: pkill 뒤 open.

### 5.2 이 Mac에서 쓰는 빌드 경로

- **`~/.local/share/dynamic-notch-agent/build-direct.sh <src> <out>`**
  - SwiftPM 매니페스트 링크가 이 Mac에서 깨져 있어 `swift build` 대신 쓴다.
  - 모든 Swift 파일을 `swiftc -O -wmo`로 한 번에 컴파일한다. 그 뒤 앱 조립, clang dylib, ad-hoc 서명은 build.sh와 같다.
  - 설치는 하지 않는다.
- **같은 폴더의 다른 파일들**:
  - `base-commit.txt`는 `43b1200`(1.0.8 기준)이고, 지금 기준과 맞지 않는다.
  - `agent-alert.patch`는 1.0.8용이라 지금 트리에 그대로 적용되지 않는다.
  - 백업: `original-1.0.8/`, `previous-app/`, `previous-app-20261102/`, `notch-agent-done.bak-*`, `settings-backup-20261102.plist`(`autoUpdate` false, `onboardingDone` true, `btSymbolCache`, `trayItems` []).
- **`scripts/review.sh`** (`0290f93`에서 추가)
  - swiftc로 `~/Developer/Dynamic-Notch-build/review`에 "Dynamic Notch Review"를 빌드한다.
  - 번들 ID는 `com.dynamicnotch.app.review`, 실행 파일은 `DynamicNotchReview`, dylib install_name은 `@rpath`다.
  - 명령은 `build`, `start`(설치된 앱을 끔), `stop`, `status`다.
- 설치된 앱은 BASELINE.md 기준으로 1.0.8 빌드 9 커스텀판이다.

### 5.3 앱 정보 (`Resources/Info.plist`)

- 번들 ID `com.dynamicnotch.app`, `CFBundleShortVersionString` 1.2.2, `CFBundleVersion` 14.
- `LSUIElement` true(Dock 아이콘 없음), `LSMinimumSystemVersion` 14.0, arm64.
- 사용 목적 문구: Apple Events, 블루투스, 캘린더(전체), 카메라, 데스크톱, 다운로드, 집중 모드 상태, 위치. 마이크 문구는 없다.

### 5.4 자동 업데이트

- **확인 시점**: 시작 30초 뒤, 이후 1시간마다 확인하되 24시간이 지났을 때만 실제로 요청한다 (App/Updater.swift:23-36).
- **대상**: GitHub Releases API `jinwithbryxn/Dynamic-Notch`의 최신 릴리스 (App/Updater.swift:11, 39-59).
- **확인 단계**: 다운로드 크기는 해시 파일 5MB, 앱 zip 100MB까지 받는다 (172-184행). 받은 뒤 아래를 확인한다 (65-118행).
  - `.zip.sha256` 자산과 SHA-256 일치
  - `codesign --verify --deep --strict` 통과(무결성만 보고 서명자는 보지 않음)
  - 같은 번들 ID
  - 더 높은 `CFBundleShortVersionString`
- **교체 방식**: `/bin/sh` 스크립트가 앱 종료를 기다린다. 그다음 기존 앱을 `.Dynamic Notch.app.old`로 옮겨 새 앱으로 바꾸고 다시 연다 (121-144행).

## 6. 기술 부채·위험

### 6.1 확장할 때의 위험

1. **업스트림 자동 업데이트가 로컬 빌드를 덮어씀**:
   - 로컬 빌드도 번들 ID가 같고 버전이 1.2.2다. 업데이터는 서명자를 확인하지 않는다.
   - 그래서 `autoUpdate`가 켜지면 업스트림 1.2.3 이상이 로컬 커스텀 빌드를 그대로 교체한다.
   - 기본값은 true이고, 지금은 사용자 값 0으로 막혀 있다. 설정을 초기화하거나 새 Mac에 설치하면 다시 켜진다.
2. **설치 스크립트가 설치된 앱을 지움**:
   - `build.sh --install`은 `/Applications/Dynamic Notch.app`을 백업 없이 지운다.
   - SwiftPM 빌드가 이 Mac에서 깨져 있어, 실제로는 build-direct.sh나 review.sh를 써야 한다.
3. **비공개 API 의존**: 하나라도 macOS 업데이트로 바뀌면 그 기능이 조용히 멈출 수 있다.
   - SkyLight: 잠금 화면, 녹화 감지
   - MediaRemote(perl 우회): 재생 정보
   - DisplayServices, CoreBrightness: 밝기
   - TelephonyUtilities: 전화
   - IOPSCopyPowerSourcesByType: 블루투스 배터리
   - DoNotDisturb DB 파일 형식: 집중 모드
4. **한 번에 하나만 보이는 구조**:
   - 접힌 노치는 활동 하나만 그린다. 일회성 알림은 하나이고, 대체된 알림은 사라진다.
   - 여러 라이브 활동, 호버 미리보기 내용, 탭을 더하려면 `ActivityCenter`·`NotchState`·크기 계산을 함께 바꿔야 한다.
   - 패널이 720×300pt 고정이라 큰 화면은 패널 크기부터 바꿔야 한다.
5. **닫힌 열거형**: `ActivityKind`, `HomeOption`, `ExpandedPage`, `PreviewID`가 모두 switch로 퍼져 있다. 기능 하나를 더할 때 5-6곳을 같이 고쳐야 하고, 빠뜨려도 컴파일러가 잡지 못하는 곳(설정 순서 기본값, 미리보기 목록)이 있다.
6. **인증 없는 명령 채널**:
   - 분산 알림 `com.dynamicnotch.app.command`는 아무 프로세스나 보낼 수 있다.
   - 배포 빌드는 허용 목록으로 막지만, 로컬에서 더한 `agent:`도 누구나 보낼 수 있다. 다만 제목과 아이콘은 정해진 값이고 프로젝트 이름은 40자로 자른다.
   - 명령을 늘릴수록 이 범위가 넓어진다.
7. **에이전트 훅 중복**: 4.3절대로, 설정 창의 연결 버튼을 누르면 Claude·Codex 알림이 겹치고 Claude 설정 파일 서식이 바뀐다. 업스트림을 따라갈 때 이 버튼과 로컬 경로를 어떻게 합칠지 정해야 한다.

### 6.2 그 밖의 부채

- **꺼도 도는 타이머·감시**:
  - 녹화 감지 1.5초 폴링(`recordingEnabled`가 false여도)
  - HUD 이벤트 탭(HUD를 모두 꺼도), 손쉬운 사용 권한이 없으면 3초 재시도 타이머가 계속 돎
  - 블루투스 권한 대기 3초 타이머
  - 전체 디스크 접근이 없으면 집중 모드 5초 폴링
  - 스크린샷 파일 감시(`screenshotEnabled`가 false여도 소스 설정만 봄, Features/Screenshot/ScreenshotMonitor.swift:69-79)
  - 클립보드 0.5초 폴링
  - 메모리 지킴이 300초, 업데이터 1시간
- **정리 누락**:
  - NSMetadataQuery 관찰자를 지우지 않는다 (Features/Screenshot/ScreenshotMonitor.swift:105-122).
  - 스크린샷 폴더 감시는 시작할 때의 저장 위치에 고정된다. 저장 위치를 바꾸면 다시 시작해야 한다.
- **쓰이지 않거나 늦게 반영되는 설정**:
  - `btShowDisconnect`, `lockWidgetBottom`은 읽는 코드가 없다.
  - `hotspotPinned`, `focusPinned`는 다음 사건 때 반영된다.
  - `trayCleanupDays`는 시작할 때만 돈다.
  - 알림 권한은 요청만 하고 쓰지 않는다.
  - `ActivityCenter.secondary`는 쓰이지 않는다.
- **메인 스레드 AppleScript**: 음악 대체 알림 처리(`fallbackNotification`)가 AppleScript를 메인 스레드에서 실행한다. Music·Spotify가 느리면 노치가 잠깐 멈출 수 있다 (Features/Media/MediaController.swift:259-280).
- **접근성 권한 시점**: 전화 배너 AX 관찰자는 앱 시작 때 권한이 있어야만 등록된다. 실행 중에 권한을 주면 다시 시작해야 전화 버튼 대체 경로가 동작한다 (Monitors/CallMonitor.swift:201-234).
- **일정 알림 범위**: 남은 일정 앞 3개만 알림 대상이다 (Features/Home/CameraAndCalendar.swift:217-233).
- **영구 삭제**: 메모 삭제는 휴지통을 거치지 않는다 (Features/Memo/MemoStore.swift).
- **설정 기본값 중복**: 기본값이 초기화와 다시 읽기 두 곳에 따로 적혀 있다. 로컬 변경도 두 곳을 같이 고쳤다. 한쪽만 고치면 설정 창을 연 뒤 값이 바뀐다 (Settings/AppSettings.swift:278-506).
- **외부 스크립트**:
  - notch-agent-done이 기록 파일에서 읽은 `root` id를 검증 없이 SQL 문자열에 넣는다. 다만 데이터베이스를 읽기 전용으로 연다.
  - `base-commit.txt`와 `agent-alert.patch`가 1.0.8 기준으로 남아 있어 혼동될 수 있다.
- **문서 불일치**: BASELINE.md의 Codex notify 줄이 실제 설정과 다르다 (4.2절).
