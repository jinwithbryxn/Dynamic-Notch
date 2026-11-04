# Notchy 설정 레퍼런스 (패리티 조사용)

Dynamic Notch(notchy-parity 브랜치)에 Notchy 기능을 옮기기 위한 기준 자료다. Notchy 공식 도움말의 설정 레퍼런스를 행 단위로 정리했다. 문구는 모두 풀어 쓴 것이며 사이트 문장을 옮기지 않았다(설정 이름만 원문 그대로).

## 1. 조사 개요

| 항목 | 내용 |
| --- | --- |
| 조사일 | 2026-11-02 |
| 출처 | https://notchy.dev/help/settings/ |
| 레퍼런스 기준 버전 | 페이지 하단 표기상 Notchy 2.0.3 설정 화면 라벨, 2026-11-01 갱신 |
| 찾은 설정 페이지 | 34개 (기대치 34개) |
| 찾은 설정 행 | 513개 (기대치 513개). 사이드바의 페이지별 숫자와 34개 페이지 모두 일치한다 |
| 설명 문구 없는 행 | 118개 (이름만 공개된 행) |
| 불러오지 못한 페이지 | 없음 |

### 페이지 구조와 수집 방법

- 34개 설정 페이지는 별도 주소가 아니라 한 페이지 안의 앵커(`#page-…`) 섹션이다. 하위 링크도 모두 이 앵커다.
- 혹시 몰라 `/help/settings/general/` 같은 별도 주소 6개(general, appearance, tabs, integrations, battery, license)를 시험했는데 모두 404였다. 그래서 따라갈 하위 페이지가 따로 없고, 실패한 페이지도 없다.
- 설정 행은 서버가 보낸 HTML 안에 다 들어 있었다(JavaScript 렌더링 불필요). 행마다 설정 이름(dt)과 설명(dd), 일부 행은 표시 조건 메모가 있다.

### 보강 자료와 근거 표기

레퍼런스는 기본값, 선택지, 요구 사항을 거의 적지 않는다. 그래서 같은 도움말 센터의 개별 글 85개와 변경 이력에서 확인된 것만 보탰다.

- `[H:slug]` = 도움말 글 `https://notchy.dev/help/slug/`
- `[C:vX.Y.Z]` = 변경 이력 `https://notchy.dev/changelog/`의 해당 버전 항목
- 근거 표기가 없는 내용은 설정 레퍼런스의 설명 문구에서 온 것이다.
- 도움말 글 상당수는 2026-10-10~11에 쓰였다(앱 1.0.207 무렵). 2.0.3 라벨과 이름이나 위치가 다른 경우가 있어 섹션 4에 따로 모았다.

### 앱 전체에 걸린 조건

- 시스템: macOS 13 Ventura 이상, Apple 실리콘과 인텔 맥 모두 지원한다. 노치 있는 MacBook은 노치를 감싸는 아일랜드, 노치 없는 맥과 외장 화면은 떠 있는 알약 형태다[H:system-requirements].
- 요금: 2.0.0부터 유료다. 7일 무료 체험 동안 모든 기능이 동작하고, 이후 1회 구매 라이선스(맥 1대당 1개)가 필요하다[C:v2.0.0][H:lost-license-key]. 기능별 Pro 등급이 없으므로 행마다 'Pro only' 같은 표기는 없다.
- 기본값 정책: 새로 설치하면 선택 기능은 모두 꺼진 채 시작하고 첫 실행 투어가 하나씩 제안한다. 업데이트로 생긴 새 기능도 꺼진 채 들어온다[H:features-off-after-install]. 그래서 기본값이 적히지 않은 토글은 대부분 꺼짐일 가능성이 높지만, 표에는 근거가 있는 값만 적었다.
- 필수 권한은 손쉬운 사용 하나뿐이고 나머지는 기능을 켤 때 요청한다[H:permissions-notchy-needs].

### 표 읽는 법

- ID: `S<페이지 번호>-<행 번호>`. 페이지와 행 순서는 사이트 순서 그대로다.
- 설정 이름: 사이트 표기 그대로다.
- 동작: "(사이트 설명 없음)"은 이름만 있고 설명이 없는 행이다. "이름 기준"이 붙으면 이름만으로 뜻이 분명해서 풀어 쓴 것이고, 뜻이 불분명하면 "자료 없음"으로 적었다.
- 기본값: "-"는 어디에도 적혀 있지 않거나 버튼·표시 행처럼 기본값 개념이 없는 경우다. "자료 없음"은 값을 고르는 설정인데 기본값 근거를 못 찾은 경우다.
- 선택지·범위: "켬/끔"은 이름과 설명으로 보아 토글로 판단한 것이다. 사이트는 컨트롤 종류를 밝히지 않으므로 추정이다.
- 요구 사항·제약: "버튼"은 상태를 저장하지 않는 실행 행, "상태 행"은 조건에 따라 뜨는 안내 문구다. "표시 조건"은 사이트가 '켜야 나타난다'고 밝힌 하위 행이다.
- 각 페이지 제목 아래의 "구역"은 사이트의 소제목과 해당 행 번호다. "(소제목 없음)"은 소제목 없이 묶인 행이다.

### 페이지 목록

| 번호 | 페이지 | 한국어 | 행 수 | 주소 |
| --- | --- | --- | ---: | --- |
| P01 | All Tools | 전체 도구 | 4 | https://notchy.dev/help/settings/#page-features |
| P02 | Activity | 활동 | 5 | https://notchy.dev/help/settings/#page-activity |
| P03 | Home | 홈 | 21 | https://notchy.dev/help/settings/#page-home |
| P04 | General | 일반 | 15 | https://notchy.dev/help/settings/#page-general |
| P05 | Appearance | 모양 | 42 | https://notchy.dev/help/settings/#page-appearance |
| P06 | Behavior | 동작 방식 | 22 | https://notchy.dev/help/settings/#page-behavior |
| P07 | Popups | 팝업 | 17 | https://notchy.dev/help/settings/#page-notifications |
| P08 | Calls & Messages | 통화·메시지 | 8 | https://notchy.dev/help/settings/#page-calls |
| P09 | Files & Utilities | 파일·유틸리티 | 10 | https://notchy.dev/help/settings/#page-capture |
| P10 | Lock Screen | 잠금 화면 | 18 | https://notchy.dev/help/settings/#page-lockScreen |
| P11 | Permissions | 권한 | 16 | https://notchy.dev/help/settings/#page-permissions |
| P12 | Tabs | 탭 | 63 | https://notchy.dev/help/settings/#page-integrations |
| P13 | Battery & Fans | 배터리·팬 | 32 | https://notchy.dev/help/settings/#page-battery |
| P14 | Connectivity | 연결 | 9 | https://notchy.dev/help/settings/#page-connectivity |
| P15 | Displays | 디스플레이 | 5 | https://notchy.dev/help/settings/#page-displays |
| P16 | Knock | 노크 | 6 | https://notchy.dev/help/settings/#page-knock |
| P17 | Now Playing | 지금 재생 중 | 24 | https://notchy.dev/help/settings/#page-nowPlaying |
| P18 | Calendar | 캘린더 | 20 | https://notchy.dev/help/settings/#page-calendar |
| P19 | Timer | 타이머 | 26 | https://notchy.dev/help/settings/#page-timer |
| P20 | Clipboard | 클립보드 | 17 | https://notchy.dev/help/settings/#page-clipboard |
| P21 | Caffeine | 카페인(잠자기 방지) | 6 | https://notchy.dev/help/settings/#page-caffeine |
| P22 | Cuely | 큐리(텔레프롬프터) | 11 | https://notchy.dev/help/settings/#page-cuely |
| P23 | AI Usage | AI 사용량 | 13 | https://notchy.dev/help/settings/#page-aiUsage |
| P24 | Terminal | 터미널 | 4 | https://notchy.dev/help/settings/#page-terminal |
| P25 | Stocks | 주식 | 9 | https://notchy.dev/help/settings/#page-stocks |
| P26 | Quick Search | 빠른 검색 | 3 | https://notchy.dev/help/settings/#page-quickSearch |
| P27 | Windows & Spaces | 창·스페이스 | 8 | https://notchy.dev/help/settings/#page-spaces |
| P28 | Desktop Pet | 데스크톱 펫 | 8 | https://notchy.dev/help/settings/#page-pet |
| P29 | Pointer | 포인터 | 7 | https://notchy.dev/help/settings/#page-pointer |
| P30 | About | 정보 | 21 | https://notchy.dev/help/settings/#page-about |
| P31 | Screenshots | 스크린샷 | 14 | https://notchy.dev/help/settings/#page-screenshots |
| P32 | Typing Sounds | 타이핑 소리 | 8 | https://notchy.dev/help/settings/#page-typingSounds |
| P33 | Face Unlock | 얼굴 잠금 해제 | 10 | https://notchy.dev/help/settings/#page-faceUnlock |
| P34 | License | 라이선스 | 11 | https://notchy.dev/help/settings/#page-license |

## 2. 페이지별 설정

### P01. All Tools (전체 도구)

- 주소: https://notchy.dev/help/settings/#page-features
- 행 수: 4
- 구역: Quick Actions 1–3 · Dictation 4

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S01-01 | Header Buttons | 탭 옆 헤더와 홈의 Quick Actions 카드에 놓을 버튼을 고른다. | - | 버튼 종류는 Tabs 페이지 Header Buttons 구역(S12-05~S12-27) 참고 | 헤더 버튼은 최대 6개, 나머지는 More 메뉴로 간다[C:v1.0.225] |
| S01-02 | Window Shortcuts | (사이트 설명 없음) 자료 없음. | - | - | 관련 가능성: 도움말의 'Snap with the Keyboard'(⌃⌥⌘ ←/↩/→)[H:keyboard-shortcuts] |
| S01-03 | Shortcuts & Timer Mode | 포모도로 시작 단축키를 지정하거나 타이머의 Standard 모드를 숨긴다. | 단축키 없음[H:keyboard-shortcuts] | - | Timer 페이지의 S19-23, S19-24와 같은 내용을 한곳에 모은 행이다 |
| S01-04 | Dictation Shortcut | 단축키를 한 번 누르면 받아쓰기를 시작하고 다시 누르면 끝내 앞의 앱에 입력한다. 음성 인식은 맥 안에서만 처리한다. | 꺼짐(옵트인)[H:features-off-after-install], 단축키 없음[H:keyboard-shortcuts] | - | 마이크·음성 인식·손쉬운 사용 권한, 1회 최대 2분[H:dictation-setup] |

### P02. Activity (활동)

- 주소: https://notchy.dev/help/settings/#page-activity
- 행 수: 5
- 구역: Tracking 1–3 · Visibility 4–5

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S02-01 | Activity Tracking | 이 맥에서 클릭 수, 키 입력 수, 마우스 이동 거리를 세어 Activity 탭에 보여 준다. | - | - | - |
| S02-02 | Screen Time | 맥 앞에 있는 동안 앱별 사용 시간을 기록한다. | - | - | - |
| S02-03 | Clear Screen Time History | 이 맥에 기록된 앱별 사용 시간을 모두 지우는 버튼이다. | - | - | 되돌릴 수 없는 삭제 |
| S02-04 | Show Rings in the Notch | 접힌 노치 옆에 세 겹 링 모양의 활동 요약을 띄운다. | - | - | - |
| S02-05 | Show Floating Orb | 모든 창 위에 떠 있는 독립 위젯(오브)으로 활동을 보여 준다. | - | - | - |

### P03. Home (홈)

- 주소: https://notchy.dev/help/settings/#page-home
- 행 수: 21
- 구역: Desktop Widgets 1–6 · Arrange 7 · Grid 8 · Card Size 9–10 · Reset 11 · Home Controls 12 · (소제목 없음) 13–14 · World Clock 15 · Color Tools 16–17 · Weather 18–20 · Saved Links 21

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S03-01 | Floating Player | 지금 재생 중인 곡을 창 위에 떠 있는 작은 플레이어로 띄운다. 끌어서 아무 데나 옮길 수 있다. | - | 크기 4종: ⌘1 Mini Player, ⌘2 Player, ⌘3 Player with Lyrics, ⌘4 Player with Artwork[H:floating-player] | 처음엔 화면 오른쪽 아래에 나타난다[H:floating-player]. v2.0.3 신규[C:v2.0.3] |
| S03-02 | Lyrics in Now Playing | 싱크 가사가 있는 곡이면 Now Playing 위젯에 현재 가사 줄을 보여 준다. | - | - | 싱크 가사가 있는 곡만 |
| S03-03 | Add Photo Widget | 사진 한 장 또는 사진 폴더를 보여 주는 위젯을 하나 더 만든다. | - | - | - |
| S03-04 | Glass Widgets | 데스크톱 위젯을 반투명 유리 질감으로 그린다. 끄면 불투명해지고 날씨 위젯은 하늘 배경을 보여 준다. | - | 켬/끔 | - |
| S03-05 | Widget Positions | 위젯 배치 방법을 알려 주는 안내 행이다. 바탕화면에서 끌어 옮기고 오른쪽 클릭으로 크기 변경·삭제를 한다. | - | - | - |
| S03-06 | Desktop Widgets | 바탕화면(모든 창 아래)에 위젯을 놓는다. | - | Clock, World Clock, Now Playing, Weather, Sunrise & Sunset, Calendar, Batteries, System, Photo | World Clock·Calendar·Batteries는 크기 3종[C:v2.0.0] |
| S03-07 | Arrange in the Notch | 노치 안 홈 카드를 길게 눌러 끌어 순서를 바꾸고, 격자 가장자리를 끌어 카드 크기를 바꾼다. | - | - | 켜면 S03-12, S03-14, S03-15 행이 나타난다 |
| S03-08 | Columns | 홈 카드 격자의 열 수를 정한다. Auto는 카드 개수에 맞춰 자동으로 정한다. | 자료 없음 | Auto 외 값은 자료 없음 | - |
| S03-09 | Minimum Card Width | 홈 카드의 최소 너비를 정한다. 넓히면 홈과 패널 자체가 넓어질 수 있다. | - | 자료 없음 | - |
| S03-10 | Minimum Card Height | 홈 카드의 최소 높이를 정한다. 카드는 내용과 남은 공간에 따라 더 커질 수 있다. | - | 자료 없음 | - |
| S03-11 | Reset Home | 홈 카드 구성을 처음 상태로 되돌리는 버튼이다. | 기본 구성: Now Playing, Weather, Camera, Up Next | - | - |
| S03-12 | Home controls run through Shortcuts | 홈 제어는 사용자가 만든 단축어(장면·액세서리당 하나)를 실행하는 방식이라고 알리는 안내 행이다. | - | - | 표시 조건: ‘Arrange in the Notch’ 켬. macOS가 HomeKit 직접 접근을 막기 때문. 단축어 앱 필요 |
| S03-13 | Shortcuts isn’t available | 단축어 앱이 없어 홈 제어를 실행할 수 없을 때 나오는 상태 행이다. | - | - | 단축어 앱 필요 |
| S03-14 | Find a Shortcut | (사이트 설명 없음, 이름 기준) 홈 제어에 쓸 단축어를 찾아 고른다. | - | - | 표시 조건: ‘Arrange in the Notch’ 켬 |
| S03-15 | Add a City | 세계 시계 카드에 도시를 추가한다. | - | 카드에는 앞의 4개만 표시 | 표시 조건: ‘Arrange in the Notch’ 켬 |
| S03-16 | Copy Format | (사이트 설명 없음, 이름 기준) 색상 도구에서 색을 복사할 때 쓸 형식을 고른다. | - | 형식 목록 자료 없음 | - |
| S03-17 | Color Tools | 최근 고른 색을 보관하고 여러 형식으로 복사한다. | - | 최근 12개 | - |
| S03-18 | City (optional) | 날씨에 쓸 도시를 직접 입력한다. 비우면 현재 위치를 쓴다. | 빈 값(현재 위치) | - | 비워 두면 위치 권한 필요. 날씨 출처는 Open-Meteo(계정·키 불필요)[H:weather-without-location] |
| S03-19 | Sky Background | 홈 날씨 카드 배경을 현재 하늘 모습으로 채운다. | - | 켬/끔 | v2.0.3 신규[C:v2.0.3] |
| S03-20 | Location | 도시를 직접 지정해서 위치 권한이 선택 사항이라는 상태 행이다. | - | - | - |
| S03-21 | Saved Links | 저장해 둔 웹 페이지를 홈과 커맨드 팔레트에서 연다. | - | - | - |

### P04. General (일반)

- 주소: https://notchy.dev/help/settings/#page-general
- 행 수: 15
- 구역: Startup 1–2 · Language 3–4 · Automation 5–6 · Menu Bar 7–12 · Recovery 13–15

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S04-01 | Open at Login | (사이트 설명 없음) 로그인할 때 Notchy를 자동으로 실행한다. | 켬[H:launch-at-login] | 켬/끔 | macOS 로그인 항목 서비스를 쓰며 시스템 설정 로그인 항목에도 보인다[H:launch-at-login] |
| S04-02 | Hello Intro | 실행할 때 여러 언어로 인사하는 인트로를 재생한다. | - | 켬/끔 | - |
| S04-03 | Language | 앱 표시 언어를 바꾼다. | 맥 시스템 언어를 따름[H:change-language] | 지원 언어 목록 자료 없음 | 완전히 적용하려면 재시작 필요. 날짜·시간도 이 언어를 따르고 아랍어 등은 좌우가 반전된다[C:v1.0.225] |
| S04-04 | Time Format | 앱 전체의 시계, 일정, 미리 알림을 12시간제로 볼지 24시간제로 볼지 정한다. | 자료 없음 | 12시간 / 24시간[H:change-language] | Notchy 안에서만 적용된다[H:change-language] |
| S04-05 | Show in Notchy | 맥이 잠금 해제된 동안 단축어나 링크가 노치에 짧은 메시지를 띄우도록 허용한다. | - | 제목 최대 120자, 메시지 최대 500자, 표시 1~10초[H:local-api] | 명령 실행·파일 열기는 불가. 링크 형식 notchy://show?title=…&message=…[H:local-api] |
| S04-06 | Copy Example Link | Show in Notchy를 시험할 예시 URL을 복사하는 버튼이다. 단축어의 Show in Notchy 액션으로도 같은 일을 한다. | - | - | - |
| S04-07 | Caffeine | 메뉴 막대에 잠자기 방지(Caffeine) 토글을 둔다. | - | 켬/끔 | - |
| S04-08 | Hide Menu Bar Icons | 메뉴 막대에 화살표 구분자를 추가한다. ⌘-드래그로 그 왼쪽에 둔 아이콘은 화살표를 눌러 접어 숨긴다. | - | 켬/끔 | Notchy 자체 아이콘도 숨김 대상이다[C:v1.0.223] |
| S04-09 | Reveal on Hover | 화살표나 메뉴 막대 빈 곳에 포인터를 올리면 숨긴 아이콘을 보여 준다. | - | 켬/끔 | - |
| S04-10 | Automatically Re-hide | (사이트 설명 없음, 이름 기준) 펼친 메뉴 막대 아이콘을 다시 자동으로 숨긴다. | - | 대기 시간 값 자료 없음 | - |
| S04-11 | Always-Hidden Section | 두 번째 구분자를 추가한다. 그 왼쪽 아이콘은 표시 키를 누르거나 화살표를 ⌥-클릭할 때만 나타난다. | - | 켬/끔 | - |
| S04-12 | Reveal Key | 단독으로 누르고 있으면 숨긴 아이콘을 모두 보여 주는 키를 정한다. | 자료 없음 | 키 목록 자료 없음 | 손쉬운 사용 권한 필요 |
| S04-13 | Emergency Shortcut | (사이트 설명 없음) 앱이 멈춰도 동작하는 고정 강제 종료 단축키를 켜거나 끈다[H:keyboard-shortcuts]. | 자료 없음 | 단축키는 ⌃⌥⌘⎋로 고정 | - |
| S04-14 | Restart Notchy | 앱을 종료했다가 스스로 다시 연다. 막 허용한 권한을 반영하거나 앱이 변화를 못 알아챌 때 쓴다. | - | - | 버튼 |
| S04-15 | Force Quit Notchy | 작업이 끝나길 기다리지 않고 프로세스를 즉시 종료한다. | - | - | 버튼 |

### P05. Appearance (모양)

- 주소: https://notchy.dev/help/settings/#page-appearance
- 행 수: 42
- 구역: Pill 1–3 · Material 4–5 · Clock 6–10 · Expanded Panel 11–18 · Interface 19–22 · Motion 23–26 · Notifications-Only Mode 27 · Minimal Layout 28–29 · Hardware Notch 30 · Pill & Island Color 31 · Expanded Panel Color 32–42

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S05-01 | Shape | 모니터를 골라 그 화면의 알약(pill) 또는 노치 모양을 정한다. | 자료 없음 | Notch / Pill[H:choose-display] | 디스플레이가 여러 대면 화면마다 행이 생긴다[H:choose-display] |
| S05-02 | Closed Pill Size | 닫힌 알약의 크기 배율을 정한다. 펼친 패널 크기는 아래 행에서 따로 정한다. | 자료 없음 | 70%~140%[H:change-notch-size] | - |
| S05-03 | Pill Height Adjustment | 닫힌 알약과 라이브 액티비티 높이를 키워 실제 노치 높이에 맞춘다. | 자료 없음 | 최대 6pt[H:change-notch-size] | 한 번 빠졌다가 요청으로 복귀[C:v1.0.222] |
| S05-04 | Glass Surfaces | 패널과 카드 뒤의 바탕화면을 흐리게 비추고 가장자리에 하이라이트를 넣는다. | - | 켬/끔 | - |
| S05-05 | Panel Translucency | 패널이 얼마나 비칠지 정한다. 값이 클수록 바탕화면이 더 보인다. | - | 범위 자료 없음 | - |
| S05-06 | Clock on the Closed Pill | 노치 없는 화면에서 쉬고 있는 알약에 시간과 날짜를 띄운다. | - | 켬/끔 | 노치 없는 디스플레이 전용. Notifications-Only Mode에서는 숨는다[H:keep-clock-visible] |
| S05-07 | Not shown on this Mac’s notch | 이 맥의 실제 노치에는 알약 시계가 표시되지 않는다는 상태 행이다. | - | - | 노치 있는 MacBook |
| S05-08 | Clock Shows | 알약 시계에 무엇을 보일지 고른다. 12/24시간제는 General의 Time Format을 따른다. | 자료 없음 | 'Time and Date' 등, 초 표시 선택 가능[H:keep-clock-visible] | - |
| S05-09 | Date Format | 알약에 표시되는 날짜 형식을 고른다. | - | 형식 목록 자료 없음 | - |
| S05-10 | Show with Activities | 음악, 타이머 같은 액티비티가 떠 있어도 시계를 옆에 계속 둔다. | - | 켬/끔 | 2026-10-11 도움말은 이런 설정이 없다고 적는다[H:keep-clock-visible] → 섹션 4 |
| S05-11 | Your Display Uses Larger Text | 디스플레이 배율이 커서 Notchy도 크게 보인다고 알리고 디스플레이 설정에서 바꿀 수 있다고 안내하는 상태 행이다. | - | - | - |
| S05-12 | Panel Width | 펼친 패널의 선호 너비를 정한다. 패널은 화면 밖으로 나가지 않는다. | - | 범위 자료 없음 | 닫힌 음악 아일랜드 폭과는 무관[H:music-island-too-wide] |
| S05-13 | Panel Sizing | (사이트 설명 없음) 패널 크기 방식을 고른다. | 자료 없음 | Fixed / Dynamic[H:change-notch-size] | - |
| S05-14 | Maximum Height | 탭이 커질 수 있는 최대 높이를 정한다. 내용이 짧은 탭은 짧게 나온다. | - | 범위 자료 없음 | S05-15와 설명이 같다 → 섹션 4 |
| S05-15 | Panel Height | 탭이 커질 수 있는 높이를 정한다. 내용이 짧은 탭은 짧게 나온다. | - | 범위 자료 없음 | S05-14와 설명이 같다 → 섹션 4 |
| S05-16 | Use Compact Size | 패널을 가장 작은 크기로 되돌리는 버튼이다. | - | - | 버튼 |
| S05-17 | Use Default Size | (사이트 설명 없음, 이름 기준) 패널을 기본 크기로 되돌리는 버튼이다. | - | - | 버튼 |
| S05-18 | Tab Sizes | 펼친 패널의 모서리를 끌어 탭마다 다른 크기를 갖게 한다. | - | - | - |
| S05-19 | Monochrome Interface | 아이콘과 강조색을 회색으로 바꾼다. 앨범 아트와 앱 아이콘 색은 그대로 둔다. | - | 켬/끔 | - |
| S05-20 | Color-Coded Levels | 볼륨, 밝기, 배터리 막대를 낮으면 빨강, 중간이면 호박색, 높으면 초록으로 칠한다. | - | 켬/끔 | - |
| S05-21 | Panel Font | 알약과 펼친 패널에 쓸 글꼴을 고른다. 설정 창은 시스템 글꼴을 쓴다. | - | 글꼴 목록 자료 없음 | - |
| S05-22 | Panel Text Size | 패널 글자 크기 배율을 정한다. | - | 범위 자료 없음 | - |
| S05-23 | Animation Style | (사이트 설명 없음) 애니메이션 스타일을 고른다. | - | 선택지 자료 없음 | - |
| S05-24 | Animation Speed | 애니메이션 재생 속도를 정한다. 값이 높을수록 빨라진다. | - | 1×가 보통 속도, 상한 자료 없음 | 한 번 빠졌다가 복귀[C:v1.0.222] |
| S05-25 | Reduce Motion | Notchy 애니메이션을 줄인다. 시스템 손쉬운 사용에서 이미 켜져 있으면 그렇게 표시한다. | - | 켬/끔 | 켜면 햅틱이 꺼지고 비주얼라이저 막대가 멈춘다[H:reduce-motion-haptics] |
| S05-26 | Haptic Feedback | 스위치, 버튼, 드래그에서 트랙패드 햅틱을 낸다. | - | 켬/끔 | Reduce Motion이 켜져 있으면 꺼진다. 타이머 종료는 두 번 진동[H:double-haptic-click] |
| S05-27 | Notifications-Only Mode | 노치가 알림만 보여 주고 닫힌 채 있는다. 클릭·호버로 패널이 열리지 않고, 알림 클릭은 상세, 음악 재생 중 클릭은 컨트롤을 연다. | - | 켬/끔 | 설정은 노치 오른쪽 클릭으로 연다. 호버 열기, 전체 화면 호버 노출, 알약 시계가 꺼진다[H:open-the-island][H:hidden-in-full-screen][H:keep-clock-visible] |
| S05-28 | Use Minimal Layout | 고른 탭과 헤더 버튼만 보이고 알약과 패널을 작게 그린다. 다른 설정은 보존된다. | - | 켬/끔 | - |
| S05-29 | Minimal Layout Scale | Minimal Layout이 켜져 있을 때 알약과 패널을 얼마나 줄일지 정한다. | - | 범위 자료 없음 | Minimal Layout 켬일 때 적용 |
| S05-30 | Hide the Notch | 메뉴 막대 띠와 화면 둥근 모서리를 검게 칠해 카메라 노치가 안 보이게 한다. | - | 켬/끔 | 스페이스마다 배경화면을 유지한다[C:v1.0.225]. 관련 이력: 'Black Out Screen Corners'가 네 모서리를 둥글게 깎아 검은 메뉴 막대와 맞춘다[C:v1.0.174] |
| S05-31 | Same as Panel | 닫힌 알약과 라이브 액티비티에 펼친 패널과 같은 색을 쓴다. | - | 켬/끔 | - |
| S05-32 | Custom Fill | 패널 배경을 내가 고른 색이나 그라디언트로 바꾼다. | - | 켬/끔 | - |
| S05-33 | Fill Style | (사이트 설명 없음) 채우기 방식을 고른다. | 자료 없음 | 단색과 그라디언트(시작·끝 색 또는 중앙·가장자리 색)[H:panel-color]. 정확한 라벨 자료 없음 | 표시 조건: ‘Custom Fill’ 켬 |
| S05-34 | Color | (사이트 설명 없음, 이름 기준) 단색 채우기 색을 고른다. | - | - | 표시 조건: ‘Fill Style’ 켬 |
| S05-35 | Center Color | (사이트 설명 없음, 이름 기준) 중앙에서 퍼지는 그라디언트의 중앙 색을 고른다. | - | - | 표시 조건: ‘Fill Style’ 켬 |
| S05-36 | Start Color | (사이트 설명 없음, 이름 기준) 그라디언트 시작 색을 고른다. | - | - | 표시 조건: ‘Fill Style’ 켬 |
| S05-37 | Edge Color | (사이트 설명 없음, 이름 기준) 중앙에서 퍼지는 그라디언트의 가장자리 색을 고른다. | - | - | 표시 조건: ‘Fill Style’ 켬 |
| S05-38 | End Color | (사이트 설명 없음, 이름 기준) 그라디언트 끝 색을 고른다. | - | - | 표시 조건: ‘Fill Style’ 켬 |
| S05-39 | Angle | 그라디언트 방향을 정한다. | - | 0°는 위→아래, 90°는 왼쪽→오른쪽. 전체 범위 자료 없음 | 표시 조건: ‘Fill Style’ 켬 |
| S05-40 | Opacity | 채우기 불투명도를 정한다. 완전히 불투명하면 뒤의 유리 효과가 가려진다. | - | 범위 자료 없음 | 표시 조건: ‘Custom Fill’ 켬 |
| S05-41 | Fade the Bottom Edge | 패널 아래 가장자리 근처에서 색을 원래 표면으로 서서히 섞는다. | - | 켬/끔 | 표시 조건: ‘Fill Style’ 켬 |
| S05-42 | Use Notchy’s Own Fill | 카메라 컷아웃과 맞는 기본 검정 배경으로 되돌리는 버튼이다. | - | - | 표시 조건: ‘Custom Fill’ 켬. 버튼 |

### P06. Behavior (동작 방식)

- 주소: https://notchy.dev/help/settings/#page-behavior
- 행 수: 22
- 구역: Opening 1–3 · Closing 4–6 · Visibility 7–14 · Keyboard Shortcuts 15–17 · (소제목 없음) 18–22

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S06-01 | Expand on Hover | 닫힌 알약이나 화면 위쪽 가운데에 포인터를 올려 두면 패널을 연다. | 자료 없음 | - | Notifications-Only Mode에서는 꺼진다. 관련 설정 Hover Delay 등은 레퍼런스에 없다 → 섹션 5 |
| S06-02 | Default Tab | 한동안 닫혀 있다가 다시 열 때 처음 보일 탭을 정한다. | 자료 없음 | 켜진 탭 중 선택 | - |
| S06-03 | Open on Current Activity | 음악이나 타이머가 돌고 있으면 기본 탭 대신 Now Playing이나 Timer 탭으로 연다. | - | 켬/끔 | - |
| S06-04 | Auto Collapse | 포인터가 떠나거나 유휴 시간이 지나면 패널을 닫는다. | - | 켬/끔 | - |
| S06-05 | Collapse Delay | 포인터가 패널을 떠난 뒤 닫기까지 기다릴 시간을 정한다. | 자료 없음 | Instant 포함[C:v1.0.222], 나머지 값 자료 없음 | 한 번 빠졌다가 복귀[C:v1.0.222] |
| S06-06 | Idle Timeout | 포인터가 패널 위에 있어도 이 시간이 지나면 닫는다. | 자료 없음 | Never 포함(Never면 호버 중 계속 열림), 나머지 값 자료 없음 | - |
| S06-07 | Show On | Notchy를 띄울 연결 디스플레이를 고른다. | 자료 없음 | All / Built-in / Main / External[H:choose-display] | 맞는 화면이 없으면 주 디스플레이로 대체[H:choose-display]. S15-01과 겹친다 → 섹션 4 |
| S06-08 | Invisible Until Hover | 쉬는 알약을 완전히 숨기고 노치 영역에 호버할 때만 보이게 한다. 음악, 타이머, 통화, 알림은 평소대로 나온다. | - | 켬/끔 | - |
| S06-09 | Hide if Menus Overlap | 메뉴 막대 항목이 알약과 겹치면 알약을 숨긴다. | - | 켬/끔 | - |
| S06-10 | Hide in Full Screen | 선택한 종류의 앱이 전체 화면이면 알약과 패널을 숨긴다. | 켬(전체 화면에서 기본으로 숨음)[H:notchy-not-showing] | 켬/끔 | - |
| S06-11 | Full-Screen Apps | 전체 화면 숨김을 적용할 앱 범위를 고른다. | 자료 없음 | 모든 전체 화면 앱 / 음악·영상 재생 중인 앱만('Playing Media App')[H:hidden-in-full-screen] | - |
| S06-12 | Hide in Mission Control | 미션 컨트롤이나 앱 익스포제가 열려 있는 동안 알약을 흐리게 숨긴다. | - | 켬/끔 | 표시 조건: ‘Hide in Full Screen’ 켬. 손쉬운 사용 권한 필요 |
| S06-13 | Screen Sharing Privacy | 스크린샷, 녹화, 화면 공유에 알약이 찍히지 않게 한다. 일부 앱은 그래도 찍을 수 있다. | 자료 없음 | Visible / Hidden from Captures / Hidden Everywhere[H:hide-during-screen-sharing] | Hidden Everywhere를 풀려면 응용 프로그램에서 Notchy를 다시 열어 설정에 들어간다[H:hide-during-screen-sharing] |
| S06-14 | Hide While Mirroring | 디스플레이 미러링 중에는 모든 화면에서 알약을 숨긴다. | - | 켬/끔 | - |
| S06-15 | Launcher Wheel | 원형 메뉴로 앱을 열거나 동작을 실행한다. 단축키를 누른 채 방향을 가리키고 떼면 고른다. | 자료 없음 | - | v2.0.3에서 Action Ring 추가[C:v2.0.3] |
| S06-16 | Siri on the Notch | Siri가 화면에 떠 있는 동안 라이브 아일랜드를 띄우고, 단축키로 Siri를 부른다. | - | 켬/끔 | - |
| S06-17 | Tab Shortcuts | 어느 앱에서든 특정 탭을 바로 여는 단축키다. 다시 누르면 닫힌다. | - | - | Notifications-Only Mode에서도 동작 |
| S06-18 | Open Notchy Shortcut | (사이트 설명 없음, 이름 기준) 패널을 여는 단축키를 기록한다. | ⌃⌥N[H:keyboard-shortcuts] | - | - |
| S06-19 | Hide Notchy Shortcut | (사이트 설명 없음, 이름 기준) Notchy를 숨기고 다시 보이는 단축키를 기록한다. | ⌥Space[H:keyboard-shortcuts] | - | - |
| S06-20 | Command Palette Shortcut | (사이트 설명 없음, 이름 기준) 커맨드 팔레트 단축키를 기록한다. | ⌃⌥K, 패널 안에선 ⌘K[H:command-palette-find-files] | - | - |
| S06-21 | Launcher Wheel Shortcut | (사이트 설명 없음, 이름 기준) 런처 휠 단축키를 기록한다. | ⌃⌥L(Launcher Wheel 켬일 때)[H:keyboard-shortcuts] | - | - |
| S06-22 | Siri Shortcut | (사이트 설명 없음, 이름 기준) Siri를 부르는 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | - |

### P07. Popups (팝업)

- 주소: https://notchy.dev/help/settings/#page-notifications
- 행 수: 17
- 구역: Timing 1–2 · Privacy 3–4 · Focus Modes 5–8 · System Popups 9–13 · Volume & Brightness Popups 14–15 · Displays 16 · Sounds 17

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S07-01 | Notification Duration | (사이트 설명 없음, 이름 기준) 알림 팝업이 노치에 머무는 시간을 정한다. | - | 값 자료 없음 | - |
| S07-02 | Feature Tips | 가끔 팁과 새 기능 소개를 띄운다. 하루 최대 1번이고 집중 모드나 통화 중엔 띄우지 않는다. | 꺼짐[C:v1.0.189] | 켬/끔 | - |
| S07-03 | Camera Guard | 어떤 앱이든 카메라를 켜는 순간 알린다. | - | 켬/끔 | - |
| S07-04 | When the Camera Goes Live | (사이트 설명 없음) 카메라가 켜졌을 때 어떻게 반응할지 고른다. | - | 선택지 자료 없음 | - |
| S07-05 | Focus Modes Unavailable | 집중 모드 목록이 전체 디스크 접근 권한 뒤에 있어 볼 수 없다고 알리는 상태 행이다. 허용 후 설정을 다시 열라고 안내한다. | - | - | 전체 디스크 접근 |
| S07-06 | Showing Inferred Modes | 권한이 없어 추정한 집중 모드를 보여 주는 중이라는 상태 행이다(설명 문구는 S07-05와 같음). | - | - | 전체 디스크 접근. 추정 방식은 관찰된 변화와 단축어 이름[H:switch-focus-modes] |
| S07-07 | Refresh Shortcuts | 집중 모드 전환용 단축어 목록을 다시 읽는다. 없으면 'Set Focus' 액션 하나짜리 단축어를 모드 이름으로 만들라고 안내한다. | - | - | 단축어 앱 |
| S07-08 | Manage Focus Modes | 시스템 설정의 집중 모드 화면을 연다. Notchy는 거기서 모드를 읽는다. | - | - | 버튼 |
| S07-09 | Volume Popup | 볼륨이 바뀌면 Notchy 팝업으로 보여 준다. | - | 켬/끔 | - |
| S07-10 | Brightness Popup | 밝기가 바뀌면 Notchy 팝업으로 보여 준다. | - | 켬/끔 | - |
| S07-11 | Quiet Popups During Focus | 집중 모드 중에는 Notchy의 볼륨·밝기 팝업을 숨긴다. | - | 켬/끔 | - |
| S07-12 | Caps Lock Popup | Caps Lock이 바뀔 때 짧은 팝업을 띄운다. | - | 켬/끔 | - |
| S07-13 | Focus Popup | 집중 모드가 바뀔 때 짧은 팝업을 띄운다. | - | 켬/끔 | - |
| S07-14 | Replace System Volume & Brightness Overlay | macOS 기본 볼륨·밝기 오버레이를 숨기고 Notchy 팝업만 보이게 한다. Notchy를 끄면 원래대로 돌아온다. | - | 켬/끔 | 필요한 권한을 켜기 전에 안내한다[C:v1.0.148]. 권한 이름 자료 없음(Permissions의 Input Monitoring 설명에 'HUD용 미디어 키'가 있다) |
| S07-15 | Popups Beside the Notch | 볼륨, 밝기, 키보드 백라이트 팝업을 카메라 노치 옆에 띄워 아래 화면을 가리지 않는다. | - | 켬/끔 | 노치 있는 맥 |
| S07-16 | Only on the Display With the Pointer | 디스플레이가 여럿이면 모든 노치 대신 지금 쓰는 화면에만 팝업을 띄운다. | - | 켬/끔 | 디스플레이 2대 이상 |
| S07-17 | Sounds | (사이트 설명 없음) 팝업과 알림 소리를 정한다. | - | 자료 없음 | AI Usage 페이지가 AI 알림 소리를 이 페이지에서 고른다고 적는다(S23-10) |

### P08. Calls & Messages (통화·메시지)

- 주소: https://notchy.dev/help/settings/#page-calls
- 행 수: 8
- 구역: (소제목 없음) 1–3 · App Notifications 4–8

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S08-01 | Call Controls | FaceTime, WhatsApp, Teams 등 통화를 노치에 띄워 받기, 음소거, 끊기를 한다. | - | 켬/끔 | FaceTime 발신자 사진은 연락처 권한(S11-07) |
| S08-02 | Meeting Calls | Teams, Zoom, Slack, Discord 통화 중에 통화 시간 아일랜드를 띄우고, 통화 소리를 Now Playing에서 뺀다. | - | 켬/끔 | - |
| S08-03 | iMessage | 새 iMessage를 아일랜드로 띄우고 바로 답장하게 한다. Teams·Slack 등은 Mirror App Notifications를 따른다. | - | 켬/끔 | Messages 자동화 권한[H:permissions-notchy-needs] |
| S08-04 | Mirror App Notifications | Outlook, Teams, Slack 등 모든 앱의 배너를 아일랜드로 보여 주고 Notifications 탭에 모은다. | - | 켬/끔 | Permissions 페이지는 알림 센터 미러링에 전체 디스크 접근이 필요하다고 적는다(S11-08) |
| S08-05 | macOS Banner Position | macOS 알림 배너를 노치 모서리에서 다른 곳(화면 어디든)으로 옮긴다. | - | 위치 목록 자료 없음 | 손쉬운 사용 권한 필요 |
| S08-06 | Notification Size | 미러링 알림의 크기 방식을 고른다. Full Size는 전체 메시지를, Expand on Hover는 작게 띄웠다가 호버하면 펼친다. | 자료 없음 | Full Size / Expand on Hover | - |
| S08-07 | Unread Count Beside Notch | Notifications 탭을 마지막으로 연 뒤 온 알림 수를 노치 옆 빨간 배지로 보여 준다. 누르면 목록을 연다. | - | 켬/끔 | v2.0.2 신규[C:v2.0.2] |
| S08-08 | Show During Focus | 집중 모드 중에도 앱 알림 미러링을 계속한다. macOS 배너를 끄고 노치만 알림 창구로 쓸 때를 위한 것이다. | - | 켬/끔 | - |

### P09. Files & Utilities (파일·유틸리티)

- 주소: https://notchy.dev/help/settings/#page-capture
- 행 수: 10
- 구역: Presenting 1–2 · Command Timer 3 · Downloads & Drives 4–6 · Dictation 7–10

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S09-01 | Keystroke HUD | 누르는 단축키를 키캡 모양으로 노치에 보여 준다. 시연이나 화면 녹화용이다. | - | 켬/끔 | - |
| S09-02 | Shortcuts Only | ⌘, ⌃, ⌥가 들어간 조합만 보여 주고 일반 타이핑은 숨긴다. | - | 켬/끔 | - |
| S09-03 | Long Command Islands | 10초 넘게 걸리는 터미널 명령을 실시간 타이머 아일랜드로 보여 주고, 끝나면 ✓ 또는 ✗를 띄운다. | - | 기준 10초 | zsh 전용. ~/.zshrc에 훅을 추가하고 끄면 지운다 |
| S09-04 | Download Finished | 다운로드 폴더에 파일이 들어오면 아일랜드를 띄운다. | - | 켬/끔 | - |
| S09-05 | Drive Mounted | 디스크가 연결되면 꺼내기 버튼이 있는 아일랜드를 띄운다. | - | 켬/끔 | - |
| S09-06 | App Install Offers | 디스크 이미지(.dmg)가 마운트되면 앱 설치를 제안한다. 다른 설치 도구를 쓰면 끈다. | - | 켬/끔 | - |
| S09-07 | Dictate Text Shortcut | (사이트 설명 없음, 이름 기준) 받아쓰기 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | S01-04와 같은 기능으로 보인다 |
| S09-08 | Press Fn to Dictate | Fn을 짧게 눌러 받아쓰기를 시작하거나 끝낸다. Fn 조합 키는 그대로 동작한다. | - | 켬/끔 | - |
| S09-09 | Fn in macOS | 키보드 설정의 'Fn 키를 누르면'을 '아무것도 안 함'으로 바꾸라고 안내하는 행이다. Apple 받아쓰기나 이모지 창이 같이 뜨는 걸 막는다. | - | - | - |
| S09-10 | Accessibility Access | Fn 사용과 다른 앱에 붙여넣기에 손쉬운 사용 권한이 필요하다는 상태 행이다. | - | - | 손쉬운 사용 |

### P10. Lock Screen (잠금 화면)

- 주소: https://notchy.dev/help/settings/#page-lockScreen
- 행 수: 18
- 구역: Pill 1–6 · Widget 7–12 · Card Style 13–15 · Cards 16–17 · Troubleshooting 18

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S10-01 | Show on Lock Screen | 잠금이나 화면 보호기 중에도 알약을 보이게 한다. | - | 켬/끔 | - |
| S10-02 | Lock & Unlock Island | 맥이 잠긴 동안 자물쇠 알약을 보여 준다. | - | 켬/끔 | - |
| S10-03 | Show Unlock Animation | 잠금을 풀 때 알약에 열린 자물쇠를 잠깐 보여 준다. | - | 켬/끔 | v1.0.223 신규[C:v1.0.223] |
| S10-04 | Lock Sounds | 맥을 잠그고 풀 때 소리를 낸다. | - | 켬/끔 | - |
| S10-05 | Lock Sound | (사이트 설명 없음, 이름 기준) 잠글 때 낼 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S10-06 | Unlock Sound | (사이트 설명 없음, 이름 기준) 잠금을 풀 때 낼 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S10-07 | Lock Screen Widget | 맥이 잠긴 동안 재생 중인 곡, 다음 일정, 날씨 등을 위젯으로 보여 준다. | 꺼짐(옵트인)[H:features-off-after-install] | 카드: Now Playing, Timer, Up Next, Reminders, Focus, Weather, Battery, Device Batteries[H:lock-screen-widgets] | - |
| S10-08 | Layout | 위젯 배치 방식을 고른다. Cards는 위젯마다 카드를, Single Strip은 아이콘과 값만 한 줄로 늘어놓는다. | 자료 없음 | Cards / Single Strip | - |
| S10-09 | Horizontal Position | 카드를 한쪽으로 밀어 로그인 입력란을 피한다. | - | 범위 자료 없음 | - |
| S10-10 | Vertical Position | 시계와 로그인 컨트롤 사이 공간 안에서 위젯을 위아래로 옮긴다. | - | 범위 자료 없음 | - |
| S10-11 | Album Art Background | 음악 재생 중 앨범 커버로 위젯 뒤 화면을 채운다. | - | 켬/끔 | - |
| S10-12 | Preview Layout | 맥을 잠그지 않고 위젯을 전체 화면으로 그려 위치를 잡게 한다. Close로 닫는다. | - | - | 버튼 |
| S10-13 | Card Density | 카드 밀도를 고른다. Compact는 모든 카드를 한 줄로(날씨는 상태와 온도, 배터리는 %) 그려 더 많이 들어가게 한다. | 자료 없음 | Compact 외 값 자료 없음 | - |
| S10-14 | Card Background | 카드 배경을 고른다. | 자료 없음 | 유리 / 평평한 어두운 채움 / 없음(배경화면 위에 글자만). 정확한 라벨 자료 없음 | - |
| S10-15 | Same Glass as Panel | 위젯에 Appearance › Material에서 고른 유리 모양을 입힌다. | - | 켬/끔 | - |
| S10-16 | Show Event and Reminder Titles | 잠금 화면 카드에 일정과 미리 알림 제목을 보여 준다. 끄면 시간만 나온다. | 꺼짐(제목 숨김)[C:v1.0.224] | 켬/끔 | 켜면 잠긴 맥 앞의 누구나 제목을 읽을 수 있다 |
| S10-17 | Reset Card Order | 카드 순서를 출고 상태로 되돌리는 버튼이다. | - | - | 버튼 |
| S10-18 | Copy Lock Screen Report | 잠금 화면 진단 보고서를 복사한다. 메일이나 GitHub 이슈에 붙여 넣는 용도다. | - | - | 버튼 |

### P11. Permissions (권한)

- 주소: https://notchy.dev/help/settings/#page-permissions
- 행 수: 16
- 구역: Required 1 · Features 2–7 · Advanced Features 8–11 · Voice & Music 12–13 · Diagnostics 14 · Setup 15–16

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S11-01 | Accessibility | 노치에 포인터를 대거나 클릭할 때 반응, 통화·메시지 배너, 창 스냅에 쓰는 권한 상태 행이다. | - | - | 유일한 필수 권한. 얼굴 잠금 해제 비밀번호 입력에도 쓴다[H:permissions-notchy-needs] |
| S11-02 | Camera | 카메라 미러 탭과 얼굴 잠금 해제에 쓰는 권한 상태 행이다. | - | - | 기능을 켤 때 요청 |
| S11-03 | Bluetooth | 케이스를 열면 AirPods와 배터리를 자동 감지하는 데 쓰는 권한 상태 행이다. | - | - | 기능을 켤 때 요청 |
| S11-04 | Calendar | 일정과 다음 이벤트 표시, Calendar Capture를 켜면 개인 일정 저장에 쓰는 권한 상태 행이다. | - | - | 'Calendar Capture'는 레퍼런스 다른 곳에 없다 → 섹션 4 |
| S11-05 | Reminders | 패널에서 미리 알림을 추가하고 완료하는 데 쓰는 권한 상태 행이다. | - | - | 기능을 켤 때 요청 |
| S11-06 | Location | 홈 탭과 알약의 지역 날씨에 쓰는 권한 상태 행이다. | - | - | 도시를 직접 입력하면 불필요(S03-18) |
| S11-07 | Contacts | FaceTime 수신 때 발신자 사진에 쓰는 권한 상태 행이다. | - | - | 기능을 켤 때 요청 |
| S11-08 | Full Disk Access | 알림 센터 미러링과 집중 모드 목록 읽기·전환에 쓰는 권한 상태 행이다. | - | - | 옵트인 고급 권한 |
| S11-09 | Input Monitoring | HUD용 미디어 키, 타이핑 소리, 스페이스바 얼굴 잠금 해제에 쓰는 권한 상태 행이다. | - | - | 트랙패드 노크에도 필요[H:knock-not-working] |
| S11-10 | Screen Recording | 스크린샷, 화면·영역 녹화, 창 제목 읽기에 쓰는 권한 상태 행이다. | - | - | macOS가 한 번만 묻고, 나중에 시스템 설정에서 허용하면 Notchy가 재시작된다[H:permission-granted-not-working] |
| S11-11 | Files & Folders | Screenshot to Shelf를 위해 스크린샷 폴더를 읽는 권한 상태 행이다. | - | - | - |
| S11-12 | Microphone | 받아쓰기, 노래 식별, 텔레프롬프터 읽기 따라가기에 쓰는 권한 상태 행이다. | - | - | 오디오는 저장하지 않는다[H:permissions-notchy-needs] |
| S11-13 | Speech Recognition | 받아쓰기와 텔레프롬프터용 기기 내 음성 인식 권한 상태 행이다. | - | - | - |
| S11-14 | Copy Permission Diagnostics | 시스템 정보와 권한 상태를 버그 보고용으로 복사한다. | - | - | 버튼 |
| S11-15 | AI Usage Setup | AI 사용량 로컬 추적기가 무엇을 읽는지 단계별로 안내한다. | - | - | 버튼 |
| S11-16 | Permission Guide | 권한 설정을 한 단계씩 안내한다. | - | - | 버튼 |

### P12. Tabs (탭)

- 주소: https://notchy.dev/help/settings/#page-integrations
- 행 수: 63
- 구역: Favorite Tabs 1–2 · Header Layout 3–4 · Header Buttons 5–27 · (소제목 없음) 28 · Productivity 29–40 · Shortcuts Tab 41 · Task Sources 42–43 · Todoist 44 · Reminders List 45 · Home Controls Tab 46–47 · Core 48–49 · Media 50–52 · Workspaces 53–57 · System 58–63

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S12-01 | Favorite Tabs | 즐겨찾는 탭만 헤더에 두고, 켜진 도구는 모두 All Tools에서 쓸 수 있게 한다. | - | 탭 목록에서 선택 | - |
| S12-02 | Undo Favorite Change | (사이트 설명 없음, 이름 기준) 직전 즐겨찾기 변경을 되돌리는 버튼이다. | - | - | 버튼 |
| S12-03 | Tab Labels | (사이트 설명 없음) 탭 이름 표시 방식을 정한다. 탭마다 이름을 보일지 고를 수 있다[C:v1.0.223]. | 자료 없음 | 자료 없음 | - |
| S12-04 | Tabs Beside the Notch | 노치 있는 맥에서 탭은 카메라 왼쪽, 헤더 버튼은 오른쪽에 두고 아래 공간을 탭 내용에 준다. | 꺼짐[H:tabs-beside-notch] | 켬/끔 | 하드웨어 노치와 Notch 모양 필요. 넘치는 탭은 More 메뉴로[H:tabs-beside-notch] |
| S12-05 | Hover Labels | (사이트 설명 없음) 헤더 버튼에 호버할 때 이름표를 보일지 정한다[C:v1.0.124]. | 자료 없음 | 자료 없음 | - |
| S12-06 | Ports Button | 헤더에서 대기 중(listening)인 TCP 포트를 보고, 그 프로세스를 한 번에 멈춘다. | - | 켬/끔 | - |
| S12-07 | Battery Button | 헤더에서 배터리 상세를 연다. | - | 켬/끔 | - |
| S12-08 | Pomodoro Button | 한 번 누르면 집중 세션을 시작하고, 다시 누르면 진행 중인 세션을 연다. | - | 켬/끔 | - |
| S12-09 | Identify Song | 배터리 옆에 한 번 눌러 노래를 찾는 버튼을 둔다. | - | 켬/끔 | 마이크 권한(S11-12) |
| S12-10 | Screenshot Button | 헤더나 홈 빠른 동작에서 캡처할 영역을 고른다. | - | 켬/끔 | 화면 기록 권한(S11-10) |
| S12-11 | Scrolling Screenshot Button | 긴 페이지를 끝까지 자동 스크롤하며 한 장으로 캡처한다. | - | 켬/끔 | 화면 기록 권한(S11-10) |
| S12-12 | Record Button | 헤더에서 화면 녹화를 시작하고 멈춘다. | - | 켬/끔 | 화면 기록 권한(S11-10) |
| S12-13 | Scan QR Code Button | 화면의 QR 코드나 바코드를 읽어 복사하고, 링크면 열지 묻는다. | - | 켬/끔 | - |
| S12-14 | Color Picker Button | 헤더에서 화면 아무 곳의 색을 뽑는다. | - | 켬/끔 | - |
| S12-15 | Microphone Mute Button | 헤더에서 마이크를 음소거하거나 푼다. 음소거 중엔 불이 켜진다. | - | 켬/끔 | - |
| S12-16 | Dictation Button | 말하면 앞에 있는 앱에 글자로 입력한다. | - | 켬/끔 | 마이크·음성 인식·손쉬운 사용[H:dictation-setup] |
| S12-17 | Camera Button | 앱이 카메라를 쓰는 동안 초록색이 된다. 누르면 Camera Guard를 대기시킨다. | - | 켬/끔 | - |
| S12-18 | Volume Button | 누르면 음소거, 호버하면 시스템 볼륨 슬라이더가 나온다. | - | 켬/끔 | - |
| S12-19 | Command Palette Button | 헤더에서 동작, 앱, 설정을 검색한다. | - | 켬/끔 | - |
| S12-20 | Stopwatch Button | Caffeine 옆에 스톱워치를 보여 준다. | - | 켬/끔 | - |
| S12-21 | Timer Button | 사용자 지정 길이의 카운트다운을 시작, 일시정지, 재개한다. | - | 켬/끔 | - |
| S12-22 | Pin Button | 노치를 열린 채 고정한다. 안 쓸 땐 헤더 자리를 차지하지 않는다. | - | 켬/끔 | - |
| S12-23 | Lock Screen Button | 누르면 화면을 잠그고, 길게 누르면 디스플레이를 끈다. | - | 켬/끔 | - |
| S12-24 | Caffeine Button | 맥이 잠들지 않게 한다. 길게 누르면 타이머를 정한다. | - | 켬/끔 | - |
| S12-25 | Clean Keyboard Button | 닦는 동안 60초간 키보드를 끈다. 길게 누르면 화면 청소(검은 화면)도 한다. | - | 60초 | - |
| S12-26 | System Stats | 게이지에 호버하면 CPU, GPU, 온도, 메모리, 네트워크를 실시간으로 보여 준다. | - | 켬/끔 | - |
| S12-27 | Rank Processes By | 프로세스 정렬 기준을 고른다. Energy는 CPU 시간에 유휴 깨우기 횟수까지 반영한다. | 자료 없음 | Energy 외 값 자료 없음 | - |
| S12-28 | Hidden by Minimal Layout | 켜져 있지만 미니멀 탭 세트에 없는 탭이라고 표시하는 상태 행이다. | - | - | Minimal Layout 켬일 때 |
| S12-29 | Keep Shelf Files | 선반을 비울 때 선반 항목과 Notchy가 만든 사본만 지우고 원본 파일은 건드리지 않는다고 알리는 행이다. | 자료 없음 | 자료 없음 | 이름과 설명이 어긋난다. 도움말의 Remember Shelf Files·Keep Independent Shelf Copies와 관계 불명 → 섹션 4 |
| S12-30 | Shelf | 파일을 알약에 끌어다 놓아 잠시 보관하는 탭을 켠다. | - | 켬/끔 | - |
| S12-31 | Clipboard | 최근 복사 기록 탭을 켠다. 한 번 눌러 복원한다. | - | 켬/끔 | - |
| S12-32 | Calculator | 식을 입력하면 답을 내는 계산기 탭을 켠다. 퍼센트, 함수, 기록을 지원한다. | - | 켬/끔 | - |
| S12-33 | Emoji | 이모지를 검색해 입력하던 곳에 붙여 넣는 탭을 켠다. | - | 켬/끔 | - |
| S12-34 | To-Do | 이 맥에만 저장되는 간단한 체크리스트 탭을 켠다. | - | 켬/끔 | - |
| S12-35 | Reminders | Apple 미리 알림을 빠르게 추가하고 완료하는 탭을 켠다. | - | 켬/끔 | 미리 알림 권한(S11-05) |
| S12-36 | Calendar | 한 주 일정과 원탭 회의 참가를 보여 주는 탭을 켠다. | - | 켬/끔 | 캘린더 권한(S11-04) |
| S12-37 | Shortcuts | Apple 단축어를 한 번에 실행하는 탭을 켠다. | - | 켬/끔 | 단축어 앱 |
| S12-38 | Launcher | 앱을 고정해 한 번에 실행하는 탭을 켠다. | - | 켬/끔 | - |
| S12-39 | Quick Search | 검색어를 입력하고 엔터를 치면 브라우저에서 여는 탭을 켠다. | - | 켬/끔 | 검색 엔진 추가는 Quick Search 페이지(P26) |
| S12-40 | Translate | 외국어를 붙여 넣으면 내 언어로 번역하는 탭을 켠다. | - | 켬/끔 | 번역 엔진 자료 없음 |
| S12-41 | Find a Shortcut | Shortcuts 탭에 둘 단축어를 찾는다. | - | - | 표시 조건: ‘Shortcuts’ 켬 |
| S12-42 | Use Apple Reminders | 할 일 출처로 Apple 미리 알림을 쓴다. Todoist를 연결한 뒤에만 끌 수 있다. | 켬 | 켬/끔 | 표시 조건: ‘Reminders’ 켬 |
| S12-43 | Quick Add Destination | (사이트 설명 없음, 이름 기준) 빠른 추가로 만든 항목이 들어갈 곳을 고른다. | - | 자료 없음 | 표시 조건: ‘Use Apple Reminders’ 켬 |
| S12-44 | Todoist | Todoist 연결 상태를 보여 주고 작업을 동기화한다. | - | - | 표시 조건: ‘Reminders’ 켬. Todoist 계정 필요 |
| S12-45 | Show List | 보여 줄 미리 알림 목록을 고른다. 새 미리 알림도 이 목록에 들어간다. | - | 목록에서 선택 | 표시 조건: ‘Use Apple Reminders’ 켬 |
| S12-46 | Home items come from Shortcuts | 홈 항목은 장면·액세서리마다 만든 단축어에서 온다고 알리는 안내 행이다. | - | - | 표시 조건: ‘Home Controls’ 켬. macOS가 HomeKit 직접 접근을 막기 때문 |
| S12-47 | Show Every Shortcut | 홈 제어 목록에 모든 단축어를 보인다. 끄면 홈 제어나 장면처럼 보이는 이름만 보인다. | - | 켬/끔 | 표시 조건: ‘Home Controls’ 켬 |
| S12-48 | Home | 음악, 날씨, 일정을 한눈에 보는 홈 탭을 켠다. | - | 켬/끔 | - |
| S12-49 | Quick Settings | 빠른 설정 탭을 노치에 보인다. | - | 켬/끔 | 어떤 스위치를 보일지와 순서를 고를 수 있다[C:v1.0.226] |
| S12-50 | Now Playing | 컨트롤과 싱크 가사가 있는 전체 플레이어 탭을 켠다. | - | 켬/끔 | - |
| S12-51 | Sound Mixer | 소리 나는 앱마다 볼륨, 이퀄라이저, 출력 장치를 정하는 탭을 켠다. | 꺼짐(옵트인)[H:features-off-after-install] | 3밴드 EQ ±12dB[H:per-app-volume], 앱 볼륨 최대 150%[C:v2.0.3] | macOS 14.4 이상, 시스템 오디오 녹음 권한. 켜면 보라색 녹음 표시가 뜬다[H:purple-recording-indicator] |
| S12-52 | Timer | 카운트다운과 포모도로 탭을 켠다. | - | 켬/끔 | - |
| S12-53 | Cuely | 웹캠 아래 텔레프롬프터 탭을 켠다. | - | 켬/끔 | - |
| S12-54 | Ask AI | 내 API 키로 Claude와 대화하는 탭을 켠다. | 꺼짐(옵트인)[H:features-off-after-install] | 켬/끔 | Anthropic API 키 필요(Claude Pro/Max 구독엔 API 미포함). 키는 키체인, 대화는 메모리에만[H:ask-ai-api-key] |
| S12-55 | Notes | 생각을 적으면 Apple 메모에 바로 저장하는 탭을 켠다. | - | 켬/끔 | Notes 자동화 권한[H:permissions-notchy-needs] |
| S12-56 | Terminal | 노치 안에서 내 셸을 돌리는 전체 터미널 탭을 켠다. | - | 켬/끔 | - |
| S12-57 | Mirror | 카메라로 내 모습을 잠깐 비춰 보는 탭을 켠다. | - | 켬/끔 | 카메라 권한(S11-02) |
| S12-58 | Home Controls | 노치에서 홈 장면과 액세서리를 실행하는 탭을 켠다. | - | 켬/끔 | 단축어 기반(S12-46) |
| S12-59 | Focus | 방해 금지, 업무 같은 집중 모드를 바꾸는 탭을 켠다. | - | 켬/끔 | 모드당 단축어 필요, 전체 디스크 접근 권장[H:switch-focus-modes] |
| S12-60 | Activity | 실시간 책상 활동, 칼로리 소모, XP 레벨 탭을 켠다. | - | 켬/끔 | Activity 페이지(P02)와 연결 |
| S12-61 | AI Usage | Claude, Codex, Cursor와 원격 제공자 사용량 탭을 켠다. | - | 켬/끔 | AI Usage 페이지(P23)와 연결 |
| S12-62 | Stocks | 관심 종목과 종목별 당일 흐름 탭을 켠다. | - | 켬/끔 | 시세 출처 Yahoo Finance[H:what-notchy-sends] |
| S12-63 | Apps & Updates | 앱, App Store, Homebrew 업데이트를 한 목록에 모은 탭을 켠다. | - | 켬/끔 | Homebrew는 /opt/homebrew/bin/brew 또는 /usr/local/bin/brew, sudo가 필요한 cask는 실패[H:homebrew-update-fails] |

### P13. Battery & Fans (배터리·팬)

- 주소: https://notchy.dev/help/settings/#page-battery
- 행 수: 32
- 구역: (소제목 없음) 1–6 · Alerts 7–10 · Charging 11–14 · Appearance 15 · Sounds 16–21 · Menu Bar 22 · Power 23 · Charge Limit 24–30 · Fans 31–32

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S13-01 | Health | (사이트 설명 없음) 배터리 성능 상태를 보여 주는 표시 행이다. | - | - | 시스템 설정 값과 맞춘다[C:v1.0.186] |
| S13-02 | Cycle Count | (사이트 설명 없음) 배터리 충전 사이클 수를 보여 주는 표시 행이다. | - | - | - |
| S13-03 | Temperature | (사이트 설명 없음) 배터리 온도를 보여 주는 표시 행이다. | - | - | - |
| S13-04 | Fan | (사이트 설명 없음) 팬별 정보와 설정 대상 팬을 보여 주는 행이다. | - | - | 팬 있는 맥 |
| S13-05 | Mode | (사이트 설명 없음) 팬 동작 모드를 고른다. | 자료 없음 | Auto / Manual(고정 속도) / Curve(온도 따라)[H:fan-control] | Fan Control 켬, 백그라운드 헬퍼 필요[H:fan-control] |
| S13-06 | Speed | (사이트 설명 없음) 팬 속도를 정한다. | 자료 없음 | 팬 자체 최소~최대 안에서만. 설정값은 하한이고 macOS가 더 빨리 돌릴 수 있다[H:fan-control] | 95°C에 닿으면 펌웨어에 제어를 돌려준다[H:fan-control] |
| S13-07 | Warn on Low Battery | (사이트 설명 없음, 이름 기준) 배터리가 부족하면 경고한다. | - | 켬/끔 | - |
| S13-08 | Low Battery Threshold | (사이트 설명 없음, 이름 기준) 부족 경고를 낼 배터리 %를 정한다. | - | 값 자료 없음 | - |
| S13-09 | Battery Drain Warnings | 전원 미연결 상태에서 어떤 앱이 몇 분째 CPU를 많이 쓰면 경고한다. | - | 켬/끔 | 기준: CPU 80% 이상 3분 연속, 같은 앱은 1시간에 1번, 시스템 프로세스 제외[H:battery-drain-warning] |
| S13-10 | Accessories Low Battery | 마우스, 키보드, iPhone, iPad 배터리가 부족하면 경고한다. | - | 켬/끔 | - |
| S13-11 | Charging Island | 충전기를 꽂으면 짧은 알약을 띄운다. | - | 켬/끔 | - |
| S13-12 | Unplug Island | 전원을 뽑으면 남은 시간이 담긴 알약을 띄운다. | - | 켬/끔 | - |
| S13-13 | Full Charge Island | 완충 기준에 닿으면 알약을 띄운다. 충전기를 뽑을 때라는 신호다. | - | 켬/끔 | - |
| S13-14 | Full Charge Level | (사이트 설명 없음, 이름 기준) 완충 알림 기준 %를 정한다. | - | 값 자료 없음 | - |
| S13-15 | Screen Glow | 배터리 부족·완충 알림 때 화면 테두리에 부드러운 빛을 깜빡인다. | - | 켬/끔 | - |
| S13-16 | Low Battery | (사이트 설명 없음, 이름 기준) 배터리 부족 알림 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S13-17 | Plugged In | (사이트 설명 없음, 이름 기준) 전원 연결 알림 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S13-18 | Unplugged | (사이트 설명 없음, 이름 기준) 전원 분리 알림 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S13-19 | Fully Charged | (사이트 설명 없음, 이름 기준) 완충 알림 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S13-20 | Accessory Low | (사이트 설명 없음, 이름 기준) 액세서리 배터리 부족 알림 소리를 고른다. | - | 소리 목록 자료 없음 | - |
| S13-21 | Accessory Fully Charged | (사이트 설명 없음, 이름 기준) 액세서리 완충 알림 소리를 고른다. | - | 소리 목록 자료 없음 | S14-04와 이름이 같다 → 섹션 4 |
| S13-22 | Battery in Menu Bar | iPhone처럼 퍼센트가 안에 든 배터리 아이콘을 메뉴 막대에 둔다. 누르면 모든 기기 배터리를 보여 준다. | - | 켬/끔 | - |
| S13-23 | Low Power Mode | macOS 저전력 모드를 켜고 끈다. | - | 켬/끔 | 바꿀 때마다 관리자 비밀번호 필요 |
| S13-24 | Limit Charging | 건강한 수준에서 충전을 멈춰 배터리 마모를 늦춘다. | - | 50%~100%[H:charge-limit] | 처음 한 번 관리자 비밀번호(헬퍼 설치). 미지원 모델은 'Not supported on this Mac'. Apple 실리콘·인텔 MacBook[H:system-requirements] |
| S13-25 | Background Helper | 업데이트된 충전 헬퍼가 준비됐다고 알리는 상태 행이다. 업데이트할 때 관리자 비밀번호를 묻는다. | - | - | 관리자 비밀번호 |
| S13-26 | Stop Charging At | 충전을 멈출 수준을 정한다. 이 맥은 macOS 자체 Charge Limit을 거쳐야 한다는 상태 문구가 붙어 있다. | 자료 없음 | 50%~100%[H:charge-limit] | 일부 맥은 macOS Charge Limit 경유(사이트 문구 기준) |
| S13-27 | Sailing Mode | 한도보다 몇 %p 떨어질 때까지 다시 충전하지 않는다. | - | 켬/끔 | Limit Charging 켬 |
| S13-28 | Automatic Discharge | 전원이 꽂혀 있어도 한도보다 높으면 배터리로 돌아 한도까지 내린다. | - | 켬/끔 | Limit Charging 켬 |
| S13-29 | Top Up to 100% | 이번 한 번만 100%까지 충전하고 이후 한도로 돌아간다. | - | - | 버튼. 여행용[H:charge-limit] |
| S13-30 | Remove Charge Helper | 정상 충전을 되살리고 백그라운드 헬퍼를 지운다. | - | - | 버튼. 팬 제어도 같은 헬퍼를 쓴다[H:fan-control] |
| S13-31 | Fan Control (Beta) | 팬 속도나 온도 곡선을 정한다. 맥 자체의 열 보호는 항상 켜져 있다. | 자료 없음 | Auto / Manual / Curve(S13-05) | 베타. 관리자 비밀번호(헬퍼). 일부 맥 펌웨어는 미지원[H:fan-control] |
| S13-32 | All Fans Automatic | 모든 팬을 맥 자동 제어로 돌려준다. | - | - | 버튼 |

### P14. Connectivity (연결)

- 주소: https://notchy.dev/help/settings/#page-connectivity
- 행 수: 9
- 구역: (소제목 없음) 1–2 · Notifications 3–4 · Network 5–7 · Actions 8–9

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S14-01 | AirPods | (사이트 설명 없음) AirPods 상태 표시 행이다. | - | - | 블루투스 권한(S11-03) |
| S14-02 | Wi-Fi | (사이트 설명 없음) Wi-Fi 상태 표시 행이다. | - | - | - |
| S14-03 | Connect & Disconnect Alerts | AirPods가 연결·해제되거나 근처에서 케이스가 열리면 팝업을 띄운다. 끄면 근처 AirPods 블루투스 탐색도 멈춘다. | - | 켬/끔 | 블루투스 권한(S11-03) |
| S14-04 | Accessory Fully Charged | 마우스, 키보드, iPhone, iPad가 100%가 되면 팝업을 띄운다. | - | 켬/끔 | S13-21과 이름이 같다 → 섹션 4 |
| S14-05 | Network Traffic History | Wi-Fi와 이더넷 사용량 합계를 이 맥에 최대 1년 보관한다. 잠자기 시간은 세지 않는다. | - | 최대 1년 | - |
| S14-06 | Observed Time | (사이트 설명 없음, 이름 기준) 기록이 쌓인 기간을 보여 주는 표시 행이다. | - | - | - |
| S14-07 | Clear Network History | (사이트 설명 없음, 이름 기준) 네트워크 사용량 기록을 지운다. | - | - | 버튼. 되돌릴 수 없는 삭제 |
| S14-08 | Refresh Audio Devices | (사이트 설명 없음, 이름 기준) 오디오 장치 목록을 새로 고친다. | - | - | 버튼 |
| S14-09 | Manage Bluetooth Devices | (사이트 설명 없음, 이름 기준) 블루투스 기기 관리 화면을 연다. | - | - | 버튼 |

### P15. Displays (디스플레이)

- 주소: https://notchy.dev/help/settings/#page-displays
- 행 수: 5
- 구역: (소제목 없음) 1–5

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S15-01 | Choose Displays | Notchy를 띄울 연결 디스플레이를 고른다. | 자료 없음 | S06-07 참고 | S06-07과 설명이 거의 같다 → 섹션 4 |
| S15-02 | Extra Brightness | 지원하는 디스플레이에서 평소 최대보다 더 밝게 한다. 배터리를 더 쓰고 맥이 더 뜨거워진다. | - | 켬/끔 | XDR 디스플레이용[C:v2.0.0] |
| S15-03 | Boost Strength | (사이트 설명 없음, 이름 기준) 추가 밝기의 세기를 정한다. | - | 범위 자료 없음 | 표시 조건: ‘Extra Brightness’ 켬 |
| S15-04 | Display Controls | 내장 포함 모든 디스플레이의 밝기, Extra Dim, 주사율을 조절한다. | - | - | 외장 디스플레이는 Apple 실리콘 맥 필요, 일부 모니터는 미지원 |
| S15-05 | Brightness Keys Control External Displays | 밝기 키로 내장 화면과 함께 외장 디스플레이도 조절한다. | - | 켬/끔 | - |

### P16. Knock (노크)

- 주소: https://notchy.dev/help/settings/#page-knock
- 행 수: 6
- 구역: (소제목 없음) 1–6

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S16-01 | Knock to Control | 맥 본체를 두드리거나 수정 키를 1~3번 탭해 동작을 실행한다. | 꺼짐(옵트인)[H:features-off-after-install] | - | 트랙패드 노크는 입력 모니터링, 측면 노크는 Apple 실리콘 노트북 필요. 안 되면 수정 키 더블탭으로 대체[H:knock-not-working] |
| S16-02 | Sensitivity | (사이트 설명 없음, 이름 기준) 노크 감도를 정한다. | - | 범위 자료 없음 | - |
| S16-03 | Knock Key | 단독으로 1~3번 탭해 노크로 쓸 수정 키를 고른다. | Control[H:knock-not-working] | 수정 키 중 선택, 1~3회 | - |
| S16-04 | Single | (사이트 설명 없음, 이름 기준) 한 번 노크했을 때 실행할 동작을 고른다. | - | 패널·선반·클립보드 열기, 재생/정지, 포모도로 시작, 스크린샷, 화면 잠금 등[H:knock-not-working] | - |
| S16-05 | Double | (사이트 설명 없음, 이름 기준) 두 번 노크했을 때 실행할 동작을 고른다. | - | S16-04와 같음 | - |
| S16-06 | Triple | (사이트 설명 없음, 이름 기준) 세 번 노크했을 때 실행할 동작을 고른다. | - | S16-04와 같음 | - |

### P17. Now Playing (지금 재생 중)

- 주소: https://notchy.dev/help/settings/#page-nowPlaying
- 행 수: 24
- 구역: Local Listening Library 1–3 · Island 4–5 · Tab 6 · Playback & Appearance 7–9 · Media Keys 10 · Default App 11–13 · Lyrics 14–18 · Desktop Lyrics 19–21 · Podcasts & Audiobooks 22–23 · Visualizer 24

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S17-01 | Local Listening History | 최근 청취 기록(recordings)을 이 맥에만 보관하고 업로드하지 않는다. | - | 최대 500개 | 'recordings'가 무엇을 뜻하는지 자료 없음 |
| S17-02 | Clear Listening History | (사이트 설명 없음, 이름 기준) 청취 기록을 지운다. | - | - | 버튼. 되돌릴 수 없는 삭제 |
| S17-03 | Clear Music Bookmarks | (사이트 설명 없음, 이름 기준) 음악 북마크를 지운다. | - | - | 버튼. 북마크 기능 설명 자료 없음 |
| S17-04 | Now Playing Island | 접힌 알약에 재생 중인 곡을 보여 준다. | - | 켬/끔 | - |
| S17-05 | Peek on Hover | 재생 중인 노치에 호버하면 컨트롤이 있는 미니 플레이어를 연다. | - | 켬/끔 | - |
| S17-06 | Now Playing Tab | 컨트롤과 싱크 가사가 있는 전체 플레이어 탭을 켠다. | - | 켬/끔 | S12-50과 같은 탭 |
| S17-07 | Show Track Info | 아티스트와 곡명이 노치에 언제 나타날지 정한다. | 자료 없음 | 선택지 자료 없음 | 도움말은 토글 'Always Show Track Info'로 적는다[H:music-island-too-wide] → 섹션 4 |
| S17-08 | Hide When Paused | 일시정지 후 약 30초 뒤 재생 정보를 지운다. 다시 재생하면 돌아온다. | - | 약 30초 | - |
| S17-09 | Square Album Art | 앨범 커버를 둥근 사각형으로 보여 준다(닫힌 노치, 호버 플레이어, 홈, Now Playing). | 꺼짐[H:square-album-art] | 켬/끔 | 한 번 빠졌다가 복귀[C:v1.0.222] |
| S17-10 | Control Playback with Media Keys | 재생·다음·이전 키를 Notchy가 직접 받아, macOS Now Playing 창이 아일랜드 위에 뜨지 않게 한다. | - | 켬/끔 | 입력 모니터링(미디어 키 가로채기)[H:permissions-notchy-needs]. 헤드폰 재생 버튼과 충돌하면 끈다[C:v1.0.222] |
| S17-11 | Music App | 재생 중인 게 없을 때 Now Playing과 홈에서 열 음악 앱을 고른다. | 자료 없음 | 앱 목록 자료 없음 | - |
| S17-12 | Stop Music from Opening Automatically | 헤드폰 연결이나 재생 키 때문에 macOS가 음악 앱을 열면 그 앱을 종료한다. | - | 켬/끔 | - |
| S17-13 | Open Music App Instead | Notchy가 음악 앱을 막을 때 위에서 고른 앱을 대신 연다. 끄면 재생 키를 눌러도 아무 일도 없다. | - | 켬/끔 | Stop Music from Opening Automatically 켬일 때 의미가 있다 |
| S17-14 | Synced Lyrics | LRCLIB에서 노래방식 싱크 가사를 가져온다. | - | 켬/끔 | 곡명·아티스트를 lrclib.net에 보낸다(앨범·길이도 보낼 수 있음). 녹음 길이와 3초 넘게 다르면 자동 스크롤 안 함[H:lyrics-not-showing] |
| S17-15 | Additional Lyrics Provider | LRCLIB보다 먼저 공개 NetEase 가사를 시도한다. | - | 켬/끔 | 곡명·아티스트를 music.163.com에 보낸다. 지역에 따라 안 될 수 있다 |
| S17-16 | Provider Lyric Translations | 추가 제공자가 번역을 주면 원문 가사와 번역을 함께 보여 준다. | - | 켬/끔 | Additional Lyrics Provider 켬 |
| S17-17 | Lyrics on Pill | 닫힌 노치에 곡명 대신 현재 가사 줄을 보여 준다. | - | 켬/끔 | - |
| S17-18 | Lyrics Timing | 가사가 노래와 어긋날 때 줄을 앞당기거나 늦춘다. | - | 범위 자료 없음 | - |
| S17-19 | Desktop Lyrics | 떠 있는 가사 패널을 띄운다. 일시정지, 잠금, 잠자기, 미러링, 녹화 중엔 숨는다. | - | 켬/끔 | - |
| S17-20 | Lyrics Layout | (사이트 설명 없음, 이름 기준) 데스크톱 가사 배치를 고른다. | - | 선택지 자료 없음 | - |
| S17-21 | Move Desktop Lyrics | 가사 패널 고정을 풀고 초점을 줘서 배경을 끌어 옮기게 한다. | - | - | 버튼 |
| S17-22 | Speed Control in Browsers | 브라우저 탭의 영상·오디오 재생 속도를 바꾼다. 브라우저의 'Apple 이벤트의 JavaScript 허용'이 켜져 있어야 하고, Notchy가 열린 브라우저마다 켜 줄 수 있다. | - | 1×~2×[H:browser-playback-speed] | 켜 두면 그 브라우저를 제어할 수 있는 앱이 페이지에서 스크립트를 돌릴 수 있다. Chrome·Brave·Edge·Vivaldi·Chromium·Safari, 자동화 승인 필요[H:browser-playback-speed] |
| S17-23 | Turn Off Speed Control | 각 브라우저의 'Apple 이벤트의 JavaScript 허용'을 다시 끈다. | - | - | 버튼. v1.0.222 신규[C:v1.0.222] |
| S17-24 | Audio-Reactive Bars | 비주얼라이저 막대가 맥에서 나오는 음악을 따라 움직인다. 끄면 잔잔한 리듬으로 움직인다. | 꺼짐[H:purple-recording-indicator] | 켬/끔 | macOS 14.4 이상. 시스템 오디오 탭 때문에 보라색 녹음 표시가 뜨고 배터리를 조금 더 쓴다[H:purple-recording-indicator] |

### P18. Calendar (캘린더)

- 주소: https://notchy.dev/help/settings/#page-calendar
- 행 수: 20
- 구역: Events & Tasks 1–2 · Calendar Sources 3–4 · Live Activity 5–7 · Menu Bar 8–10 · Keyboard Shortcuts 11–12 · Full-Screen Meeting Alert 13–16 · Connect Another Calendar 17 · Next Event 18 · (소제목 없음) 19–20

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S18-01 | Manage Calendar Events | Apple 캘린더에 일회성 일정을 추가, 편집, 삭제한다. 입력한 날짜를 미리 보여 준다. | - | 켬/끔 | 캘린더 권한(S11-04) |
| S18-02 | Calendar with Due Tasks | 마감이 된 미리 알림을 일정과 함께 보여 준다. | - | 켬/끔 | 미리 알림 권한(S11-05) |
| S18-03 | Add Calendar Accounts | Google, Microsoft 등 계정은 시스템의 인터넷 계정에서 추가하라고 안내한다. 추가하면 여기에 자동으로 나온다. | - | - | Notchy는 Google·Microsoft에 직접 로그인하지 않는다[H:calendar-setup] |
| S18-04 | Use macOS Calendars | 캘린더 앱 일정을 보여 준다. 끄려면 먼저 캘린더 링크나 CalDAV 계정을 추가해야 한다. | 켬[H:calendar-setup] | 켬/끔 | 캘린더 권한(S11-04) |
| S18-05 | Upcoming Event Island | 일정 시작 전 카운트다운 아일랜드를 띄운다. | 꺼짐(옵트인 'Meeting Countdown')[H:features-off-after-install] | 켬/끔 | 회의 링크가 있으면 Join 동작이 붙는다[H:calendar-meeting-countdown] |
| S18-06 | Lead Time | (사이트 설명 없음) 일정 몇 분 전부터 카운트다운을 띄울지 정한다[H:calendar-meeting-countdown]. | 자료 없음 | 분 단위, 값 자료 없음 | - |
| S18-07 | Keep Until Joined or Dismissed | 아일랜드가 몇 초 뒤 사라지지 않고 Join·Dismiss 버튼과 함께 노치에 남는다. | - | 켬/끔 | - |
| S18-08 | Next Meeting in Menu Bar | 메뉴 막대에 다음 일정과 남은 시간을 보여 준다. 누르면 월 달력이 열린다. | - | 켬/끔 | - |
| S18-09 | Show Event Title | 메뉴 막대에 일정 제목을 보인다. 끄면 카운트다운만 나온다. | - | 켬/끔 | Next Meeting in Menu Bar 켬 |
| S18-10 | Show Date in Icon | Calendar와 Next Meeting 아이콘에 오늘 월·일을 넣는다. | - | 켬/끔 | - |
| S18-11 | Open Calendar Shortcut | (사이트 설명 없음, 이름 기준) 캘린더를 여는 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | - |
| S18-12 | Join Meeting Shortcut | (사이트 설명 없음, 이름 기준) 다음 회의에 참가하는 단축키를 기록한다. | 자료 없음 | - | - |
| S18-13 | Full-Screen Alert | 모든 디스플레이를 덮는 회의 알림과 Join 버튼을 띄운다. | - | 켬/끔 | - |
| S18-14 | Alert Timing | (사이트 설명 없음, 이름 기준) 전체 화면 알림을 띄울 시점을 정한다. | - | 값 자료 없음 | - |
| S18-15 | Only Meetings with a Join Link | Zoom, Meet, Teams 등 화상 회의 링크가 없는 일정은 전체 화면 알림에서 뺀다. | - | 켬/끔 | - |
| S18-16 | Preview Alert | 예시 회의 알림을 바로 띄운다. Esc로 닫는다. | - | - | 버튼 |
| S18-17 | Calendar Link or CalDAV | 읽기 전용 .ics 링크나 CalDAV 계정을 추가한다. | - | .ics 링크 / CalDAV | 읽기 전용 |
| S18-18 | Up Next | (사이트 설명 없음) 다음 일정 표시와 관련된 행이다. 자료 없음. | - | - | - |
| S18-19 | Connection Type | 연결 방식을 고른다. 캘린더 공유 설정의 비공개 .ics 링크를 붙여 넣으라고 안내한다. | 자료 없음 | .ics 링크 / CalDAV | - |
| S18-20 | Calendar Access | 캘린더 접근이 허용되지 않았다는 상태 행이다. 시스템 설정에서 켜라고 안내한다. | - | - | 캘린더 권한 |

### P19. Timer (타이머)

- 주소: https://notchy.dev/help/settings/#page-timer
- 행 수: 26
- 구역: Tab 1–2 · Pomodoro Lengths 3–5 · Pomodoro Stats 6–8 · Break Reminders 9–12 · Distraction Blocking 13–14 · Sound 15–16 · (소제목 없음) 17–18 · Quick Start 19–22 · Quick Access 23–25 · Focus Sounds 26

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S19-01 | Timer Tab | 노치에 실시간 카운트다운을 보여 주는 타이머 탭을 켠다. | - | 켬/끔 | - |
| S19-02 | Controls on Hover | 실행 중인 타이머에 호버하면 일시정지, 1분 추가, 정지를 할 수 있다. | - | 켬/끔 | - |
| S19-03 | Focus Length | 새 집중 세션의 길이를 정한다. 진행 중인 세션은 원래 길이를 유지한다. | 자료 없음 | 값 자료 없음 | - |
| S19-04 | Break Length | (사이트 설명 없음, 이름 기준) 짧은 휴식 길이를 정한다. | 자료 없음 | 값 자료 없음 | - |
| S19-05 | Long Break Length | (사이트 설명 없음, 이름 기준) 긴 휴식 길이를 정한다. | 자료 없음 | 값 자료 없음 | - |
| S19-06 | Today | (사이트 설명 없음, 이름 기준) 오늘 포모도로 기록을 보여 주는 표시 행이다. | - | - | - |
| S19-07 | Current Streak | (사이트 설명 없음, 이름 기준) 연속 기록을 보여 주는 표시 행이다. | - | - | - |
| S19-08 | Recorded Total | (사이트 설명 없음, 이름 기준) 누적 기록을 보여 주는 표시 행이다. | - | - | - |
| S19-09 | Look Away | 20-20-20 규칙에 따라 먼 곳을 보며 눈을 쉬라고 알린다. | - | 켬/끔 | - |
| S19-10 | Stand Up | 의자에서 일어나라고 알린다. | - | 켬/끔 | - |
| S19-11 | Every | (사이트 설명 없음, 이름 기준) 휴식 알림 간격을 정한다. | - | 값 자료 없음 | - |
| S19-12 | Drink Water | 다른 두 알림 사이에 물을 마시라고 알린다. | - | 켬/끔 | - |
| S19-13 | Block Apps While Focusing | 집중 단계에서 목록의 앱이 앞으로 나오면 숨긴다. 앱을 종료하지는 않는다. | - | 켬/끔 | 휴식 중엔 막지 않는다[H:pomodoro-block-apps] |
| S19-14 | Add an App | 차단할 앱을 추가한다. 비어 있으면 아직 막는 앱이 없다고 표시한다. | - | - | 버튼 |
| S19-15 | Play Sound When Timer Ends | (사이트 설명 없음, 이름 기준) 타이머가 끝나면 소리를 낸다. | - | 켬/끔 | - |
| S19-16 | Repeat Timer Alarm | 반복 알람이 언제 멈출지 고른다. | 꺼짐(신규 옵션은 꺼진 채 시작)[C:v1.0.195] | 선택지 자료 없음 | - |
| S19-17 | Start a Timer | (사이트 설명 없음, 이름 기준) 타이머를 시작한다. | - | - | 버튼 |
| S19-18 | Mascot | 포모도로 카운트다운 옆에 마스코트를 보여 준다. | - | 마스코트 목록 자료 없음 | - |
| S19-19 | Stop Timer | (사이트 설명 없음, 이름 기준) 실행 중인 타이머를 멈추는 빠른 동작이다. | - | - | 버튼 |
| S19-20 | Stop Pomodoro | (사이트 설명 없음, 이름 기준) 진행 중인 포모도로를 멈추는 빠른 동작이다. | - | - | 버튼 |
| S19-21 | Start Pomodoro | (사이트 설명 없음, 이름 기준) 포모도로를 시작하는 빠른 동작이다. | - | - | 버튼 |
| S19-22 | Repeat Timer | 타이머가 끝나면 같은 길이로 다시 시작한다. 맥 앞을 비우면 반복을 멈춘다. | - | 켬/끔 | v1.0.226 신규[C:v1.0.226] |
| S19-23 | Start Pomodoro Shortcut | (사이트 설명 없음, 이름 기준) 포모도로를 시작하는 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | S01-03과 겹친다 |
| S19-24 | Pomodoro Only | Standard 모드를 숨기고 바로 집중 세션으로 연다. | - | 켬/끔 | S01-03과 겹친다 |
| S19-25 | Continue Automatically | 휴식과 다음 집중 세션을 누르지 않아도 자동으로 시작한다. | - | 켬/끔 | - |
| S19-26 | Focus Sounds | 타이머나 선택형 홈 카드에서 환경음을 튼다. | - | 소리 목록 자료 없음 | - |

### P20. Clipboard (클립보드)

- 주소: https://notchy.dev/help/settings/#page-clipboard
- 행 수: 17
- 구역: (소제목 없음) 1–3 · History 4–9 · Privacy 10 · Shortcuts 11–12 · Links 13 · Auto-Clear 14–15 · Saved Lists 16 · Snippets 17

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S20-01 | Clipboard History | 최근 복사 내용을 보관하고 한 번 눌러 복원한다. | 자료 없음 | 켬/끔 | 이 맥에만 저장. 비밀번호 관리자의 숨김 복사는 기록하지 않는다[H:clipboard-history] |
| S20-02 | Open Clipboard Shortcut | (사이트 설명 없음, 이름 기준) 클립보드 기록을 여는 단축키를 기록한다. | ⌃⌥C[H:keyboard-shortcuts] | - | - |
| S20-03 | Paste as Plain Text Shortcut | (사이트 설명 없음, 이름 기준) 서식 없이 붙여넣기 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | - |
| S20-04 | Stored Items | (사이트 설명 없음, 이름 기준) 저장된 항목 수를 보여 주는 표시 행이다. | - | - | - |
| S20-05 | History Limit | (사이트 설명 없음) 기록을 몇 개까지 보관할지 정한다. | 40[H:clipboard-history] | 40 / 100 / 200 / 500[H:clipboard-history] | 고정 항목은 한도에서 빠진다. 한도를 낮추면 먼저 확인을 묻는다[C:v1.0.224] |
| S20-06 | Keep History After Quitting | 앱을 재시작해도 기록을 남긴다. 이 맥에만 저장한다. | 켬[H:clipboard-history] | 켬/끔 | - |
| S20-07 | Capture Sound | 새 복사가 저장될 때마다 짧은 소리를 낸다. | - | 켬/끔 | - |
| S20-08 | Sound | (사이트 설명 없음, 이름 기준) 복사 저장 소리를 고른다. | - | 소리 목록 자료 없음 | Capture Sound 켬 |
| S20-09 | Clear History | 저장된 복사 기록을 지금 모두 지운다. | - | - | 버튼. 고정 항목은 남는다[H:clipboard-exclude-apps] |
| S20-10 | Ignore an App | 기록하지 않을 앱을 추가한다. 그 앱이 앞에 있을 때 한 복사는 기록되지 않는다. | - | - | 버튼 |
| S20-11 | Copy Twice to Open | ⌘C를 두 번 눌러 기록을 연다. | - | 켬/끔 | - |
| S20-12 | Paste with 1–9 | 기록이 열린 상태에서 숫자를 누르면 그 항목을 앞의 앱에 붙여 넣는다. | - | 켬/끔 | - |
| S20-13 | Tracking Links | 복사한 링크의 추적용 파라미터를 찾아 깨끗한 링크를 제안하거나, 복사 즉시 지운다. | 자료 없음 | 제안 / 복사 즉시 제거. 정확한 라벨 자료 없음 | - |
| S20-14 | Empty the Clipboard | 일정 시간 아무것도 안 하면 지금 붙여넣기 될 내용을 비운다. 기록은 남긴다. | - | 켬/끔 | - |
| S20-15 | Clear After | 클립보드를 비우기까지의 유휴 시간을 정한다. | - | 값 자료 없음 | Empty the Clipboard 켬 |
| S20-16 | Sync Saved Items with iCloud | 저장한 텍스트 항목과 목록을 iCloud로 다른 맥과 맞춘다. 이미지와 일반 기록은 이 맥에 남는다. | 꺼짐[H:clipboard-sync] | 켬/끔 | iCloud 계정 필요 |
| S20-17 | Save Snippet from Clipboard | 지금 클립보드 내용을 ⌘K 팔레트에서 붙여 넣을 재사용 텍스트(스니펫)로 저장한다. | - | - | 버튼 |

### P21. Caffeine (카페인(잠자기 방지))

- 주소: https://notchy.dev/help/settings/#page-caffeine
- 행 수: 6
- 구역: (소제목 없음) 1–4 · Quick Durations 5 · Actions 6

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S21-01 | Until a Time | (사이트 설명 없음, 이름 기준) 정한 시각까지 맥을 깨어 있게 한다. | - | 시각 지정 | - |
| S21-02 | Caffeine | 맥이 잠들지 않게 한다. | - | 켬/끔 | - |
| S21-03 | Stay Awake with the Lid Closed | 덮개를 닫아도 맥을 깨어 있게 한다. 승인을 기다리는 중이라는 상태 문구가 붙는다. | - | 켬/끔 | 시스템 전원 설정을 바꾸므로 관리자 비밀번호 필요[H:keep-mac-awake] |
| S21-04 | Disconnect Mouse and Keyboard | 덮개를 닫으면 블루투스 마우스, 키보드, 트랙패드 연결을 끊어 배터리 소모를 막는다. 헤드폰은 연결을 유지한다. | - | 켬/끔 | - |
| S21-05 | Until Stopped | 멈출 때까지 계속 깨어 있게 하는 빠른 지속 시간이다. 상태 문구는 'Active'다. | - | - | 버튼 |
| S21-06 | Deactivate Caffeine | Caffeine을 끄고 평소처럼 잠들게 한다. | - | - | 버튼 |

### P22. Cuely (큐리(텔레프롬프터))

- 주소: https://notchy.dev/help/settings/#page-cuely
- 행 수: 11
- 구역: Tab 1 · Auto-Scroll 2–3 · Teleprompter Size 4–6 · Manual Scroll 7 · Voice Mode (Beta) 8 · Actions 9 · (소제목 없음) 10–11

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S22-01 | Cuely Tab | 웹캠 바로 아래에 텔레프롬프터를 띄우는 탭을 켠다. | - | 켬/끔 | - |
| S22-02 | Scroll Speed | (사이트 설명 없음, 이름 기준) 자동 스크롤 속도를 정한다. | - | 범위 자료 없음 | - |
| S22-03 | Font Size | (사이트 설명 없음, 이름 기준) 텔레프롬프터 글자 크기를 정한다. | - | 범위 자료 없음 | - |
| S22-04 | Width | (사이트 설명 없음, 이름 기준) 텔레프롬프터 띠의 너비를 정한다. | - | 범위 자료 없음 | - |
| S22-05 | Height | (사이트 설명 없음, 이름 기준) 텔레프롬프터 띠의 높이를 정한다. | - | 범위 자료 없음 | - |
| S22-06 | Use Default Size | 텔레프롬프터 크기를 기본값으로 되돌린다. 읽는 중에 띠 모서리를 끌어 크기를 바꿀 수 있다고 안내한다. | - | - | 버튼 |
| S22-07 | Scroll Manually | 자동 스크롤 없이 마우스, 트랙패드, 화살표 키로 직접 대본을 넘긴다. | - | 켬/끔 | - |
| S22-08 | Follow My Voice | 내가 읽는 속도에 맞춰 스크롤을 넘긴다. 권한이 거부되면 자동 스크롤로 돌아간다. | - | 켬/끔 | 베타. 마이크·음성 인식 권한(S11-12, S11-13) |
| S22-09 | Start Session | 알약을 열고 자동 스크롤을 시작한다. | - | - | 버튼 |
| S22-10 | Voice Permissions | 마이크와 음성 인식이 허용됐다는 상태 행이다. | - | - | - |
| S22-11 | Presets | 한 번 눌러 고르는 속도 프리셋이다. | - | 프리셋 값 자료 없음 | - |

### P23. AI Usage (AI 사용량)

- 주소: https://notchy.dev/help/settings/#page-aiUsage
- 행 수: 13
- 구역: Tab 1–2 · Live Agent Activity 3–5 · Privacy 6 · Notifications 7–9 · Sound Notifications 10 · Menu Bar 11 · Usage Display 12 · (소제목 없음) 13

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S23-01 | AI Usage Tab | Claude, Codex, Cursor, Antigravity, Copilot 사용량을 이 맥에서 읽어 보여 주는 탭을 켠다. | - | 켬/끔 | 로컬 로그만 읽고 권한·키 불필요. 원격 한도는 Accounts & Credentials에서 API 키·토큰 추가(키체인 저장)[H:ai-usage-setup] |
| S23-02 | Compact Layout | Claude Code나 Codex를 작은 카드 두 장(리셋 시각이 붙은 한도, 오늘 API 비용 추정)으로 보여 준다. | - | 켬/끔 | - |
| S23-03 | Agent Permission Islands | Claude Code나 Codex가 권한이나 입력을 기다리는 순간 노치에 아일랜드를 띄우고 터미널로 이동 버튼을 준다. | - | 켬/끔 | ~/.claude/settings.json, ~/.codex/hooks.json에 훅 설치(끄면 제거). Codex는 훅 신뢰를 한 번 묻는다[H:claude-code-notifications] |
| S23-04 | Approve & Deny from the Notch | Claude Code와 Codex 권한 요청을 아일랜드에서 바로 승인·거부한다. 누를 때까지 에이전트가 기다리고, 시간이 지나면 원래 프롬프트로 넘어간다. | - | 켬/끔 | 2분 안에 답이 없으면 터미널 프롬프트로 돌아간다[H:claude-code-notifications]. Agent Permission Islands 필요 |
| S23-05 | Session Cost Summary | Claude Code 답변이 끝날 때마다 대화 전체의 추정 API 비용과 그 답변의 비용을 보여 준다. | - | 켬/끔 | - |
| S23-06 | Hide Personal Information | AI Usage 탭의 프로젝트 이름, 경로, 계정 이메일을 가린다. 화면 표시만 바꾸고 저장된 값은 그대로다. | - | 켬/끔 | - |
| S23-07 | Preview Usage Warning | Claude 쿼터 경고 예시를 노치에 띄운다. | - | - | 버튼 |
| S23-08 | Preview Session Cost Summary | 대화 비용 합계와 마지막 답변 비용 예시를 띄운다. | - | - | 버튼 |
| S23-09 | Limit Warnings | 세션·주간 한도가 바닥나 갈 때, 바닥났을 때, 리셋될 때 알린다. | - | 켬/끔 | - |
| S23-10 | AI Notification Sounds | AI 사용량 알림과 에이전트 승인 소리는 Popups 페이지에서 고른다고 알리는 안내 행이다. | - | - | - |
| S23-11 | Menu Bar Readout | AI Usage가 메뉴 막대에 있을 때 가장 빠듯한 한도를 아이콘 옆에 보여 준다. | - | 켬/끔 | - |
| S23-12 | Reset Sections | 사용량 섹션 순서를 되돌린다. 찾은 제공자 전부를 찾은 순서대로 보여 준다. | - | - | 버튼 |
| S23-13 | Revoke Standing Approvals | (사이트 설명 없음, 이름 기준) 상시 승인으로 저장된 에이전트 권한을 철회한다. | - | - | 버튼 |

### P24. Terminal (터미널)

- 주소: https://notchy.dev/help/settings/#page-terminal
- 행 수: 4
- 구역: Tab 1 · Appearance & Font 2–4

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S24-01 | Terminal Tab | 노치를 열 때 터미널 탭을 보인다. | - | 켬/끔 | - |
| S24-02 | Font Size | (사이트 설명 없음, 이름 기준) 터미널 글자 크기를 정한다. | - | 범위 자료 없음 | - |
| S24-03 | Font | 터미널 글꼴을 고른다. Nerd Font를 쓰면 Powerlevel10k·Starship 프롬프트가 제대로 그려진다. | - | 글꼴 목록 자료 없음 | - |
| S24-04 | Color Scheme | 터미널 글자와 배경 색 구성을 고른다. | - | 구성 목록 자료 없음 | - |

### P25. Stocks (주식)

- 주소: https://notchy.dev/help/settings/#page-stocks
- 행 수: 9
- 구역: (소제목 없음) 1–6 · Add Stock 7 · Appearance 8 · Live Activity 9

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S25-01 | Market data unavailable | (사이트 설명 없음) 시세 데이터를 받을 수 없다는 상태 행이다. | - | - | 인터넷 필요. 시세 출처 Yahoo Finance[H:what-notchy-sends] |
| S25-02 | All Stocks | (사이트 설명 없음, 이름 기준) 등록한 종목 전체 목록이다. | - | - | - |
| S25-03 | Monitor This Stock | 종목별 가격 감시를 켜고 끈다. 끄면 종목과 알림은 남기고 감시만 멈춘다. | - | 켬/끔 | - |
| S25-04 | Remove Stock | 종목과 그 알림을 지운다. | - | - | 버튼. 되돌릴 수 없는 삭제 |
| S25-05 | Condition | (사이트 설명 없음, 이름 기준) 가격 알림 조건을 고른다. | - | 조건 목록 자료 없음 | - |
| S25-06 | Price | (사이트 설명 없음, 이름 기준) 가격 알림 기준 가격을 입력한다. | - | - | - |
| S25-07 | Search | 회사 이름이나 티커로 종목을 찾는다(예: Apple, AAPL, BTC-USD). | - | - | - |
| S25-08 | Company Logos | 회사 로고를 각 회사 웹사이트에서 가져온다. 끄면 맥에서 그린 글자 타일을 쓴다. 관심 종목이 새지 않게 로고 서비스는 쓰지 않는다. | - | 켬/끔 | 켜면 회사 웹사이트에 접속 |
| S25-09 | Show in the Notch | 노치를 실시간 시세판으로 바꾼다. 한 번에 한 종목씩, 오르내림에 따라 색을 입히고 장이 닫히면 조용해진다. | - | 켬/끔 | - |

### P26. Quick Search (빠른 검색)

- 주소: https://notchy.dev/help/settings/#page-quickSearch
- 행 수: 3
- 구역: Add an Engine 1–3

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S26-01 | Name | 추가할 검색 엔진 이름을 입력한다. Quick Search 탭의 버튼에 표시된다. | - | - | - |
| S26-02 | Search URL | (사이트 설명 없음, 이름 기준) 검색 엔진의 검색 URL을 입력한다. | - | URL 형식(검색어 자리 표시 방법) 자료 없음 | - |
| S26-03 | Shortcut | 검색 엔진을 부를 짧은 단축어를 입력한다. | 없음(빈 값) | 영문·숫자, 공백 없음 | - |

### P27. Windows & Spaces (창·스페이스)

- 주소: https://notchy.dev/help/settings/#page-spaces
- 행 수: 8
- 구역: (소제목 없음) 1–2 · Window Snapping 3 · Space Change Island 4 · Current Display 5–6 · Snap Zones 7–8

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S27-01 | Previous Space | (사이트 설명 없음, 이름 기준) 이전 스페이스로 가는 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | - |
| S27-02 | Next Space | (사이트 설명 없음, 이름 기준) 다음 스페이스로 가는 단축키를 기록한다. | 없음[H:keyboard-shortcuts] | - | - |
| S27-03 | Snap Windows to the Notch | 창을 노치 쪽으로 끌어다 놓아 반쪽, 4분의 1, 전체 화면으로 배치한다. | - | 켬/끔 | 손쉬운 사용 권한 필요[H:window-snapping] |
| S27-04 | Show Space Changes | 데스크톱을 바꾸거나 전체 화면 앱에 들어가면 짧은 아일랜드를 띄운다. | - | 켬/끔 | - |
| S27-05 | Current Space | (사이트 설명 없음, 이름 기준) 현재 스페이스를 보여 주는 표시 행이다. | - | - | - |
| S27-06 | Spaces on This Display | (사이트 설명 없음, 이름 기준) 이 디스플레이의 스페이스 목록을 보여 주는 표시 행이다. | - | - | - |
| S27-07 | Tiles per Row | 이 디스플레이에서 스냅 영역을 한 줄에 몇 개씩 놓을지 정한다. | 자료 없음 | 값 자료 없음 | - |
| S27-08 | Restore Default Zones | 스냅 영역을 기본 구성으로 되돌린다. | Left, Top Left, Full, Top Right, Right | - | 버튼. 먼저 확인을 묻는다[C:v1.0.224] |

### P28. Desktop Pet (데스크톱 펫)

- 주소: https://notchy.dev/help/settings/#page-pet
- 행 수: 8
- 구역: Companion 1 · Options 2–3 · Advanced 4–5 · Backup 6–7 · Learn 8

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S28-01 | Desktop Pet | 바탕화면을 돌아다니며 맥 상태에 반응하는 펫을 띄운다. | - | 켬/끔 | - |
| S28-02 | Potty Breaks | 펫이 가끔 쉬면서 작은 웅덩이를 남긴다. | - | 켬/끔 | - |
| S28-03 | Quiet During Focus | 집중 모드와 포모도로 중에는 펫이 아래 구석에서 기다린다. | - | 켬/끔 | - |
| S28-04 | Pet Rides on Windows | 펫이 가끔 창 제목 표시줄에 올라타 함께 움직인다. | - | 켬/끔 | - |
| S28-05 | Pet Visits Other Displays | 디스플레이가 여럿이면 펫이 가끔 다른 화면으로 건너간다. | - | 켬/끔 | 디스플레이 2대 이상 |
| S28-06 | Back Up Pet | 펫, 레벨, 비밀, 모자, Pet Room을 파일로 저장한다. | - | - | 버튼 |
| S28-07 | Restore Pet | 백업 파일의 펫으로 지금 펫을 바꾼다. | - | - | 버튼. 현재 펫을 덮어쓴다 |
| S28-08 | Pet Field Guide | 펫 바로 위에서 펫이 하는 일을 보여 주는 대화형 안내를 연다. | - | - | 버튼 |

### P29. Pointer (포인터)

- 주소: https://notchy.dev/help/settings/#page-pointer
- 행 수: 7
- 구역: Style 1 · Effects 2–5 · Visibility 6 · Text 7

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S29-01 | Pointer Size | macOS 손쉬운 사용에서 정한 포인터 크기에 배율을 곱한다. | - | 범위 자료 없음 | - |
| S29-02 | Click Ripples | 클릭할 때마다 링이 퍼진다. 오른쪽 클릭은 이중 링이다. | - | 켬/끔 | - |
| S29-03 | Pointer Halo | 포인터를 따라다니는 부드러운 링을 그리고, 누르면 오므라든다. | - | 켬/끔 | - |
| S29-04 | Trail | 움직이는 포인터 뒤에 꼬리를 그린다. | - | 켬/끔 | 저전력 모드나 동작 줄이기 중엔 멈춘다 |
| S29-05 | Spotlight | ⌃⌥를 누르는 동안 포인터 주변만 남기고 화면을 어둡게 한다. | - | 키 ⌃⌥(변경 가능 여부 자료 없음) | - |
| S29-06 | Hide Pointer When Idle | 포인터가 멈춰 있으면 모든 앱에서 숨긴다. 마우스를 움직이면 다시 나온다. | - | 대기 시간 자료 없음 | v1.0.226 신규[C:v1.0.226] |
| S29-07 | Text Actions | 어느 앱에서든 글자를 선택하면 복사, 검색, 사전 찾기, 번역 동작을 띄운다. | - | 켬/끔 | - |

### P30. About (정보)

- 주소: https://notchy.dev/help/settings/#page-about
- 행 수: 21
- 구역: Updates 1–4 · Insights 5–8 · Support 9–12 · Backup 13–15 · App 16–21

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S30-01 | Check for Updates | (사이트 설명 없음) 지금 업데이트를 확인한다. | - | - | 버튼 |
| S30-02 | Reminders Skipped | (사이트 설명 없음, 이름 기준) 건너뛴 버전 알림 상태를 보여 주는 표시 행이다. | - | - | - |
| S30-03 | Skip This Version | (사이트 설명 없음) 이번 버전 알림을 그만 받는다[H:update-notchy]. | - | - | 버튼 |
| S30-04 | Automatic Updates | 백그라운드에서 업데이트를 확인·다운로드하고 Notchy를 끌 때 설치한다. macOS가 승인을 물을 수 있다. | 자료 없음 | - | 약 1시간마다 확인, 서명 검사 후 설치[H:update-notchy]. 도움말은 이 행을 두 개(확인·다운로드)로 적는다 → 섹션 4 |
| S30-05 | Notchy Wrapped | 한 해 동안의 노치 사용을 공유용으로 요약한다. | - | - | 버튼 |
| S30-06 | Monthly Receipt | 지난달 노치 사용을 영수증처럼 항목별로 보여 준다. | - | - | 버튼 |
| S30-07 | Share Your Stats | Wrapped 카드를 복사한다. 대신 게시하지는 않는다. | - | - | 버튼 |
| S30-08 | Behind the Scenes | 무엇이 나왔고 무엇이 고장 났고 다음엔 뭐가 오는지 보여 준다. | - | - | 버튼 |
| S30-09 | Send Feedback | 스크린샷이나 녹화를 붙여 버그나 아이디어를 보낸다. 이메일 계정이 없어도 된다. | - | - | 버튼. v2.0.2 신규[C:v2.0.2] |
| S30-10 | Community Discussions | GitHub에서 토론을 시작한다. | - | - | 버튼. GitHub 계정 |
| S30-11 | Crash Reports | 익명 충돌 보고를 어떻게 보낼지 정한다. 앱 버전, macOS 버전, 충돌 스택이 담긴다. | Ask Each Time[H:crash-report-settings] | Ask Each Time / Send Automatically / Never Send[H:crash-report-settings] | 홈 폴더 경로는 지운다. 안 보낸 보고는 14일 보관[H:crash-report-settings] |
| S30-12 | Rate Notchy | 노치에서 한 번 눌러 Notchy를 익명으로 평가한다. | - | - | 버튼 |
| S30-13 | Sync Settings via iCloud | (사이트 설명 없음) iCloud로 여러 맥의 설정을 자동으로 맞춘다. | 꺼짐[H:backup-settings] | 켬/끔 | iCloud 계정 필요 |
| S30-14 | Export Settings | 모든 환경설정을 파일로 저장한다. | - | - | 버튼. 파일 확장자 .notchysettings[H:backup-settings] |
| S30-15 | Import Settings | 내보낸 파일로 지금 환경설정을 바꾼다. | - | - | 버튼. 먼저 확인을 묻는다[C:v1.0.224]. Face Unlock·링크 자동화 스위치는 이 맥 값을 유지한다[C:v1.0.222] |
| S30-16 | Replay Feature Tour | (사이트 설명 없음, 이름 기준) 첫 실행 기능 투어를 다시 본다. | - | - | 버튼 |
| S30-17 | Settings Guide | 모든 설정 페이지와 그 역할을 둘러보는 안내를 연다. | - | - | 버튼 |
| S30-18 | What’s New | (사이트 설명 없음, 이름 기준) 새 기능 소개를 연다. | - | - | 버튼 |
| S30-19 | Clear Cache | (사이트 설명 없음) 캐시가 차지한 용량을 보여 주고 비운다[H:reset-notchy-settings]. | - | - | 버튼 |
| S30-20 | Reset All Settings | 모든 환경설정을 기본값으로 되돌린다. 원래 구성이 필요하면 먼저 백업을 내보내라고 권한다. | - | - | 버튼. 백업 내보내기를 먼저 제안한다[H:reset-notchy-settings] |
| S30-21 | Uninstall Notchy | 앱과 설정, 권한, 셸 훅, 저장 데이터를 함께 지운다. | - | - | 버튼. 되돌릴 수 없다 |

### P31. Screenshots (스크린샷)

- 주소: https://notchy.dev/help/settings/#page-screenshots
- 행 수: 14
- 구역: Screenshots 1–3 · Watermark 4–12 · Ask About the Screen 13–14

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S31-01 | Screenshot to Shelf | 새 스크린샷을 선반에 올려 바로 끌어 쓸 수 있게 한다. | - | 켬/끔 | 파일 및 폴더 권한(스크린샷 폴더, S11-11) |
| S31-02 | Annotate After Capture | Notchy로 찍은 캡처 뒤 마크업 편집기(화살표, 상자, 형광펜, 가림)를 연다. | - | 켬/끔 | 편집기에서 배경·패딩(0~120pt)·모서리(0~24pt)·그림자를 캡처마다 켤 수 있다[H:screenshot-background] |
| S31-03 | Save To | Notchy로 찍은 스크린샷과 녹화를 저장할 위치를 정한다. | 자료 없음 | 폴더 선택 | - |
| S31-04 | Add a Watermark | 마크업 편집기에서 저장하는 스크린샷에 이름이나 로고를 박는다. | - | 켬/끔 | - |
| S31-05 | Watermark Type | (사이트 설명 없음) 워터마크 종류를 고른다. | 자료 없음 | 텍스트 / 이미지로 보인다(아래 행 구성 기준) | 표시 조건: ‘Add a Watermark’ 켬 |
| S31-06 | Watermark Text | (사이트 설명 없음, 이름 기준) 워터마크 글자를 입력한다. | - | - | 표시 조건: ‘Watermark Type’ 켬 |
| S31-07 | Color | (사이트 설명 없음, 이름 기준) 워터마크 글자 색을 고른다. | - | - | 표시 조건: ‘Watermark Type’ 켬 |
| S31-08 | Image | 워터마크로 쓸 이미지를 고른다. 비어 있으면 선택 안 됨으로 표시한다. | - | - | 표시 조건: ‘Watermark Type’ 켬 |
| S31-09 | Position | (사이트 설명 없음, 이름 기준) 워터마크 위치를 고른다. | 자료 없음 | 위치 목록 자료 없음 | 표시 조건: ‘Add a Watermark’ 켬 |
| S31-10 | Watermark Size | 워터마크 높이를 스크린샷 짧은 변에 대한 비율로 정한다. | - | 범위 자료 없음 | 표시 조건: ‘Add a Watermark’ 켬 |
| S31-11 | Watermark Opacity | 워터마크 불투명도를 정한다. 높을수록 덜 투명하다. | - | 범위 자료 없음 | 표시 조건: ‘Add a Watermark’ 켬 |
| S31-12 | Watermark Rotation | 워터마크를 똑바른 상태에서 회전시킨다. | - | 각도 범위 자료 없음 | 표시 조건: ‘Add a Watermark’ 켬 |
| S31-13 | Ask About the Screen | 화면 영역을 골라 글자를 읽고, 링크·날짜를 열고, 그 영역에 대해 질문한다. | - | 켬/끔 | 이미지는 Ask를 누르고 Anthropic API 키가 저장돼 있을 때만 맥 밖으로 나간다. v2.0.0 신규[C:v2.0.0] |
| S31-14 | Ask About the Screen Shortcut | (사이트 설명 없음, 이름 기준) Ask About the Screen 단축키를 기록한다. | 자료 없음 | - | - |

### P32. Typing Sounds (타이핑 소리)

- 주소: https://notchy.dev/help/settings/#page-typingSounds
- 행 수: 8
- 구역: Typing Sounds 1–8

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S32-01 | Typing Sounds | 키를 누를 때마다 클릭 소리를 낸다. 비밀번호 입력란에서는 소리를 내지 않는다. | - | 켬/끔 | 입력 모니터링 권한(S11-09) |
| S32-02 | Sound | 타이핑 소리 종류를 고른다. | 자료 없음 | Mechanical, NK Cream, Holy Panda, Kailh Box Navy, Typewriter, Soft, Blip, Beep, My Sound | - |
| S32-03 | Sound File | My Sound에 쓸 소리 파일을 고른다. 고르기 전엔 Mechanical이 난다. | - | 파일 형식 자료 없음 | Sound가 My Sound일 때 |
| S32-04 | Volume | (사이트 설명 없음, 이름 기준) 타이핑 소리 음량을 정한다. | - | 범위 자료 없음 | - |
| S32-05 | Preview | Typing Sounds를 켜지 않고 고른 소리를 미리 듣는다. | - | - | 버튼 |
| S32-06 | Play In | (사이트 설명 없음) 소리를 낼 범위를 고른다. | 자료 없음 | 선택지 자료 없음 | - |
| S32-07 | Add an App | 소리를 낼 앱을 추가한다. 비어 있으면 아직 어디서도 소리가 나지 않는다고 표시한다. | - | - | 버튼 |
| S32-08 | Pause Typing Sounds Shortcut | (사이트 설명 없음, 이름 기준) 타이핑 소리를 잠시 멈추는 단축키를 기록한다. | 자료 없음 | - | - |

### P33. Face Unlock (얼굴 잠금 해제)

- 주소: https://notchy.dev/help/settings/#page-faceUnlock
- 행 수: 10
- 구역: Battery 1 · Face Unlock 2–7 · (소제목 없음) 8–10

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S33-01 | Face Unlock Only | 노치와 다른 모든 기능을 끄고 얼굴 잠금 해제만 돌린다. 끄면 다른 기능이 돌아온다. | 자료 없음 | 켬/끔 | 구형 맥 배터리 절약용[C:v1.0.226] |
| S33-02 | Unlock with Face | 잠긴 맥에 돌아와 카메라를 보면 잠금을 푼다. | - | 켬/끔 | 내장 카메라 또는 덮개를 닫았을 때 USB 웹캠. 재시작 뒤 첫 잠금은 비밀번호 직접 입력. 보안 기능이 아닌 편의 기능[H:is-face-unlock-secure][H:face-unlock-not-working] |
| S33-03 | Camera Access Not Granted | 카메라 접근이 허용되지 않았다는 상태 행이다. 카메라는 얼굴 학습 때와 복귀 후 몇 초만 쓴다고 알린다. | - | - | 카메라 권한 |
| S33-04 | Accessibility Needed | 손쉬운 사용 권한이 필요하다는 상태 행이다. 잠금 화면에서 비밀번호를 입력하는 데만 쓴다고 알린다. | - | - | 손쉬운 사용 권한 |
| S33-05 | Set Up Again | 얼굴을 다시 스캔하거나 새 비밀번호를 저장한다. | - | - | 버튼 |
| S33-06 | Remove Face Unlock | 키체인에서 저장된 얼굴과 비밀번호를 지운다. | - | - | 버튼. 되돌릴 수 없는 삭제 |
| S33-07 | Set Up Face Unlock | 맥을 바라보는 것만으로 잠금을 풀도록 설정을 시작한다. 몇 초 걸린다. | - | - | 버튼. 맥 로그인 비밀번호(키체인 저장), 카메라, 손쉬운 사용 필요[H:set-up-face-unlock] |
| S33-08 | Match Strictness | 얼굴 일치 기준의 엄격함을 정한다. 왼쪽일수록 엄격해 더 자주 거부하고, 오른쪽 끝은 설정 때 측정한 기준이다. | 자료 없음 | 슬라이더. 도움말은 'Balanced' 선택지를 언급[H:face-unlock-not-working] | - |
| S33-09 | Scan on Spacebar | 잠금 화면에서 스페이스바를 누르면 다시 스캔한다. | - | 켬/끔 | 입력 모니터링 권한(S11-09) |
| S33-10 | Re-authorize Every | Touch ID로 연 저장 비밀번호를 얼굴 잠금 해제용으로 얼마나 열어 둘지 정한다. | 7일[H:face-unlock-not-working] | 1~30일[H:face-unlock-not-working] | Touch ID 보호 저장소를 쓰는 맥만 |

### P34. License (라이선스)

- 주소: https://notchy.dev/help/settings/#page-license
- 행 수: 11
- 구역: License 1–5 · Free Trial 6–7 · This Mac 8 · Support 9 · (소제목 없음) 10 · Activate 11

| ID | 설정 이름 | 동작 | 기본값 | 선택지·범위 | 요구 사항·제약 |
| --- | --- | --- | --- | --- | --- |
| S34-01 | Licensed To | (사이트 설명 없음) 라이선스가 등록된 이름·이메일을 보여 주는 표시 행이다. | - | - | - |
| S34-02 | License Key | (사이트 설명 없음) 라이선스 키를 보여 주는 표시 행이다. | - | - | - |
| S34-03 | Copy License Key | 비밀번호나 Touch ID 확인 뒤 전체 키를 복사한다. 새 맥으로 옮길 때 쓴다. | - | - | 버튼 |
| S34-04 | Check License | 라이선스를 확인한다. | - | - | 버튼. 인터넷 필요 |
| S34-05 | Contact Support | 지원팀에 연락해 라이선스 문제를 해결한다. | - | - | 버튼 |
| S34-06 | Time Left | (사이트 설명 없음, 이름 기준) 무료 체험 남은 기간을 보여 주는 표시 행이다. | - | 체험 7일[C:v2.0.0] | - |
| S34-07 | Ends | (사이트 설명 없음, 이름 기준) 무료 체험 종료일을 보여 주는 표시 행이다. | - | - | - |
| S34-08 | Deactivate This Mac | 이 맥의 라이선스를 해제한다. 맥을 팔거나 지우기 전에 한다. | - | - | 버튼. 라이선스 1개는 맥 1대[H:lost-license-key] |
| S34-09 | Support Info | Notchy 버전, 맥 모델, 라이선스 상태(키는 가림)를 모은 지원용 정보다. | - | - | - |
| S34-10 | One-Time Purchase | 이 맥용 1회 구매 영구 라이선스이고 업데이트가 포함된다는 안내 행이다. | - | - | 구독 없음 |
| S34-11 | Lost Your Key? | 키를 잃어버렸으면 구매 이메일로 다시 보내 준다고 안내한다. | - | - | - |

## 3. 설정에서만 드러나는 기능

기능 소개 페이지에는 잘 안 보이지만 설정 행으로만 존재를 알 수 있는 동작이다. 구현 범위를 정할 때 빠뜨리기 쉬운 것 위주로 묶었다.

| 묶음 | 내용 | 관련 ID |
| --- | --- | --- |
| 탭별 패널 크기 | 패널 모서리를 끌면 탭마다 크기를 따로 기억한다. 패널 크기 방식(Fixed/Dynamic), 최대 높이, 최소 크기 되돌리기가 함께 있다. 홈 카드 최소 크기를 키우면 패널 자체가 넓어진다. | S05-12~S05-18, S03-09, S03-10 |
| 홈 카드 격자 편집 | 노치 안에서 카드를 길게 눌러 순서와 크기를 바꾸고, 열 수를 자동 또는 수동으로 정한다. | S03-07~S03-11 |
| 입력·제스처 매핑 | 노크(본체 두드림 또는 수정 키 1~3회)마다 다른 동작을 건다. 방사형 런처 휠, 탭별 전역 단축키, ⌘C 두 번으로 클립보드 열기, 숫자 1~9로 붙여넣기, Fn 짧게 눌러 받아쓰기, ⌃⌥ 누르는 동안 포인터 스포트라이트가 있다. 트랙패드 스와이프 방향별 스위치는 레퍼런스에 없고 도움말에만 있다(섹션 5). | S16-01~S16-06, S06-15, S06-17~S06-22, S20-11, S20-12, S09-08, S29-05 |
| 화면 공유·녹화 시 숨김 | 캡처에서만 숨기기, 내 화면에서도 숨기기, 미러링 중 숨기기를 고른다. 키 입력 표시는 수정 키 조합만 보이게 해 타이핑 내용을 숨긴다. AI 사용량 탭은 프로젝트 이름·경로·이메일을 가린다. 데스크톱 가사도 미러링·녹화 중엔 숨는다. | S06-13, S06-14, S09-02, S23-06, S17-19 |
| 노치 지우기(검은 메뉴 막대) | 메뉴 막대 띠와 화면 모서리를 검게 칠해 카메라 노치를 안 보이게 한다. | S05-30 |
| 메뉴 막대 정리 | 바텐더류 아이콘 숨김(구분자 2개, 호버 노출, 자동 재숨김, 표시 키), 메뉴 막대 배터리, 다음 회의, Caffeine 토글, AI 한도 표시가 있다. | S04-07~S04-12, S13-22, S18-08~S18-10, S23-11 |
| 잠금 화면 알림 프라이버시 | 잠금 화면 카드에 일정·미리 알림 제목을 보일지 정한다. 기본은 시간만 보인다. 잠금 화면 위젯, 앨범 아트 배경, 배치 미리보기도 설정에만 있다. | S10-16, S10-07~S10-15 |
| 시스템 UI 대체 | macOS 볼륨·밝기 오버레이 숨기기, 미디어 키 직접 처리, macOS 알림 배너 위치 이동, 음악 앱 자동 실행 막기가 있다. | S07-14, S07-15, S17-10, S08-05, S17-12, S17-13 |
| iCloud 동기화 | 앱 설정 전체 동기화와 클립보드 저장 항목 동기화가 별개 스위치다. 둘 다 기본 꺼짐이다. | S30-13, S20-16 |
| 가져오기·내보내기·초기화 | 설정 파일 내보내기·가져오기, 데스크톱 펫 백업·복원, 전체 초기화, 캐시 비우기, 앱 제거가 있다. | S30-14, S30-15, S28-06, S28-07, S30-19~S30-21 |
| 베타 표기 | 팬 제어와 음성 따라 스크롤이 베타로 표시된다. 업데이트 베타 채널은 2.0.3 레퍼런스에 없다(섹션 4). | S13-31, S22-08 |
| 외부 파일·설정 수정 | 긴 명령 아일랜드는 `~/.zshrc`에, 에이전트 권한 아일랜드는 `~/.claude/settings.json`과 `~/.codex/hooks.json`에 훅을 넣는다. 브라우저 속도 제어는 브라우저의 'Apple 이벤트의 JavaScript 허용'을 바꾼다. 앱 제거는 셸 훅까지 지운다. | S09-03, S23-03, S23-04, S17-22, S17-23, S30-21 |
| 관리자 권한 헬퍼 | 충전 한도(세일링 모드, 자동 방전, 100% 충전 포함)와 팬 제어가 같은 백그라운드 헬퍼를 쓴다. 저전력 모드 전환과 덮개 닫고 깨어 있기도 관리자 비밀번호를 묻는다. | S13-23~S13-32, S21-03 |
| 외부로 나가는 데이터 스위치 | 싱크 가사(lrclib.net), 추가 가사(NetEase), 회사 로고(각 회사 사이트), 화면 질문(Anthropic API 키), Ask AI 탭(Anthropic)이 각각 켜야만 외부와 통신한다. | S17-14, S17-15, S25-08, S31-13, S12-54 |
| 로컬 기록 보관·삭제 | 청취 기록 최대 500개, 네트워크 사용량 최대 1년, 앱별 사용 시간, 클립보드 기록과 자동 비우기, 추적 링크 정리가 있다. | S17-01~S17-03, S14-05~S14-07, S02-02, S02-03, S20-01~S20-15 |
| 다중 디스플레이 | 화면별 노치/알약 모양, 표시할 화면 선택, 포인터 있는 화면에만 팝업, 화면별 스냅 영역 줄 수, 외장 화면 밝기 키 연동, 펫의 화면 이동이 있다. | S05-01, S06-07, S15-01, S07-16, S27-07, S15-04, S15-05, S28-05 |
| 진단·복구 | 고정 강제 종료 단축키, 재시작, 강제 종료, 권한 진단 복사, 잠금 화면 보고서 복사가 있다. | S04-13~S04-15, S11-14, S10-18 |
| 집중 보조 | 집중 중 앱 숨기기, 눈·일어서기·물 알림, 집중 중 팝업 끄기, 집중 중에도 알림 미러링 유지, 펫 대기, 팁은 집중·통화 중 안 뜸. | S19-09~S19-14, S07-11, S08-08, S28-03, S07-02 |
| 저전력 단독 모드 | 구형 맥에서 노치와 다른 기능을 모두 끄고 얼굴 잠금 해제만 돌린다. | S33-01 |
| 시각 피드백·접근성 | 단색 인터페이스, 수준별 색 막대, 배터리 알림 화면 빛, 클릭 물결·포인터 후광·꼬리, 대기 시 포인터 숨김, 햅틱이 있다. | S05-19, S05-20, S13-15, S29-01~S29-06, S05-26 |
| 로컬 자동화 | 단축어 액션이나 `notchy://show` 링크로 노치에 메시지를 띄운다. 로컬 TCP API는 레퍼런스에 없고 도움말에만 있다(섹션 5). | S04-05, S04-06 |

## 4. 현행 여부가 불분명한 설정

레퍼런스(2.0.3, 2026-11-01)와 도움말 글(대부분 2026-10-10~11)·변경 이력이 서로 맞지 않거나, 중복·베타·상태 문구로 보이는 것들이다.

### 4.1 중복이거나 같은 설명을 쓰는 행

| 대상 | 근거 | 판단 |
| --- | --- | --- |
| Maximum Height(S05-14) / Panel Height(S05-15) | 설명 문구가 글자 하나 다르지 않고 같다. 사이트는 둘의 표시 조건을 적지 않았다. | Panel Sizing(Fixed/Dynamic) 값에 따라 하나만 나오는 행으로 보이나 확인 못 했다. |
| Show On(S06-07) / Choose Displays(S15-01) | 두 페이지에 거의 같은 설명으로 실려 있다. | 같은 설정의 두 진입점인지 별개 설정인지 자료 없음. |
| Shortcuts & Timer Mode(S01-03) / Start Pomodoro Shortcut·Pomodoro Only(S19-23, S19-24) | 같은 내용이 All Tools와 Timer 두 곳에 있다. | All Tools는 바로가기 모음 페이지로 보인다. |
| Dictation Shortcut(S01-04) / Dictate Text Shortcut(S09-07) | 같은 받아쓰기 단축키가 두 페이지에 다른 이름으로 있다. | 위와 같은 바로가기 중복으로 보인다. |
| Accessory Fully Charged(S13-21 / S14-04) | 같은 이름이 Battery & Fans의 소리 구역과 Connectivity의 알림 구역에 있다. | 하나는 소리 선택, 하나는 팝업 토글로 역할이 다르다. 구현 시 이름 충돌 주의. |
| Hide While Mirroring(S06-14) | 도움말은 Screen Sharing Privacy의 선택지 중 하나처럼 설명한다[H:hide-during-screen-sharing]. 레퍼런스에선 별도 행이다. | 2.0.3에서 별도 토글로 분리된 것으로 보인다. |

### 4.2 이름·위치가 바뀐 것으로 보이는 설정

| 대상 | 근거 | 판단 |
| --- | --- | --- |
| Show with Activities(S05-10) | 2026-10-11 도움말은 음악·타이머 옆에 시계를 계속 두는 설정이 "현재 없다"고 적는다[H:keep-clock-visible]. | 그 뒤에 생긴 설정으로 보이며 도움말이 낡았다. 현행으로 취급한다. |
| Show Track Info(S17-07) | 도움말은 토글 'Always Show Track Info'로 적는다[H:music-island-too-wide]. 레퍼런스 설명은 '언제 보일지' 고르는 형태다. | 토글에서 선택형으로 바뀐 것으로 보인다. 선택지는 자료 없음. |
| Knock to Control(S16-01) | 도움말과 변경 이력은 'Knock to Open'으로 적는다[H:knock-not-working][H:features-off-after-install]. | 이름이 바뀌고 동작 매핑(S16-04~06)이 붙은 것으로 보인다. |
| Keep Shelf Files(S12-29) | 이름은 '보관'인데 설명은 '비울 때 원본은 그대로'다. 도움말에는 Remember Shelf Files(기본 켬), Keep Independent Shelf Copies, Clear Shelf After 24 Hours가 따로 있다[H:file-shelf][C:v1.0.195]. | 여러 선반 설정이 하나로 합쳐졌거나 라벨·설명이 어긋난 것으로 보인다. 동작 불명. |
| Automatic Updates(S30-04) | 도움말은 'Check for Updates Automatically'와 'Download Updates Automatically' 두 스위치로 적는다[H:update-notchy]. | 2.0.3에서 하나로 합쳐진 것으로 보인다. |
| Speed Control in Browsers(S17-22) | 도움말은 먼저 'Long-Form Controls'를 켜라고 한다[H:browser-playback-speed]. 레퍼런스 Podcasts & Audiobooks 구역엔 그 행이 없다. | Long-Form Controls가 없어졌거나 레퍼런스에서 빠졌다. 자료 없음. |
| Calendar Capture(S11-04 설명 속) | 캘린더 권한 설명에만 나오고 같은 이름의 설정 행은 없다. | 옛 이름일 가능성. Manage Calendar Events(S18-01)가 같은 일을 하는지 자료 없음. |
| Face Unlock 설정 위치(P33) | 도움말은 얼굴 잠금 설정이 Settings → Lock Screen에 있고 Detection Distance, Scan on Wake도 있다고 적는다[H:face-unlock-not-working][H:remove-face-unlock]. 레퍼런스는 별도 Face Unlock 페이지이고 두 행이 없다. | 페이지가 분리되며 일부 행이 빠졌거나 숨겨진 것으로 보인다. |
| 잠금 화면 위젯 배치(S10-09, S10-10) | 도움말은 Placement(Below Login 포함), Card Width, Columns, Match Card Heights, 그리고 잠금 알약용 Adjust Lock Screen Position·Pill Vertical Offset을 언급한다[H:lock-screen-widget-placement][H:lock-screen-island-position]. 레퍼런스엔 Horizontal Position과 Vertical Position만 있다. | Placement가 Horizontal Position으로 바뀐 것으로 보인다. 나머지는 현행 여부 불명. |
| 받아쓰기·날씨·배터리 페이지 이름 | 도움말은 Settings → Capture & Files, Settings → Weather, Settings → Battery로 적는다[H:dictation-setup][H:weather-without-location][H:charge-limit]. | 2.0.3에선 Files & Utilities(P09), Home의 Weather 구역(S03-18~20), Battery & Fans(P13)다. Capture & Files는 Notifications에서 갈라져 나온 이름이다[C:v1.0.142]. |

### 4.3 레퍼런스에서 사라진 것으로 보이는 설정

| 대상 | 근거 | 판단 |
| --- | --- | --- |
| 업데이트 베타 채널 | 변경 이력에 "About → Updates에서 프리릴리스 빌드를 받는 옵션" 추가 기록이 있다[C:v1.0.55]. 2.0.3 About → Updates 구역(S30-01~S30-04)엔 없다. | 제거됐거나 레퍼런스 누락. 자료 없음. |
| 데스크톱 펫 추가 옵션 | 변경 이력은 Settings → Pet에 캐릭터 52종, Pet Weather, Fur Colours, Pet Memories, Quick Paws를 적는다[C:v1.0.198]. Desktop Pet 페이지(8행)엔 없다. | 펫 화면 안으로 옮겨졌거나 레퍼런스 누락. |
| 페이지별 Restore Defaults | 도움말은 모든 설정 페이지에 'Restore Defaults' 행이 있다고 적는다[H:change-notch-size][H:reset-notchy-settings]. 513행 어디에도 없다. | 레퍼런스가 일부 공통 행을 빼고 실은 것으로 보인다. |
| About → Developer 구역 | 도움말은 Local API, Regenerate Token, Reset Everything & Relaunch가 About → Developer에 있다고 적는다[H:local-api][H:reset-notchy-settings]. 레퍼런스 About 페이지엔 Developer 구역이 없다. | 숨김 개발자 메뉴이거나 레퍼런스 누락. |
| Behavior → Opening의 호버·스와이프 설정 | 도움말은 Hover Delay, Require Double-Click, Hover Top to Open, Swipe Gestures 묶음을 적는다[H:open-the-island][H:stop-opening-on-hover]. 레퍼런스 Opening 구역엔 3행(S06-01~S06-03)만 있다. | 현행 여부 불명. 섹션 5 참고. |

### 4.4 베타 표기

| 대상 | 근거 |
| --- | --- |
| Fan Control (Beta)(S13-31) | 설정 이름 자체에 Beta가 붙어 있다. 일부 맥 펌웨어는 미지원이다[H:fan-control]. |
| Follow My Voice(S22-08) | 구역 이름이 Voice Mode (Beta)다. 음성 따라 스크롤은 2026-05-27 첫 도입 때부터 베타였다[C:v1.0.9]. |

### 4.5 설정이 아닌 상태 문구가 행으로 실린 것

다음 행은 값을 바꾸는 설정이 아니라, 조건에 따라 뜨는 안내 문구나 조사 당시 앱 상태가 그대로 찍힌 것으로 보인다. 513행에 포함돼 있지만 구현 시 별도 설정으로 만들 필요는 없다.

- 조건부 안내: S03-13, S03-20, S05-07, S05-11, S07-05, S07-06, S09-09, S09-10, S12-28, S13-25, S18-20, S22-10, S25-01, S33-03, S33-04
- 설명 자리에 당시 상태가 찍힌 행: S21-03("승인 대기 중" 문구), S21-05("Active"), S33-01(켜진 상태 문구), S12-44(연결됨 문구), S14-06·S19-06~S19-08·S20-04 같은 값 표시 행

## 5. 참고: 레퍼런스에 없고 도움말 글·변경 이력에만 나오는 설정

513행 집계에는 넣지 않았다. 2.0.3에 실제로 남아 있는지 확인하지 못했으므로 구현 전 실제 앱에서 확인이 필요하다(섹션 4.3 참고).

| 설정 이름 | 출처가 말하는 위치 | 내용 | 근거 |
| --- | --- | --- | --- |
| Hover Delay | Behavior → Opening | 호버 후 패널이 열리기까지 지연. 0~1.5초, 기본 0.25초 | [H:open-the-island] |
| Require Double-Click | Behavior → Opening | 더블클릭해야만 패널이 열림 | [H:open-the-island][H:stop-opening-on-hover] |
| Hover Top to Open | Behavior → Opening | 화면 위 가장자리에 포인터를 밀면 열림 | [H:open-the-island] |
| Swipe Gestures: Swipe to Open / Swipe to Dismiss / Swipe to Change Tabs / Swipe to Change Track | Behavior → Opening | 포인터가 노치 위에 있을 때 두 손가락 스와이프 방향별 동작 | [H:open-the-island][C:v1.0.207] |
| Reveal Over Full-Screen Apps | Behavior → Visibility | 전체 화면에서 숨어 있을 때 위쪽 가운데를 건드리면 노출 | [H:hidden-in-full-screen] |
| Auto-Restart if Frozen | General → Recovery | 12초 응답이 없으면 자동 재시작. 기본 켬 | [H:notchy-frozen] |
| Local API / Regenerate Token | About → Developer | 127.0.0.1:9999에서 토큰 붙은 줄바꿈 JSON(TCP)으로 앱 제어. 기본 꺼짐 | [H:local-api] |
| Reset Everything & Relaunch | About → Developer | 권한·키체인·캐시·훅까지 지우고 새로 설치한 상태로 재시작 | [H:reset-notchy-settings] |
| Check for Updates Automatically / Download Updates Automatically | About | 자동 확인과 자동 다운로드를 따로 켜고 끔 | [H:update-notchy] |
| Beta updates | About → Updates | 프리릴리스 빌드 받기 | [C:v1.0.55] |
| Restore Defaults | 모든 설정 페이지 | 그 페이지만 기본값으로 되돌림 | [H:change-notch-size][H:reset-notchy-settings] |
| Accounts & Credentials / Add Account | AI Usage | 제공자 API 키·토큰을 추가해 원격 한도도 추적. 키는 실제 요청으로 검증 후 키체인 저장 | [H:ai-usage-setup] |
| Long-Form Controls | Now Playing | 팟캐스트·오디오북용 ±15초 건너뛰기와 1×~2× 속도 칩 | [H:browser-playback-speed][C:v1.0.99] |
| Playlist Checkmarks | Now Playing → Playlists | Spotify 재생목록에 현재 곡이 이미 있는지 표시 | [H:spotify-playlist-checkmarks] |
| Spotify 연결(Client ID) | Now Playing의 음악 앱 목록 | 좋아요·셔플·반복·재생목록 추가용. 사용자가 만든 Spotify 개발자 앱의 Client ID와 PKCE 로그인, 리디렉트 http://127.0.0.1:8888/callback | [H:connect-spotify] |
| Copy Media Health Report | Now Playing | 음악 표시 문제 진단 보고서 복사 | [H:now-playing-not-showing][H:bug-report] |
| Remember Shelf Files / Keep Independent Shelf Copies / Clear Shelf After 24 Hours / Preview on Hover | 선반(Shelf) | 재시작 후 선반 유지(기본 켬), 원본 대신 사본 보관, 24시간 뒤 사본 정리, 노치 위에 파일을 들고 있으면 훑어보기 | [H:file-shelf][C:v1.0.195] |
| Snap with the Keyboard / Repeat to Move Across Displays | Windows & Spaces | ⌃⌥⌘ ← / ↩ / →로 창 스냅, 같은 단축키 반복 시 다음 화면으로 이동 | [H:window-snapping][H:keyboard-shortcuts] |
| Detection Distance / Scan on Wake / Screen Light | Face Unlock(도움말상 Lock Screen) | 인식 거리, 화면이 깨면 바로 스캔, 어두운 방에서 화면 조명 | [H:face-unlock-not-working][H:set-up-face-unlock] |
| Adjust Lock Screen Position / Pill Vertical Offset | Lock Screen → Pill | 잠금 화면 알약 위치 보정 | [H:lock-screen-island-position] |
| Placement / Card Width / Columns / Match Card Heights | Lock Screen 위젯 | 위젯 배치(Below Login 포함), 카드 너비, 열 수, 카드 높이 맞춤 | [H:lock-screen-widget-placement] |
| Add a Card | Home | 홈에 카드 추가(예: Clock) | [H:keep-clock-visible] |
| Calendars | Calendar | Notchy에 보일 캘린더 선택 | [H:calendar-setup] |
| Still not working? → Reset & Relaunch | Permissions 각 행 | 해당 권한에 대한 macOS 기록만 지우고 다시 묻기 | [H:permission-granted-not-working] |
| Remove API Key | Ask AI 탭 | 저장된 Anthropic 키 삭제 | [H:ask-ai-api-key] |
| Move to This Mac | License | 새 맥에서 키 입력 후 라이선스 이전. 옛 맥은 몇 시간 안에 멈춤 | [H:lost-license-key] |
| AI Rewrite | 클립보드 | 기기 내 Apple 모델로 교정·어조 변경·요약(최대 6,000자). macOS 26과 Apple Intelligence 필요 | [H:ai-rewrite-unavailable][H:system-requirements] |
| Pet Weather / Fur Colours / Pet Memories / Quick Paws, 캐릭터 52종 | Pet | 펫 부가 기능, 각각 기본 꺼짐 | [C:v1.0.198] |
