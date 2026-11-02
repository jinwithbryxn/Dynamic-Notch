# 변경 기록 (notchy-parity)

기준: upstream `8105e6f` (1.2.2) + 로컬 에이전트 알림 패치(`50ebc7b`). 아래는 그 위에 더한 변경이다.

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
| 개인 빌드 표시(`DMNCustomBuild`)가 있으면 업데이트 확인이 원본 릴리스로 교체하지 않고 알리기만 함 | `App/Updater.swift`, `Resources/Info.plist` | M-L-017 |
| 메모리 지킴이 기본 기준 70 → 150MB, 켜진 기능당 3MB 여유, 진행 중 작업이 있는 기능은 재시작 막음 | `Settings/AppSettings.swift`, `App/MemoryGuard.swift`, `App/AppDelegate.swift` | M-L-023 |
| 설치·복원 스크립트 (기존 앱은 지우지 않고 백업 폴더로 이동) | `scripts/install-local.sh` | M-L-017 |

## 검증 도구

- `--list-modules`, `--module-selftest=<id|all>`: 기능 목록·자체 검사.
- `--render-tab=<id>`: 탭 화면만 PNG로.
- `--render-notch=<home|dashboard|palette|module:id|detail-actions|compact-two|compact-bubble>`: 노치 전체를 실제 뷰로 PNG로. `DMN_NO_NOTCH=1`이면 노치 없는 화면.
- 화면 녹화 권한 없이 앱이 스스로 그리므로, 실제 화면 캡처와는 다르다(창 그림자·블러·실제 노치 위치는 확인 못 함).
