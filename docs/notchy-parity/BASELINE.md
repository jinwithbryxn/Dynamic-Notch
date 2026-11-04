# 기준 상태 (2026-11-02)

Notchy 기능 확장 작업을 시작하기 전의 설치 앱, 로컬 커스텀 변경, 1.2.2 소스를 대조한 기록이다.

## 1. 실행 환경

| 항목 | 값 |
| --- | --- |
| macOS | 26.5.2 (25F84) |
| 내장 화면 | 1512×982 pt, 2배율, 물리 노치 663–848 pt(폭 185 pt, 높이 32 pt, 가운데 755.5 pt) |
| 외부 화면 | 3440×1440 pt, 1배율, 노치 없음 |
| CPU | Apple Silicon (arm64) |
| 빌드 도구 | swiftc 직접 빌드. 이 Mac은 SwiftPM 매니페스트 링크가 깨져 있어 `swift build`를 쓰지 않는다 |

## 2. 설치 앱

| 항목 | 값 |
| --- | --- |
| 경로 | `/Applications/Dynamic Notch.app` |
| 버전 | 1.0.8 (build 9) |
| 번들 ID | `com.dynamicnotch.app` |
| 서명 | ad-hoc, 지정 요구사항을 번들 ID로 고정 |
| 자동 업데이트 | 꺼짐 (`autoUpdate = false`) |

### 설치 바이너리와 보관 패치의 일치 확인

깨끗한 `43b1200`(1.0.8)에 `~/.local/share/dynamic-notch-agent/agent-alert.patch`만 적용해 같은 스크립트(`build-direct.sh`)로 다시 빌드하고 설치본과 비교했다.

- 실행 파일 `DynamicNotch`: 서명을 제거하면 바이트 단위로 같다. LC_UUID `6B55613E-B272-3F33-B9CA-8A5B82A10D6B`도 같다.
- `libMRAdapter.dylib`: 설치 이름(LC_ID_DYLIB)에 빌드 출력 폴더 경로가 들어가서만 다르다. 패치는 이 파일의 소스를 바꾸지 않는다.
- `Info.plist`, `mr_run.pl`: 같다.

따라서 설치 앱은 `43b1200` + 보관 패치로 만든 것이다. 검토용 빌드 스크립트(`scripts/review.sh`)는 dylib 설치 이름을 `@rpath/libMRAdapter.dylib`로 고정해 이 차이를 없앤다.

### 유휴 자원 사용 (설치본, 노치 접힘, 1분 측정)

| 항목 | 값 |
| --- | --- |
| CPU | 0.0–0.2 % |
| 메모리(top MEM) | 24–25 MB, RSS 57 MB |
| 전력 점수(top POWER) | 0.0–0.2 |
| 스레드 | 5–6 |

### 사용자 설정 백업

`~/.local/share/dynamic-notch-agent/settings-backup-20261102.plist` (`defaults export com.dynamicnotch.app`). 대부분 기본값이며 선반은 비어 있다.

## 3. 보존해야 하는 로컬 커스텀 변경

보관 패치(`agent-alert.patch`, 267행)와 외부 스크립트로 이루어진다.

| 변경 | 위치 | 비고 |
| --- | --- | --- |
| Claude Code·Codex 완료 알림 | 앱: 분산 알림 `com.dynamicnotch.app.command`의 `agent:<claude\|codex>\|<프로젝트>` 명령. 외부: `~/.local/bin/notch-agent-done` | 실제 앱 아이콘 사용. 프로젝트 이름은 40자까지만 받는다 |
| 작업이 남아 있으면 알림 미루기 | `notch-agent-done` | Claude: 백그라운드 명령·Monitor·백그라운드 하위 에이전트. Codex: 상위 스레드와 하위 에이전트가 모두 턴을 마쳤는지 Codex 상태 DB(`~/.codex/state_<n>.sqlite`)와 rollout으로 확인. 내부 보조 스레드는 무시 |
| Codex 기존 notify 보존 | `notch-agent-done`이 Codex Computer Use notify를 먼저 실행 | `~/.codex/config.toml`의 `notify` |
| 스크린샷 감지 지연·중복 개선 | `ScreenshotMonitor.swift` | 폴더 직접 감시 + 화면 캡처 xattr, Spotlight 질의는 보조. 기본 감지 대상을 '둘 다'로 |
| 영역 캡처의 녹화 오인 수정 | `RecordingMonitor.swift` | 화면 감시자(SLSIsScreenWatcherPresent)가 있을 때만 스크린샷 창을 녹화 근거로 본다 |
| 호버 테두리 | `NotchController.swift`, `NotchViewModel.swift` | 노치 가운데가 0.5 pt에 걸리면 패널 폭을 1 pt 늘려 가운데를 맞추고, 호버 몸통을 노치보다 양옆 1 pt 넓게 |

연결 설정:

- `~/.claude/settings.json`: Stop 훅 `/Users/me/.local/bin/notch-agent-done claude 2>/dev/null || true` (async, timeout 10)
- `~/.codex/config.toml`: Codex Computer Use가 2026-11-01에 `notify`를 고쳐, 지금은 `SkyComputerUseClient turn-ended --previous-notify '["/Users/me/.local/bin/notch-agent-done","codex"]'`이다. Computer Use가 먼저 실행되고 이 스크립트를 이어서 부른다. 처음 연결할 때(2026-10-27)는 반대로 이 스크립트가 notify였고 Computer Use를 먼저 불렀다. 2026-11-02부터 스크립트는 부모 프로세스가 Computer Use이면 Computer Use를 다시 부르지 않는다(그 전에는 턴마다 두 번 불렸다).

## 4. 1.2.2 비교

- 기준 커밋 `43b1200`(1.0.8) 이후 `8105e6f`(1.2.2, build 14)까지 19개 커밋, 30개 파일, +3458/−538행.

1.2.2에서 새로 생긴 기능 (설치본에는 없음):

| 기능 | 커밋 | 로컬 변경과의 관계 |
| --- | --- | --- |
| AI 사용량 (Claude, ChatGPT, Gemini): 홈 페이지, 노치 표시, 웹 로그인, 갱신 주기 | f6f847d, 8f1e5d2, f464359 | 겹치지 않음 |
| Claude Code·Codex 완료 알림 (`--agent-done=` 훅, `com.dynamicnotch.app.agent`, 설정에서 연결·해제, 눌러서 앱 열기, 끝난 작업 문구) | 203a5f2, c143a5a | 겹침. 기존 훅은 하위 작업이 남아 있어도 매번 알린다 |
| 메모 (홈, 자동 저장, 목록) | 7a704f0, 6932989 | 겹치지 않음 |
| 홈 기능 순서·끄기, 노치 안 편집 단축키, AirDrop·트레이 숨기기 | 5f2376f | 겹치지 않음 |
| ⌘⇧5 스크린샷 뒤 녹화 오인 수정 | 1727aa4 | 부분 겹침. ⌘⇧4 영역 선택 오인은 1.2.2에 없다 |
| 설정 창 Liquid Glass 디자인 | 492ebda, 2c0e1b6 | 겹치지 않음 |
| 라이브 활동 넘겨 보기, 컴팩트 글꼴, 핫스팟·Focus 아이콘 | 8f1e5d2, 7212ade, cc427ae | 겹치지 않음 |
| Face Unlock 보안·개인정보 설계 문서 (구현 없음) | ce77a70 | - |

## 5. 개발 기준

- 개발 저장소: `~/Developer/Dynamic-Notch`, 브랜치 `notchy-parity`.
- 기준: 1.2.2(`8105e6f`) 위에 로컬 패치를 옮긴 커밋 `50ebc7b`. 1.0.8 기준으로 진행하면 1.2.2가 이미 만든 AI 사용량·메모·에이전트 알림을 다시 만들게 되므로 최신 1.2.2를 기준으로 삼았다.
- 충돌 처리: `NotchActivity.swift`(양쪽 모두 `.agent` 추가)와 `AppDelegate.swift`(명령 채널)만 충돌했다. `agent:` 명령은 1.2.2의 에이전트 알림 모양·켜고 끄기 설정을 따르게 했고, 기본 모양은 지금까지 보던 상세 카드로 두었다.
- 빌드: `50ebc7b`는 `build-direct.sh`로 빌드된다. 실제 Mac에서 실행 검증은 아직 하지 않았다.

## 6. 빌드·설치 안전 수칙

- `scripts/build.sh --install`은 `pkill -x DynamicNotch` 후 `/Applications/Dynamic Notch.app`을 지우고 복사한다. `--run`도 같은 이름의 프로세스를 모두 끝낸다. 검증 전에는 쓰지 않는다.
- 검토용 앱은 `scripts/review.sh`로 만든다. 이름 `Dynamic Notch Review`, 번들 ID `com.dynamicnotch.app.review`, 실행 파일 `DynamicNotchReview`로 설치본과 설정·권한·프로세스가 섞이지 않는다. 분산 알림 채널은 같으므로 두 앱을 동시에 켜지 않는다(`start`가 설치본을 정상 종료하고, `stop`이 다시 띄운다).

## 7. 복원 자료

| 자료 | 위치 |
| --- | --- |
| 1.0.8 앱 | `~/.local/share/dynamic-notch-agent/original-1.0.8/` |
| 스크린샷 수정 전 앱 | `~/.local/share/dynamic-notch-agent/previous-app/` |
| 호버 수정 전 앱 | `~/.local/share/dynamic-notch-agent/previous-app-20261102/` |
| 패치 이전 판 | `agent-alert.patch.bak-20261101`, `agent-alert.patch.bak-20261102` |
| 알림 스크립트 이전 판 | `notch-agent-done.bak-20261027`, `.bak-20261101`, `.bak-20261102` |
| 설정 백업 | `settings-backup-20261102.plist` |
