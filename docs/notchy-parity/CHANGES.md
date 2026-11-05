# 변경 기록 (notchy-parity)

기준: 1.2.2 `8105e6f` (1.2.2) + 로컬 에이전트 알림 패치(`50ebc7b`). 아래는 그 위에 더한 변경이다.

## 공통 노치 상태 (P1)

| 변경 | 파일 | 대조표 행 |
|---|---|---|
| 확장 기능 규약: `NotchModule`, 등록부, 기능별 설정 저장, 키체인 저장소, 전역 단축키, 이전 앱 붙여넣기, 딥링크 처리기 | `Modules/Core/*` | M-A-009, M-H-004, M-H-017, M-K-027 |
| 확장 패널 탭 페이지(`ExpandedPage.module`)와 탭 크기에 맞춘 도형 크기 | `Notch/NotchViewModel.swift`, `NotchRootView.swift` | M-A-006, M-A-023 |
| 확장 패널 아래 독: 홈 점 · 고정 탭 · 모든 도구/명령 · 열림 고정 | `Modules/Core/CommandPalette.swift` | M-A-014, M-A-019, M-A-020 |
| 명령 팔레트: 전역 단축키(기본 ⌃⌥K), 모든 도구 격자, 기능별 즉석 결과, ↑↓·Return·Esc | `Modules/Core/CommandPalette.swift`, `PaletteSupport.swift`, `App/AppDelegate.swift` | M-H-005, M-H-007(타이머) |
| ⌘1–9 칸 이동, Esc 닫기, 두 손가락 좌우로 홈 → 고정 탭 순서 넘기기 | `Notch/NotchPanel.swift`, `NotchViewModel.swift` | M-H-006, M-A-016 |
| 상세 카드 버튼(`ActivityAction`) — 에이전트 승인 허용·거부 등 | `Activity/NotchActivity.swift`, `ActivityViews.swift` | M-K-018 |
| 두 번째 라이브 활동을 노치 오른쪽에 떨어진 동그라미로 (다이나믹 아일랜드 minimal) | `Notch/IslandExtras.swift`, `NotchRootView.swift`, `NotchController.swift` | M-A-008, M-A-010 |
| 다이내믹 아일랜드 모양 맞추기 (1.2.5): 연속 곡률 아래 모서리, 작은 표시 양끝 반원, 펼친 카드·확장 반경 38pt, 어두운 모드 둘레 선, 카드의 노치 옆 아이콘·값 칸, 글자 단계(`IslandText`)와 medium 이상 굵기, SF Pro | `Notch/IslandStyle.swift`, `NotchShape.swift`, `NotchViewModel.swift`, `NotchRootView.swift`, `Activity/ActivityViews.swift`, 노치 화면 96개 파일의 글자 크기 | M-A-008, M-A-010 |
| 음악 호버 미리보기(미니 플레이어), 지연 설정 | `Notch/IslandExtras.swift`, `NotchController.swift` | M-A-005 |
| 더 중요한 알림에 밀려난 알림을 대기열로 되돌림 | `Activity/ActivityCenter.swift` | M-A-007 |
| 노치 없는 화면에서 메뉴바 아래 떠 있는 알약 | `Notch/NotchRootView.swift`, `NotchViewModel.swift` | M-A-002 |
| 화면 공유·녹화에서 노치 숨기기 요청 (`sharingType = .none`, 보장 안 됨) | `Notch/NotchController.swift` | M-A-047 |
| 홈 대시보드: 음악 · 타이머 · 다음 일정 · 확장 기능 카드 | `Features/Home/DashboardPage.swift` | M-A-022(일부) |
| 설정 → 확장 기능: 아일랜드 옵션, 팔레트 단축키, 기능별 켜기·독 고정·세부 설정 | `Modules/Core/PaletteSupport.swift`, `Settings/SettingsView.swift` | M-L-024 |
| 호버로 열기 지연(0–1.5초), 더블클릭으로 펼치기, 커서가 떠나면 접기(끔/즉시/0.5/1/2초), 알림 전용 모드 | `Notch/NotchController.swift`, `IslandExtras.swift` | M-A-011, M-A-013, M-A-032 |
| 노치 없는 화면의 쉬는 알약: 보이기 / 시계 / 커서를 올릴 때만 | `Notch/NotchRootView.swift`, `NotchViewModel.swift` | M-A-029, M-A-040 |
| 노치 창 크기 720×300 → 820×440 (넓은 탭) | `Notch/NotchGeometry.swift` | M-A-023 |

## 기존 기능 보존·안전 (P2)

| 변경 | 파일 | 대조표 행 |
|---|---|---|
| 개인 빌드 표시(`DMNCustomBuild`)가 있으면 업데이트 확인이 릴리스 파일로 교체하지 않고 알리기만 함 | `App/Updater.swift`, `Resources/Info.plist` | M-L-017 |
| 메모리 지킴이 기본 기준 70 → 150MB, 켜진 기능당 3MB 여유, 진행 중 작업이 있는 기능은 재시작 막음 | `Settings/AppSettings.swift`, `App/MemoryGuard.swift`, `App/AppDelegate.swift` | M-L-023 |
| 설치·복원 스크립트 (기존 앱은 지우지 않고 백업 폴더로 이동) | `scripts/install-local.sh` | M-L-017 |

## 통합 연결 (P3)

| 변경 | 파일 | 대조표 행 |
|---|---|---|
| 기능이 직접 찍은 영역 캡처(글자 인식·QR·마크업 등)를 녹화 감지에 알려, 영역 선택 화면을 녹화로 잘못 본 것을 거둠 | `Modules/Core/ModuleServices.swift`, `App/AppDelegate.swift` | M-G-001, 보존 수정(영역 캡처 ≠ 녹화) |
| 상시 표시 우선순위에 확장 기능 종류(카메라·마이크, 청소, 포모도로, 스톱워치, 잠자기 방지, 다음 일정, 알림 미러링, 시스템, 주식) 추가. 저장된 순서에는 기본 순서상 바로 앞 항목 뒤에 끼워 넣음 | `Settings/AppSettings.swift`, `Settings/SettingsView.swift` | M-A-009 |
| 청소 모드·키보드 잠금 전용 활동 종류(`.cleaning`)로 시스템 게이지와 겹치지 않게 함 | `Activity/NotchActivity.swift`, `Modules/Cleaning/CleaningModule.swift` | M-G-015, M-G-016 |
| 확장 기능 '캘린더'(카운트다운 켬)·'배터리'가 켜져 있으면 기존 일정·배터리 알림은 쉬어 같은 알림이 두 번 뜨지 않음 | `Features/Home/CameraAndCalendar.swift`, `Monitors/BatteryMonitor.swift` | M-D-002, M-I-010 |
| 자연어 명령의 타이머는 기본 타이머로 시작, 날씨는 잠금 화면 카드와 홈 대시보드 카드로 연결 | `App/AppDelegate.swift`, `Modules/Weather/WeatherModule.swift` | M-H-007, M-D-017, M-A-022 |
| 권한 설명 문구: 다른 앱 제어(브라우저 탭 제목·메모 저장·회의 통화), 일정 추가, 현재 위치 날씨 | `Resources/Info.plist`, `Resources/ko.lproj/InfoPlist.strings` | - |
| 집중 모드 동안 덜 중요한 알림 줄이기(선택, 기본 끔). 통화·배터리 부족·타이머 끝·에이전트 승인은 그대로 | `Activity/ActivityCenter.swift`, `Monitors/FocusMonitor.swift`, `Notch/IslandExtras.swift` | M-C-013 |
| 저장 링크 기능이 두 묶음에서 겹쳐 런처 묶음의 `savedlinks`만 남김 | `Modules/SavedLinks/` | M-D-016 |

## 기능 묶음

각 묶음은 `Modules/<이름>/` 아래에만 파일을 더했고, 기능 폴더 밖 파일은 바꾸지 않았다. 행별 상태는 `FEATURE-MATRIX.md`의 구현 상태 열과 `UNSUPPORTED.md`에 있다.

| 묶음 | 기능 id |
|---|---|
| 알림·잠금 화면 | `notifymirror`, `lockcards` |
| 미디어·오디오 | `audiodevices`, `soundmixer`, `spectrum`, `musictools`, `listenhistory`, `miniplayer`, `desktoplyrics`, `ytmusic`, `btbattery` |
| 클립보드·글자 | `clipboard`, `snippets`, `colors` |
| 실행·검색·입력 | `calculator`, `quicksearch`, `emoji`, `translate`, `launcher`, `launcherwheel`, `windowsnap`, `nlcommands`, `shortcuts`, `homeshortcuts`, `savedlinks`, `videosaver`, `inputtriggers`, `textactions`, `dictation`, `spaces` |
| 일정·할 일·메모·날씨 | `calendar`, `reminders`, `todo`, `applenotes`, `weather` |
| 파일·앱 관리 | `filetools`, `drives`, `packages`, `appdata` |
| 시간·집중·위젯 | `pomodoro`, `stopwatch`, `focussounds`, `keepawake`, `activity`, `screentime`, `breaks`, `focusswitch`, `typingsounds`, `desktopwidgets` |
| 시스템·하드웨어·주식 | `sysmon`, `netusage`, `batteryhealth`, `devices`, `keyhud`, `displays`, `stocks`, `ports` |
| 캡처·개인정보 | `capture`, `markup`, `teleprompter`, `presenter`, `cleaning`, `windowwatch`, `privacy`, `meeting`, `menubar`, `noticesounds` |
| 기본 예시 | `worldclock` |

## 검증 도구

- `--list-modules`, `--module-selftest=<id|all>`: 기능 목록·자체 검사.
- `--render-tab=<id>`: 탭 화면만 PNG로.
- `--render-notch=<home|dashboard|palette|module:id|compact|compact-two|compact-bubble|detail|detail-actions>`: 노치 전체를 실제 뷰로 PNG로. `DMN_NO_NOTCH=1`이면 노치 없는 화면.
- 화면 녹화 권한 없이 앱이 스스로 그리므로, 실제 화면 캡처와는 다르다(창 그림자·블러·실제 노치 위치는 확인 못 함).
