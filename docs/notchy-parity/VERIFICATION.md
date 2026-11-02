# 검증 기록 (notchy-parity)

2026-11-02 통합 빌드에 대해 무엇을 어떻게 확인했고 무엇을 확인하지 못했는지 적는다. 행별 상태는 `FEATURE-MATRIX.md`, 끝까지 되지 않은 행과 이유는 `UNSUPPORTED.md`에 있다.

검증은 세 단계로 나눈다.

1. 빌드: 컴파일과 서명이 되는지.
2. 자체 검사: 앱이 `--module-selftest`로 실제 macOS 호출을 하되 화면·사용자 데이터·시스템 상태를 바꾸지 않고 결과를 확인한다. 화면은 `--render-tab`·`--render-notch`로 앱이 스스로 그린다.
3. 실기: 실제 Mac에서 앱을 띄워 동작을 본다. 검토용 앱(`com.dynamicnotch.app.review`)은 번들 ID가 달라 손쉬운 사용·화면 기록·입력 모니터링·캘린더 등 권한이 하나도 없다. 권한이 필요한 경로는 실기에서 확인하지 못했다.

## 1. 빌드

| 항목 | 결과 |
|---|---|
| 기준 커밋 | `a31b8ec` (기능 묶음 10개 병합과 통합 연결 후) |
| 검토용 빌드 `scripts/review.sh build` | 성공, 오류 없음 |
| 기능 수 `--list-modules` | 76 |

## 2. 자체 검사

| 항목 | 결과 |
|---|---|
| `--module-selftest=all` | 종료 코드 0, 기능 76개 모두 실행, FAIL 0. 결과 파일: `~/Developer/Dynamic-Notch-build/verification/selftest-all-a31b8ec.txt` |
| 다른 앱 설정 파일 | `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.codex/config.toml`, `~/.zshrc`의 md5가 검사 전후 같음 (에이전트 훅·셸 연동은 사용자가 '연결'을 누를 때만 씀) |
| 검사 뒤 남은 포트 | 9999 등 대기 중인 포트 없음 |
| 상시 표시 우선순위 합치기 | 기존 사용자 순서(사용자 지정·기본)에 새 항목이 기본 순서상 앞 항목 뒤로 들어가는지 별도 스크립트로 확인 |

### 화면 그리기 (앱이 스스로 그린 PNG)

화면 녹화 권한 없이 앱이 실제 SwiftUI 뷰를 그린 것이다. 창 그림자·블러·실제 노치 위치는 실제 화면 캡처와 다를 수 있다.

- 통합 빌드: `~/Developer/Dynamic-Notch-build/verification/`
  - `int-palette.png` 명령 팔레트(켜진 도구 격자와 즉석 결과), `int-dashboard.png` 홈 대시보드, `int-module-pomodoro.png` 확장 탭 페이지와 아래 독
  - `notch-*.png`, `pill-*.png` 공통 노치 상태: 상세 카드 버튼, 두 활동, 옆 동그라미, 노치 없는 화면의 알약
- 기능 묶음별 탭 화면 119장: `~/Developer/Dynamic-Notch-build/wt-<묶음>/shots/`

## 3. 실기 (검토용 앱, 이 Mac)

| 항목 | 결과 |
|---|---|
| 실행 | 설치 앱을 잠시 끄고 검토용 앱 실행. 기본 켜짐 10개 + `localapi`, `sysmon`, `screentime`, `breaks`, `keepawake` (15개 실행) |
| CPU (쉬는 중, `top` 1초 간격 10회) | 0.7–3.7% |
| 메모리 (RSS) | 약 70–72MB. 메모리 지킴이 기준 150MB + 기능당 3MB = 195MB 아래 |
| 로컬 API | `127.0.0.1:9999`에만 열림(루프백). 줄 단위 JSON. 훅 범위 토큰으로 `status` 성공(scope `hook`, 허용 명령 `status`), 틀린 토큰 `unauthorized`, 훅 토큰으로 `show` 시도 `forbidden`, HTTP 요청 `http_not_supported` |
| 에이전트 완료 알림 | 기존 경로(`com.dynamicnotch.app.command`, `agent:claude|…`)로 보냄. 화면 캡처 권한이 없어 노치에 뜬 모습은 확인하지 못함 |
| 종료 | 아래 4절의 문제를 찾아 고친 뒤, 설정·권한 창 도우미가 떠 있는 상태에서 `review.sh stop`이 3초 만에 본 앱과 도우미를 모두 끝내고 설치 앱을 다시 띄움 |

### 보존한 로컬 수정

- 에이전트 알림(`Features/Agent`), 스크린샷 즉시 카드(`Features/Screenshot`), 녹화 감지(`Monitors/RecordingMonitor.swift`) 파일은 로컬 패치 커밋 `50ebc7b` 이후 바뀌지 않았다.
- 기능 묶음 10개는 모두 `Modules/<이름>/` 아래 파일과 `ModuleCatalog.swift`만 바꿨다.
- 기능이 직접 찍는 영역 캡처는 `ModuleServices.captureFinished()`로 녹화 감지에 알려 '영역 캡처 ≠ 녹화' 수정이 새 기능에서도 유지된다.

## 4. 실기에서 찾아 고친 문제

- 증상: 검토용 앱이 종료 요청을 받고도 꺼지지 않아 설치 앱과 함께 떠 있었다.
- 원인: 설정·권한(첫 안내) 창은 같은 실행 파일을 같은 번들 ID의 도우미 프로세스로 띄운다. `tell application id … to quit`이 본 앱이 아니라 도우미에 먼저 가서 도우미만 끝났다. 도우미가 없을 때는 바로 꺼졌다(3회 반복으로 확인). upstream 구조에서 온 동작이며 이번 기능 추가로 생긴 것은 아니다.
- 영향: 설정 창을 연 채로 설치·복원하면 `install-local.sh`가 "did not quit"으로 멈췄을 것이다(교체는 하지 않으므로 안전하지만 설치가 안 됨).
- 수정: `scripts/install-local.sh`와 `scripts/review.sh`가 본 앱과 도우미가 모두 끝날 때까지 2초마다 다시 종료를 요청한다(최대 15초).
- 참고: 검토용 앱과 설치 앱은 명령 채널 이름(`com.dynamicnotch.app.command`)이 같다. 둘을 동시에 띄우면 한쪽에 보낸 명령을 다른 쪽도 받는다. 검토용 앱을 띄울 때는 설치 앱을 끄므로 평소에는 겹치지 않는다.

## 5. 확인하지 못한 것

- 실제 화면 캡처: 셸에 화면 기록 권한이 없고, 화면 조작 도구는 `/Applications` 밖의 검토용 앱을 대상으로 잡지 못했다. 화면 모양은 2절의 자체 그리기 PNG로만 확인했다.
- 권한·하드웨어가 필요한 경로: `UNSUPPORTED.md` 5절 목록(화면 기록, 손쉬운 사용, 입력 모니터링, 마이크, 위치, 캘린더·미리 알림, 외장 디스플레이, USB 기기, 외장 드라이브, 실제 통화, API 키, 실제 에이전트 세션 등).
- macOS 14·15: 이 Mac(macOS 26)에서만 빌드·실행했다.
