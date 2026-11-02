# Notchy 변경 기록·도움말 센터 정리

## 1. 수집 개요

| 항목 | 내용 |
|---|---|
| 수집일 | 2026-11-02 |
| 최신 버전 | v2.0.3 (Build 303), 2026-11-01 |
| 변경 기록 항목 수 | 221개 (2026-05 9개, 06 16개, 07 45개, 08 57개, 09 53개, 10 40개, 11 1개). 가장 오래된 항목은 v1.0.8 (2026-05-24) |
| 날짜가 표기되지 않은 항목 | v1.0.166, v1.0.150, v1.0.144, v1.0.140, v1.0.73 (페이지 순서상 앞뒤 항목 사이 날짜로 추정한다) |
| 목록에 없는 버전 번호 | v1.0.1~v1.0.7, v1.0.35, v1.0.125 |
| 읽은 도움말 문서 | `/help/` 아래 85개 전부(`/help/settings/` 제외) + 도움말 센터 목록에서 연결된 `/help/` 밖 문서 4개(`/uninstall/`, `/hide-macbook-notch/`, `/menu-bar-icons-behind-notch/`, `/notchy-cpu-battery-usage/`) = 89개 |
| 실패한 페이지 | 없음. 모든 페이지가 서버 렌더링 HTML이라 HTTP 200으로 받았고 브라우저 도구는 쓰지 않았다 |
| 보조 확인 | 폐기 여부를 판정하려고 홈페이지(`https://notchy.dev/`)와 설정 참조 페이지(`https://notchy.dev/help/settings/`)에서 키워드만 검색했다. 설정 참조 페이지 본문 정리는 다른 담당 문서의 범위다 |

출처 표기: 변경 기록은 `https://notchy.dev/changelog/#v<버전>` 앵커, 도움말은 `https://notchy.dev/help/<slug>/` 주소를 쓴다. 본문은 모두 의역이다.

## 2. 폐기·변경된 기능

| 기능 | 무슨 일이 있었나 | 버전·날짜 | 대체 수단 | 근거 |
|---|---|---|---|---|
| GitHub PR glance (읽기 전용 토큰으로 열린 PR 수와 검토 아일랜드 표시) | **제거(확인)**. 1.0.45에서 추가되고 1.0.49에서 토큰 입력란을 다듬은 뒤 1.0.95 수정 목록에서 제거되었다고 적혀 있다. 도움말과 설정 참조 페이지에는 GitHub PR 항목이 없고 GitHub는 피드백 게시판으로만 나온다. 홈페이지 "Building & shipping" 묶음에는 아직 "GitHub PRs"가 남아 있어 홈페이지가 낡은 상태다 | v1.0.95, 2026-08-09 | 없음 | https://notchy.dev/changelog/#v1.0.95 , https://notchy.dev/changelog/#v1.0.45 |
| Google 직접 로그인 (캘린더) | **폐기(확인)**. 1.0.173에서 추가되었고, 1.0.173 항목에 붙은 후속 메모가 1.0.208에서 폐기되었다고 밝힌다. 1.0.208 본문 자체에는 이 내용이 없다. 현재 도움말은 Notchy가 Google·Microsoft에 직접 로그인하지 않는다고 명시한다 | v1.0.208, 2026-10-13 | 시스템 설정 → 인터넷 계정에 Google 계정을 추가하면 macOS 캘린더로 표시된다. 또는 Google의 iCal 비밀 주소(.ics, 읽기 전용) | https://notchy.dev/changelog/#v1.0.173 , https://notchy.dev/help/calendar-setup/ |
| Microsoft 직접 로그인 (Outlook·Microsoft 365) | **폐기(확인)**. Google과 같은 메모로 함께 폐기되었다 | v1.0.208, 2026-10-13 | 인터넷 계정에 Microsoft 365·Exchange 추가, 또는 Outlook 게시 캘린더 .ics 링크 | https://notchy.dev/changelog/#v1.0.173 , https://notchy.dev/help/calendar-setup/ |
| Microsoft To Do (작업 소스) | **폐기(확인)**. 같은 메모에서 To Do도 폐기되었다고 적는다 | v1.0.208, 2026-10-13 | 직접 대체 없음. 현재 작업 소스는 Apple Reminders와 Todoist뿐이다 | https://notchy.dev/changelog/#v1.0.173 , https://notchy.dev/help/calendar-setup/ |
| 사용자 Lottie idle 애니메이션 (닫힌 노치에 자기 Lottie JSON·.lottie 재생, 속도·크기·위치 편집기) | **폐기 기록 없음, 현행 여부 미확정**. 1.0.51 추가, 1.0.57·1.0.59·1.0.61·1.0.75·1.0.77 수정, 1.0.78에서 .lottie 번들 지원이 마지막 언급이다. 이후 변경 기록, 도움말 89개, 설정 참조 페이지(Appearance 포함)에서 이 기능이 보이지 않는다. 1.0.220은 드물게 쓰는 설정 약 80개를 삭제·통합했다고만 하고 목록은 밝히지 않는다. 홈페이지는 여전히 "Custom Idle Animation"을 소개한다 | 마지막 언급 v1.0.78, 2026-07-29 | 해당 없음 | https://notchy.dev/changelog/#v1.0.51 , https://notchy.dev/changelog/#v1.0.78 , https://notchy.dev/changelog/#v1.0.220 |
| 카메라·마이크 사용 중 표시 아일랜드 | **제거**. 1.0.51에서 추가된 사용 중 표시 알약이 사라졌다 | v1.0.166 (날짜 미표기, 2026-09-13~14 사이) | Camera Guard(켜 둔 경우 경고), 헤더 Camera 버튼(1.0.123, 카메라 사용 중 녹색) | https://notchy.dev/changelog/#v1.0.166 |
| 정기 후원 팝업 | **제거**. 1.0.175에서 헤더 하트로 줄였고 1.0.202에서 예약 팝업을 없앴다. 1.0.223부터 Support 버튼도 숨길 수 있다 | v1.0.202, 2026-10-09 | 헤더 Support 버튼 → 2.0.0 유료화 | https://notchy.dev/changelog/#v1.0.202 |
| 무료·후원 모델 | **변경**. 유료 앱으로 전환했다. 7일 체험 동안 전 기능을 쓰고 이후 1회 구매로 계속 쓴다. Ko-fi·Buy Me a Coffee 후원자에게는 무료 라이선스를 메일로 보낸다. 라이선스는 한 번에 Mac 한 대다 | v2.0.0, 2026-10-26 | Settings → License | https://notchy.dev/changelog/#v2.0.0 , https://notchy.dev/help/lost-license-key/ |
| 드물게 쓰는 설정 약 80개 | **삭제·통합**. 일부는 요청으로 1.0.222에서 복귀했다(Control Playback with Media Keys, Square Album Art, Pill Height Adjustment, Animation Speed, Collapse Delay) | v1.0.220, 2026-10-17 / 복귀 v1.0.222, 2026-10-19 | 복귀 항목 외 목록 미공개 | https://notchy.dev/changelog/#v1.0.220 , https://notchy.dev/changelog/#v1.0.222 |
| Hide from Screen Capture 스위치 | **변경(대체)**. 삭제 시점은 기록이 없고 1.0.202에서 Settings → Behavior로 돌아왔다. 현재 도움말은 "Screen Sharing Privacy" 3지선다(Hidden from Captures / Hidden Everywhere / Hide While Mirroring)로 설명한다. 1.0.196의 "Hide Pill for Sharing"이 Hidden Everywhere에 해당한다 | 복귀 v1.0.202, 2026-10-09 | Screen Sharing Privacy | https://notchy.dev/changelog/#v1.0.202 , https://notchy.dev/help/hide-during-screen-sharing/ |
| Minimalistic UI | **이름 변경**. 1.0.136의 "Minimalistic UI"가 현재 "Use Minimal Layout"이다. 변경 기록에서 새 이름은 1.0.218부터 보인다 | 1.0.136 → 1.0.218 무렵 | Minimal Layout | https://notchy.dev/changelog/#v1.0.136 , https://notchy.dev/help/minimal-layout/ |
| Black Out Screen Corners | **통합**. 1.0.174에서 별도 옵션으로 추가되었고, 1.0.220부터 Hide the Notch를 켜면 둥근 모서리도 자동으로 검게 칠한다 | v1.0.220, 2026-10-17 | Settings › Appearance › Hardware Notch › Hide the Notch | https://notchy.dev/changelog/#v1.0.174 , https://notchy.dev/hide-macbook-notch/ |
| 클립보드 전역 단축키 | **변경**. ⇧⌘V(1.0.8) → ⌃⌥C(1.0.13, 재지정 가능) | v1.0.13, 2026-05-29 | ⌃⌥C | https://notchy.dev/changelog/#v1.0.13 , https://notchy.dev/help/keyboard-shortcuts/ |
| 명령 팔레트 단축키 | **변경**. 1.0.33은 ⌘K(전역 단축키 별도 지정 가능)였다. 현재 기본 전역 단축키는 ⌃⌥K이고 ⌘K는 열린 패널 안에서만 쓴다. 변경 시점 기록은 없다 | 미기재 | ⌃⌥K | https://notchy.dev/changelog/#v1.0.33 , https://notchy.dev/help/keyboard-shortcuts/ |
| Liquid Glass 모양 선택지 | **축소**. 20가지(1.0.51) → 6가지(1.0.118) | v1.0.118, 2026-08-17 | 6가지 모양 | https://notchy.dev/changelog/#v1.0.118 |
| AI Usage 집계 방식 | **변경**. 1.0.31은 CLI 로컬 로그만 읽었고(키·네트워크 없음) 1.0.32에서 원격 공급자를 추가했다. 1.0.78부터 상단 합계는 로컬 로그 스캔 대신 사용량 엔진에서 가져온다 | v1.0.32, v1.0.78 | 해당 없음 | https://notchy.dev/changelog/#v1.0.78 |
| 첫 실행 권한 요청 | **변경**. 1.0.137부터 첫 실행 때는 Accessibility만 요청하고 나머지는 기능을 켤 때 요청한다. 1.0.180부터 새 설치는 부가 기능이 모두 꺼진 상태로 시작한다 | v1.0.137, v1.0.180 | 해당 없음 | https://notchy.dev/changelog/#v1.0.137 , https://notchy.dev/help/features-off-after-install/ |
| 인라인 답장 지원 앱의 배너 처리 | **변경**. 1.0.140은 "Notchy Only"에서 Teams·Outlook·Slack 같은 앱 알림에 답장 칸 대신 Open을 보여 줬다. 1.0.219부터 Teams·WhatsApp·Slack 등에 노치에서 보낸 답장이 실제로 전송된다 | v1.0.140 → v1.0.219, 2026-10-17 | 노치 인라인 답장 | https://notchy.dev/changelog/#v1.0.140 , https://notchy.dev/changelog/#v1.0.219 |
| Face Unlock 설정 위치 | **이동**. 도움말(2026-10-10~11 갱신)은 Settings → Lock Screen이라고 하지만, 1.0.210부터 Face Unlock은 전용 설정 페이지를 가진다. 설정 참조 페이지에도 "Face Unlock" 묶음이 따로 있다 | v1.0.210, 2026-10-14 | Settings → Face Unlock | https://notchy.dev/changelog/#v1.0.210 , https://notchy.dev/help/set-up-face-unlock/ |
| Weather 설정 위치 | **이동**. 도움말은 Settings → Weather를 가리키지만 1.0.210은 Weather가 Home 아래로 갔다고 적는다 | v1.0.210, 2026-10-14 | Home 설정 | https://notchy.dev/changelog/#v1.0.210 , https://notchy.dev/help/weather-without-location/ |
| Face Unlock 활성 검사 방식 | **변경(충돌 있음)**. 1.0.207은 회전·깜빡임 지시를 없애고 수동적 생체 신호로 바꿨다. 1.0.221은 깜빡임이나 고개 돌리기를 요청하고 5회 실패 시 잠시 멈춘다고 적는다. 도움말(10-11 갱신)은 1.0.207 기준이다. 최신 변경 기록(1.0.221)을 우선한다 | v1.0.207 → v1.0.221, 2026-10-18 | 해당 없음 | https://notchy.dev/changelog/#v1.0.207 , https://notchy.dev/changelog/#v1.0.221 , https://notchy.dev/help/is-face-unlock-secure/ |
| 익명 분석 끄기 | **충돌**. 1.0.173은 About → Privacy에서 익명 분석을 끄고 식별자를 초기화할 수 있다고 한다. 도움말 "무엇을 보내나"(10-10 갱신)는 하루 1회 가명 핑을 끌 수 없다고 한다. 두 항목이 서로 다른 데이터일 수 있으나 공식 문서는 구분하지 않는다. 최신 도움말 기준으로 일일 핑은 끌 수 없다고 본다 | v1.0.173 / 도움말 2026-10-10 | 해당 없음 | https://notchy.dev/changelog/#v1.0.173 , https://notchy.dev/help/what-notchy-sends/ |
| Beta 업데이트 채널 | **현행 여부 미확정**. 1.0.55에서 About → Updates에 추가되었다. 현재 업데이트 도움말과 설정 참조 페이지 About → Updates에는 베타 항목이 없고, 홈페이지만 "optional beta channel"을 언급한다 | 추가 v1.0.55, 2026-07-21 | 해당 없음 | https://notchy.dev/changelog/#v1.0.55 , https://notchy.dev/help/update-notchy/ |
| Spotify 연결 요건 | **변경**. 1.0.55는 본인 무료 앱 키를 쓴다고 했지만 현재 도움말은 Spotify 개발 모드 정책 때문에 앱 소유자에게 Premium이 필요하다고 적는다 | 도움말 2026-10-11 | 해당 없음 | https://notchy.dev/changelog/#v1.0.55 , https://notchy.dev/help/connect-spotify/ |

그 밖의 연동 폐기는 확인되지 않았다. Todoist, Spotify, YouTube Music, LRCLIB·NetEase 가사, Open-Meteo, Yahoo Finance, Google 번역은 현재 도움말이나 최근 변경 기록에서 계속 쓰인다.

## 3. 버전별 기능 추가 요약 (최신순)

기능 추가가 없는 수정 릴리스는 "(수정만)"으로 표시한다.

- 2.0.3 (2026-11-01): 4가지 크기의 플로팅 음악 플레이어, 커버를 밀어 곡 넘기기, 단어 단위로 빛나는 가사, Apple Music 움직이는 앨범 아트, 활동이 액체처럼 갈라지고 합쳐지는 애니메이션과 2단계 열림·닫힘, 파일을 끌며 흔들면 그 자리에서 셸프 열기, Window Watch(창 일부를 지켜보다 바뀌면 알림), 런처 휠의 Action Ring, 앱 볼륨 150%, 날씨 카드 Sky Background, 클립보드 색 견본·필터, 캘린더 빠른 추가·카운트다운, 완료 체크 진행 링, Zoom 음소거 동기화
- 2.0.2 (2026-10-30): 닫힌 노치 옆 읽지 않은 알림 배지(클릭하면 열림), 설정 툴바 뒤로/앞으로(⌘[ ⌘], 마우스 측면 버튼), Settings › About의 피드백 보내기(스크린샷·화면 녹화 첨부, 메일 계정 불필요), 연결·해제 알림을 끄면 근처 AirPods 블루투스 스캔 중단
- 2.0.1 (2026-10-28): 자리 비움·배터리 사용 시 데스크톱 펫 절전, 노치 음악 막대 저전력, 한눈에 읽는 AI Usage 토큰 차트, Files 셸프의 Finder식 선택(클릭·⌘·⇧·⌘A·Esc), 잠금 화면 AirPods 배터리·충전 표시
- 2.0.0 (2026-10-26): 유료 전환(7일 무료 체험, 1회 구매, Settings › License에 남은 일수), 후원자 무료 라이선스, Ask About the Screen(화면 일부를 골라 텍스트 복사·링크와 날짜 열기·검색·번역·질문), World Clock·Calendar·Batteries 데스크톱 위젯(3가지 크기), XDR 디스플레이용 Extra Brightness, Home에서 블루투스 기기 원클릭 연결
- 1.0.226 (2026-10-22): 잠금 화면 위젯이 패널 재질을 따르고 Clear 유리 선택, Quick Settings 스위치 선택·순서 변경, Safari·Chrome·사진·Mail에서 끈 이미지를 셸프로 받기, 구형 Mac용 Face Unlock Only 모드, Repeat Timer, 유휴 시 포인터 숨기기, 날씨 카드 최고·최저·자외선, Ports 창 개편, Clean Keyboard 길게 눌러 Clean Screen
- 1.0.225 (2026-10-21): 헤더 버튼 최대 6개와 More 메뉴, Notchy 언어 기준 날짜·시간, 아랍어 등 RTL 레이아웃 미러링, Hide Notch 사용 시 Space별 배경화면 유지, AI Usage 공급자 확대, 자체 키로 서명된 업데이트만 수락
- 1.0.224 (2026-10-21): 지우는 동작 전 확인(클립보드 한도 축소, 설정 가져오기, 스냅 영역 초기화, API 토큰 재발급), Full Keyboard Access·VoiceOver 지원 확대, 화면에 필요 없을 때 밝기·가사·AI 사용량·통화·미디어 검사 일시 중지, 잠금 화면 일정·미리알림 카드는 기본으로 시간만 표시, 알림 사본 암호화 저장, 데스크톱 위젯(Clock·Now Playing·Weather·System·Photo), Clean Screen, 서드파티 블루투스 키보드·마우스·이어버드 배터리
- 1.0.223 (2026-10-19): Open Music이 고른 플레이어 실행, 헤드폰 연결 시 Music 자동 실행 차단, 시·분·초 사용자 타이머, 실행 중 타이머 hover 컨트롤, 잠금 화면 타이머 카드의 스톱워치, 탭 이름 표시 선택, Minimal Layout 버튼 확대·Minimal Layout Scale, Support 버튼 숨기기, Show Unlock Animation, 업데이트 설치 실패 시 기존 앱 복원
- 1.0.222 (2026-10-19): 요청으로 설정 5개 복귀, 설정 섹션 기본 펼침, 패널 그림자, 브라우저별 "Allow JavaScript from Apple Events" 끄기 버튼, 백업 복원 시 Face Unlock·링크 자동화 스위치는 Mac별 유지, 복사한 API 토큰을 클립보드 기록에서 제외
- 1.0.221 (2026-10-18): 넘치는 헤더 버튼만 More로 접기, 잠금 화면 컨트롤이 암호 입력을 방해하지 않음, Full Keyboard Access 확대, Face Unlock 깜빡임·고개 돌리기 요청과 5회 실패 시 일시 정지, System Stats 팬 스위치·Open Fan Settings 버튼
- 1.0.220 (2026-10-17): 설정 약 80개 삭제·통합과 Tools 섹션, 재실행 후에도 타이머·스톱워치 유지, 명령 팔레트 자연어 입력(타이머·메모·작업·미리알림), Ask AI Retry·Edit Question, Notes·Ask AI 별도 창, 번역이 Google로 간다는 고지, 클립보드 캡처 일시 정지, 덮개 닫고 깨어 있기가 회사·학교 계정에서도 암호 요청
- 1.0.219 (2026-10-17): macOS 26 노치 MacBook 잠금 화면 알약 위치, Teams·WhatsApp·Slack 등 노치 답장 실제 전송, 배너 옆으로 밀어 닫기, AI Usage OpenCode 탭(로컬 기록 기반 토큰·비용·세션·주 모델), "Same as Panel" 알약 색, Packages 업데이트 진행률, Caffeine 켜짐·꺼짐 아일랜드
- 1.0.218 (2026-10-16): 잠금 화면 확대 보정으로 알약을 카메라 바로 아래에, 모든 데스크톱에 알약 유지, Minimal Layout 헤더 버튼 선택, 실행 중 타이머를 카메라 옆에, 시스템 설정에서 메뉴 막대 항목이 꺼졌을 때 안내
- 1.0.217 (2026-10-16): 잠금 후 알약 크기·위치 안정, Cuely 읽기 띠 크기 조절, 패널 헤더 Update 버튼(설치 후 재실행), Join Meeting이 곧 시작할 회의 우선
- 1.0.216 (2026-10-16): 잠금 후 알약을 카메라 아래 유지, 실행 시 블루투스 대기 제거로 빠른 시작
- 1.0.215 (2026-10-16): (수정만) 소리·앱별 볼륨·창 스냅·색 그리기 크래시, 설정 동시 읽기·쓰기 안정화
- 1.0.214 (2026-10-15): Cuely 수동 스크롤(휠·트랙패드), 메시지 알림 쌓기(각각 Reply·Open·Dismiss), 설정 페이지 기본 표시, 잠금 화면 정렬 자동화
- 1.0.213 (2026-10-15): (수정만) 수동 잠금 후 알약 위치, 메뉴 막대 캘린더 정리
- 1.0.212 (2026-10-15): (수정만) 잠금 알약·Face Unlock 위치, 1.0.211의 전체 화면 잠금 해제 화면 문제
- 1.0.211 (2026-10-15): 메뉴 막대 다음 회의 클릭 시 월 캘린더(일정·Join·New Event), 알림·마이크 음소거·외부 디스플레이 밝기가 노치를 막지 않음, 에이전트 승인 "Always"를 비슷한 명령으로 한정·명령의 숨은 문자 표시, Todoist 마감 시각 수정
- 1.0.210 (2026-10-14): Screenshots·Typing Sounds·Face Unlock·Developer 전용 설정 페이지, Weather를 Home 아래로, 노치 없는 Mac에서 알약이 앱 메뉴를 피함, 다중 디스플레이에서 지금 쓰는 화면에만 열기, 승인 아일랜드에 명령 전체 표시, 주가 현지 통화
- 1.0.209 (2026-10-14): Face Unlock 카메라 중단 복구, 새 macOS 통화 인식, 잠금·깨우기 후 위치 유지, 알림 전달 스위치 축소
- 1.0.208 (2026-10-13): Focus가 허용한 알림 즉시 표시·hover 확장·해제 취소, Face Unlock 빠른 시작·재스캔 안내, 미리알림 완료·스니펫 삭제 취소, 설정 초기화 시 메모·설정 진행 유지, iCloud 최신 편집 우선 (1.0.173 메모에 따르면 이 버전에서 Google·Microsoft 직접 로그인과 To Do 폐기)
- 1.0.207 (2026-10-11): 바라보기만 하는 Face Unlock, 설정 과정 안정화(작은 고개 움직임·흐린 프레임 건너뛰기·어두운 방 화면 조명), My Setup·펫 옵션 정리, 트랙패드 스와이프 방향별 스위치, macOS 27 배너 대응
- 1.0.206 (2026-10-11): 개선된 Face Unlock 재스캔(암호는 키체인 유지, Touch ID 없는 Mac 처리), macOS 27 FaceTime·iPhone 통화 인식, Notifications-Only Mode, HUDs Beside the Notch
- 1.0.205 (2026-10-10): (수정 위주) Face Unlock 스캔 수용, 설정 페이지 즉시 전환, Supporter 섹션 접기
- 1.0.204 (2026-10-10): Face Unlock 설정 암호 확인 실패 처리, 중복 설치본을 휴지통으로 옮기기 제안, macOS 27에서 숨긴 아이콘 상태로 알림 센터 열기, 스크린샷 아일랜드 Copy 버튼
- 1.0.203 (2026-10-10): 연속 2회 크래시 시 안전 모드 시작과 업데이트 확인, macOS 27 Siri 아일랜드, Square Album Art 전체 적용, Live Transcript(받아쓰기 중 최근 단어 표시, 기본 꺼짐)
- 1.0.202 (2026-10-09): Ask AI 탭(본인 Anthropic API 키, 기본 꺼짐), Sound Mixer 탭 출력·마이크·입력 레벨·마이크 음소거, Codex 권한 아일랜드, Hide from Screen Capture 복귀, 예약 후원 팝업 제거
- 1.0.201 (2026-10-08): Desktop Lyrics, 번역 포함 2번째 가사 공급자, 비공개 청취 기록·북마크, 노치에서 일정 생성·편집과 마감 작업 표시, 메뉴 막대 아이콘 항상 숨김·hover 표시, 탭을 노치 옆에·즐겨찾기 탭·Sound Mixer 탭, 발신 통화 컨트롤, 동작 프리셋, 네트워크 트래픽 기록, Ports 버튼, 심각한 버전 강제 업데이트 확인
- 1.0.200 (2026-10-07): Typing Sounds, 메뉴 막대 다음 회의, Calendar 열기 단축키, Square Album Art, 클립보드 Capture Sound
- 1.0.199 (2026-10-06): Announce New Tracks, Stop Title Scrolling, 펫 낚시·명절·성장·일일 퀘스트, 펫이 걷는 동안 AI 사용량 재스캔 중단
- 1.0.198 (2026-10-06): 펫 캐릭터 52종과 Pet Weather·Fur Colours·Pet Memories·Quick Paws, Text Actions(선택 텍스트 위 작은 막대로 복사·검색·조회·번역)
- 1.0.197 (2026-10-06): Show On의 External 옵션, 녹음 버전과 맞을 때만 가사 동기화, 펫 9종·게임·취침 등, 날씨 예보, AI 한도 알림
- 1.0.196 (2026-10-05): Hide Pill for Sharing(모든 디스플레이에서 숨김), 초기화·가져오기에도 Cuely 대본 유지, 종료 시 녹화 저장 대기, 잠금 화면 메시지 미리보기 차단
- 1.0.195 (2026-10-04): Focus Sounds, Color Tools, Saved Links, 자연어 미리알림 날짜, 반복 타이머 알람, 독립 셸프 사본, 셸프 자동 정리
- 1.0.194 (2026-10-03): Home 카드 제목에서 해당 섹션 열기, Launcher 재정렬·폴더 동작 개선
- 1.0.193 (2026-10-02): 호환되는 최신 릴리스를 찾는 업데이트 확인, Spotify 재생목록 체크 점진 갱신, 통화 컴팩트 표시
- 1.0.192 (2026-10-02): 오래된 Now Playing 세션 닫기·복원, Spotify Playlist Checkmarks, Center Pill Lyrics
- 1.0.191 (2026-10-01): My Setup, Pomodoro 빠른 접근, 받아쓰기 단축키, 디스플레이 간 반복 창 스냅
- 1.0.190 (2026-10-01): Outlook 일정 메모의 Teams 링크 정리, 작은 원형 아일랜드 컨트롤·크기·HUD 색 반전
- 1.0.189 (2026-09-30): 펫별 돌봄·레벨, 펫 카드 공유 메뉴, 데스크톱 변경 라벨, 기능 팁 기본 꺼짐
- 1.0.188 (2026-09-30): 더블클릭해야 열리는 옵션, 클립보드 최신순·목록 저장 항목 분리, iCloud 설정 동기화가 업로드 전 최신본 로드, Zoom Back to Meeting 버튼
- 1.0.187 (2026-09-29): Pet Room 카드, 펫 간식·빗질·묘기, 가져온 알림을 Notifications 탭에 보관, 통화 컨트롤 빠른 표시
- 1.0.186 (2026-09-29): 화면 QR 코드 스캔, 화면 녹화 저장 위치와 빨간 타이머, 동시 재생 앱 감지, Pomodoro Skip
- 1.0.185 (2026-09-28): 클립보드 항목 제목 붙이기, 긴 목록 멈춤 감소
- 1.0.184 (2026-09-28): Behavior·Displays 설정 페이지, 키보드 창 스냅과 디스플레이별 스냅 영역, Space 이동 단축키와 Space 표시 아일랜드
- 1.0.183 (2026-09-28): Home 카드 검색·분류·제거 취소, 최소 10pt 글자, 마지막 설정 페이지 다시 열기, 실패 뒤 암호 입력 시 Face Unlock이 새 외모 학습
- 1.0.182 (2026-09-27): System Info 플라이아웃 팬 제어(Automatic·Manual·Curve), 133개 언어 번역 개선
- 1.0.181 (2026-09-26): Home 카드 12종(Tasks, Desktop Pet, Screen Time, Apps, Sound, Device Batteries, Coding Agents, App Updates, Quick Actions, Brightness, Emoji, Calculator), Packages 탭 App Cleaner, iOS 27 스타일 Siri 파형
- 1.0.180 (2026-09-26): 새 설치는 부가 기능을 끈 채 시작, 포인터 스타일과 클릭 물결·후광·꼬리·⌃⌥ 스포트라이트
- 1.0.179 (2026-09-26): 회의 전체 화면 알림과 노치에서 참가, 종료 후에도 클립보드 기록 유지, 저장 항목 목록, 저장 텍스트 iCloud 동기화, 새 펫 4종
- 1.0.178 (2026-09-25): 데스크톱 픽셀 펫, 방사형 앱 런처 휠, 잔여 파일과 함께 앱 삭제, 서식 없이 붙여넣기, Screen Time 카드, Claude Code 연속 사용 기록
- 1.0.177 (2026-09-24): 전체 화면 앱 위 메뉴 막대 항목, 분리한 Timer의 메뉴 막대 남은 시간
- 1.0.176 (2026-09-24): (수정만) 아일랜드 소리 재생 시 멈춤
- 1.0.175 (2026-09-24): Quick Settings 크기 슬라이더 3종, 날씨 도시 자동 완성, 후원 요청을 헤더 하트로
- 1.0.174 (2026-09-24): Black Out Screen Corners, 저전력 모드 애니메이션 단축
- 1.0.173 (2026-09-24): Google Calendar·Outlook·iCalendar 링크·CalDAV 일정, Todoist·Microsoft To Do 작업과 Quick Add 저장 위치, 익명 분석 끄기·식별자 초기화, 설정 라벨 270개 번역 (Google·Microsoft 직접 로그인과 To Do는 1.0.208에서 폐기)
- 1.0.172 (2026-09-23): Tasks 탭, 클립보드가 1Password·Apple Passwords·지정 앱 무시, 링크 추적 매개변수 제거, 지연·잠자기·잠금 시 클립보드 비우기, 앱별 출력 장치, 메뉴 막대 아이콘 우클릭 옵션
- 1.0.171 (2026-09-16): Face Unlock 정확도 향상과 사진·화면 거부 주장, 잠금 화면에서 스페이스로 스캔, 알약·패널 사용자 색·그라데이션, 브라우저 로그인 AI 사용량을 Notchy가 직접 읽음
- 1.0.170 (2026-09-15): Spaces Home 카드·클릭·스와이프·단축키·이름, 월간 영수증
- 1.0.169 (2026-09-14): 충전 한도·Sailing Mode·자동 방전·100% 충전, iPhone·iPad 배터리, 배터리 기록·온도·배터리 소모 앱 경고, 분리·완충 알림, 메뉴 막대 배터리
- 1.0.168 (2026-09-14): (수정만) Face Unlock 설정 크래시, 설정이 잠금 화면 위로 열리지 않음, 위젯 공간 활용
- 1.0.167 (2026-09-14): (수정만) 1.0.168과 같은 내용
- 1.0.166 (날짜 미표기): Face Unlock 첫 도입(잠긴 Mac을 바라보면 해제, 얼굴·암호는 Mac 밖으로 나가지 않음), Settings Guide, 카메라·마이크 사용 아일랜드 제거, 최대 12초 멈춤 수정
- 1.0.165 (2026-09-13): Invisible Until Hover, 일정 카운트다운 칩, 명령 팔레트에서 키보드 청소 잠금
- 1.0.164 (2026-09-12): 노치 안 Clean Keyboard(60초 입력 차단), 메뉴와 겹칠 때 유휴 노치 숨김 선택, 앱 알림 제어를 Notifications로 모음
- 1.0.163 (2026-09-12): (수정만) 오디오·시스템 상태 변화 처리
- 1.0.162 (2026-09-10): (수정만) 음악 시작 시 멈춤
- 1.0.161 (2026-09-10): 크래시·멈춤 후 익명 보고서 전송 제안, Ask·Send Automatically·Never 선택
- 1.0.160 (2026-09-10): 헤더 볼륨 버튼, Teams·Slack·Outlook 알림을 끄면 메시지 아일랜드도 중지
- 1.0.159 (2026-09-10): Apple 연속 곡선 모서리, 메뉴 막대 아이콘 숨김 깜빡임 수정
- 1.0.158 (2026-09-10): Sound Mixer(앱별 볼륨·음소거·3밴드 EQ), Notchy가 처리 못 하는 볼륨·밝기 키는 macOS로 넘김
- 1.0.157 (2026-09-09): Menu Bar 카드 스크롤, 메뉴 막대가 숨긴 아이콘 개수 배지
- 1.0.156 (2026-09-07): Monochrome Glass, Monochrome Interface, 전체 화면 앱 위 볼륨·밝기·키보드 백라이트 아일랜드, 배터리 성능 표시 복구
- 1.0.155 (2026-09-07): (수정 위주) Now Playing 카드 크기 적응, 큰 글자 잘림
- 1.0.154 (2026-09-07): Now Playing 카드 긴 제목 스크롤
- 1.0.153 (2026-09-07): Quick Search에 동영상 링크를 붙여 파일로 저장, macOS 알림 배너 위치 변경, Features 갤러리 카드로 탭 켜기
- 1.0.152 (2026-09-06): 내용만큼만 넓은 Now Playing 알약, macOS 26 로그인 창을 피하는 잠금 화면 위젯, 알약 통화 음소거, 셸프 AirDrop
- 1.0.151 (2026-09-04): (수정만) Full Disk Access 부여 후 재시작 안내
- 1.0.150 (날짜 미표기): (수정만) 잠금 화면 위젯이 로그인 창을 피함
- 1.0.149 (2026-09-04): (수정만) 마이크 음소거 복구 문제와 장치별 레벨 기억
- 1.0.148 (2026-09-04): 잠금 화면 위젯 Single Strip 레이아웃, "Notchy Only" 배너 재확인, 권한 없는 설정은 켤 수 없고 바로 안내
- 1.0.147 (2026-09-04): (수정만) macOS 26 알림 미러링, Notchy Only 배너 제거 속도
- 1.0.146 (2026-09-04): 앱 전체 글꼴·글자 크기, 통화 End가 실제 종료, 미러 알림 중복 제거와 해당 메시지로 열기
- 1.0.145 (2026-09-04): (수정만) 업데이트 Install 첫 클릭, 잠금 화면 위젯과 시계 겹침, 번역 재시도
- 1.0.144 (날짜 미표기): Teams·Zoom·Webex·Slack 통화 음소거·카메라·End 동작, 통화 줄 재설계, 가사 타이밍 조절
- 1.0.143 (2026-09-03): (수정만) Teams·Outlook·Slack·Mail 배너 중복, 잠금 화면 카드 잘림
- 1.0.142 (2026-09-03): Quick Search 사용자 검색 엔진, 작동하지 않는 켜진 기능 경고, 탭 하단 단축키 표시, 미러링·화면 공유 중 노치 숨김
- 1.0.141 (2026-09-02): Quick Search(9개 엔진·접두어), Translate, Calculator 탭, 업데이트 설치 중 관리자 암호 창 유지
- 1.0.140 (날짜 미표기): (수정 위주) hover 시 Mac 전체 멈춤, Notchy Only가 인라인 답장 앱 배너도 닫음
- 1.0.139 (2026-09-02): AI 공급자 40여 곳 로고, Focus·Home 타일 아이콘, AI 탭 공급자 장애 표시, 프로젝트 이름·계정 메일 가리기
- 1.0.138 (2026-09-01): 통화 아일랜드 마이크·카메라·끊기, 더 많은 앱·언어의 통화·메시지 인식, Notification Delivery 설정
- 1.0.137 (2026-09-01): 블루투스 광고 수신 최소화, 첫 실행 Accessibility만 요청, 34개 기능 갤러리, Teams·Zoom 음소거, 페이지별 기본값 복원
- 1.0.136 (2026-08-31): 패널 사전 준비로 즉시 열림, Minimalistic UI, 음악 표시가 앱 메뉴를 피함
- 1.0.135 (2026-08-30): Animation Speed 전체 적용, 헤더 잘림 방지, 잠금 화면 카드 열 배치
- 1.0.134 (2026-08-27): 유리 재질이 패널과 함께 커짐, 야간 배터리 절감, 에이전트 상시 허용 1탭 철회, Wi-Fi 암호 다시 가리기
- 1.0.133 (2026-08-26): (수정 위주) hover 시 패널 미리 준비
- 1.0.132 (2026-08-25): Home Quick Note 카드(백업·iCloud 포함), 노치 유무와 무관한 통화 모양
- 1.0.131 (2026-08-25): Home 카드 Small·Wide·Tall·Large, 큰 Calendar 카드 기본, 내장·까다로운 디스플레이 소프트웨어 디밍
- 1.0.130 (2026-08-25): 터미널 단축키·우클릭 메뉴, 셸프 PDF 병합, Home Calendar 카드, DDC 미응답 모니터 소프트웨어 디밍
- 1.0.129 (2026-08-25): iCloud 설정 동기화, Focus 목록 복구, 두 손가락 스와이프, 스냅 영역 줄 배치
- 1.0.128 (2026-08-24): 노치 MacBook 수신 통화 위치, 업데이트 실패 단계·오류 코드 익명 보고
- 1.0.127 (2026-08-21): (수정만) 선택 탭 강조 모양
- 1.0.126 (2026-08-21): 모든 앱 알림 노치 아일랜드, Teams·Outlook·Slack 인라인 답장, Unread 카드, 앱별 음소거
- 1.0.124 (2026-08-20): 닫힌 알약 시계 설정, 화면 영역 녹화, 디스플레이별 스냅 영역, 외부 모니터 자체 밝기 표시, 종일 일정 표시
- 1.0.123 (2026-08-20): macOS 26 유리 테두리, 심볼 애니메이션, 헤더 Camera 버튼과 Camera Guard, 숫자 굴림 애니메이션
- 1.0.122 (2026-08-19): 설정 항목 단위 검색, 닫힌 알약 시계 기본 꺼짐, 2초 주기 통화 검사 제거
- 1.0.121 (2026-08-19): 피드백 게시판 요청 16건(노치 시계, Focus 전환, 화면 녹화, HomeKit 탭, Calendar 탭, 런처 폴더, 디스크 공간, 기본 탭, 탭별 패널 크기 등), 단축키 충돌 수정, 잠금 화면 전체 가사 기본 켬, Menu Bar 카드
- 1.0.120 (2026-08-18): 통화가 노치 양옆에 표시, Hide When Paused
- 1.0.119 (2026-08-18): (수정 위주) Home 카드 잘림, 버튼 반응, 다단어 설정 검색
- 1.0.118 (2026-08-17): macOS 13·14 실행 크래시 수정, YouTube Music 컴패니언 서버 연동, 자 모양 타이머 다이얼, Liquid Glass 6가지 모양
- 1.0.117 (2026-08-15): (수정만) 유휴 CPU, Claude Code 턴 비용 약 1.8배 과대 계산
- 1.0.116 (2026-08-15): 진행 중 회의·하루 타임라인, 노치 한 줄 가사, 패널 높이 슬라이더·Compact
- 1.0.115 (2026-08-14): (수정만) 음악 재생 CPU 대폭 감소
- 1.0.114 (2026-08-14): 셸프 상자 드래그 선택, 플릭 제스처, Ventura 아이콘 복구
- 1.0.113 (2026-08-14): Stocks 전용 탭과 차트 개선
- 1.0.112 (2026-08-14): Stocks 관심 목록·가격 알림, Teams·Zoom·WhatsApp·FaceTime 통화 아일랜드, 에이전트 승인·AI Usage 기본 켬
- 1.0.111 (2026-08-12): AI 지출 예측·프로젝트별·모델별, Knock 보정, 전화번호·JSON·계산식 클립보드 동작, Cuely Markdown
- 1.0.110 (2026-08-12): 주간 한도 표시, Lock Screen 설정 페이지
- 1.0.109 (2026-08-12): 에너지 기준 Top Processes, Devices 카드, World Clock 카드, 휴식 알림, 덮개 닫고 깨어 있기, ⌘K에서 포트 비우기
- 1.0.108 (2026-08-11): (수정 위주) 카메라·미리알림 권한 대화상자, "Ask me again"
- 1.0.107 (2026-08-11): (수정 위주) 권한 부여 후 패널 무반응, 터미널 탭 바로 입력
- 1.0.106 (2026-08-11): (수정만) 파일 드롭 후 패널 닫힘
- 1.0.105 (2026-08-11): (수정만) Sonoma 권한 프롬프트
- 1.0.104 (2026-08-11): (수정만) 파일 드래그 중 열림 유지
- 1.0.103 (2026-08-11): 권한 프롬프트가 안 뜰 때 이유 안내와 재실행
- 1.0.102 (2026-08-10): (수정만) 구형 Mac 권한 프롬프트
- 1.0.101 (2026-08-10): (수정만) 채팅 영상 종료 후 음악 아일랜드
- 1.0.100 (2026-08-10): 패널 너비 설정, 브라우저 동영상 재생 속도, AI 공급자 표시·순서 선택
- 1.0.99 (2026-08-10): 실제 오디오 반응 막대 기본 켬, 팟캐스트·오디오북 ±15초·1~2배속, 잠금 화면 전체 가사
- 1.0.98 (2026-08-10): Intel Mac 지원(유니버설 빌드), 셔플·반복, 패널 접힘 대기 시간
- 1.0.97 (2026-08-09): (수정 위주) 음악 아일랜드 색, 후원처 단일화
- 1.0.96 (2026-08-09): AI 위젯 새로고침과 모든 계정 표시, XL 위젯, AI 사용량 기본 켬
- 1.0.95 (2026-08-09): 권한 설정 자동 진행·재시작 후 이어서 진행, GitHub PR glance 제거
- 1.0.94 (2026-08-08): 노치 별점 평가, 낮은 평점 시 후원 요청 중단
- 1.0.93 (2026-08-07): 내용 크기에 맞는 아일랜드, 잠금 표시를 카메라 옆에, 잠금 화면 플레이어에서 가사 열기, Siri 아일랜드·단축키
- 1.0.92 (2026-08-07): 노치 Mac에서 Song ID 등 활동을 카메라 양옆에, Home 카드 5종(Reminders, Shortcuts, Shelf, AI Usage, Focus)
- 1.0.91 (2026-08-06): Home 카드 4종(Battery, System, Timer, Clipboard), 카드 공간 적응
- 1.0.90 (2026-08-06): Home 레이아웃 편집기·열 수 선택
- 1.0.89 (2026-08-06): Home 카드 선택·순서, Daily Activity 카드, 순수 검정 알약
- 1.0.88 (2026-08-06): 노치 주변 클릭 통과, 실제 오디오 반응 막대
- 1.0.87 (2026-08-06): (수정 위주) 단일 표면 열림, Virtual Notch 크기
- 1.0.86 (2026-08-05): 공통 스프링 모션, Activity 링 정리, 터미널 알림 배지
- 1.0.85 (2026-08-04): 노치 Mac 중앙 확장, 전체 화면 상단 머무름 필요, 활동을 닫힌 알약에서 빼는 옵션
- 1.0.84 (2026-08-04): (수정 위주) 열림 프레임레이트, Peek on Hover 크기
- 1.0.83 (2026-08-04): 2개 객체 아일랜드, 아트워크·이퀄라이저 양옆 배치와 진행 링, Peek on Hover 기본 켬
- 1.0.82 (2026-08-04): Activity Rings, Milestones, Island Sounds, Expanded Island 활동 목록
- 1.0.81 (2026-08-03): Dynamic Island 칩, 닫힌 상태 음악 표시, 중앙에서 열림·자동 닫힘, 시계식 타이머
- 1.0.80 (2026-08-03): 에이전트 승인·거부 아일랜드 복구, 터미널 응답 시 프롬프트 해제, 훅 오류 출력 제거, 메뉴 막대 팝오버 자동 닫힘, 위젯 진입점 수정
- 1.0.79 (2026-08-02): 데스크톱·알림 센터 위젯(AI Usage·Activity·Timer), AI 사용량 참조 엔진 일치, Cursor·Antigravity·Copilot 실시간 한도, 공급자 다중 계정, 터미널 제목 표시줄
- 1.0.78 (2026-07-29): 독립 표면 시스템 유리, 엔진 기반 AI 합계, .lottie 지원, 실제로 막혔을 때만 에이전트 알림
- 1.0.77 (2026-07-27): 실행 시간 약 40% 단축, hover 플레이어 재구성, Lottie 정지 수정
- 1.0.76 (2026-07-27): 여러 라이브 활동 나란히 표시, 첫 실행 권한 대화상자 수정, Cuely 음성 모드 중지
- 1.0.75 (2026-07-24): (수정 위주) 패널 클릭 신뢰성, Lottie 캐시
- 1.0.74 (2026-07-23): (수정만) 코드 정리
- 1.0.73 (날짜 미표기): (수정 위주) 패널 기본 높이 316px, 헤더 렌더링
- 1.0.72 (2026-07-22): Antigravity 다중 계정, AI 도구 호출 칩, 한도 심각도 게이지
- 1.0.71 (2026-07-22): (수정만) 콘텐츠 너비 고정
- 1.0.70 (2026-07-22): (수정만) hover 반응 180ms → 60ms
- 1.0.69 (2026-07-22): (수정만) 버튼 hover 그림자
- 1.0.68 (2026-07-22): (수정만) 카메라 카드 그림자
- 1.0.67 (2026-07-22): (수정만) 카메라 카드 크기
- 1.0.66 (2026-07-22): (수정만) 120fps 열림, 카메라 미리보기 경계
- 1.0.65 (2026-07-22): 터미널 활동에서 개발 서버 제외, 5분 자동 소멸
- 1.0.64 (2026-07-22): 닫힌 음악 알약에서 제목 숨김, peek 막대 확장, 잠금 화면 카드 잘림 수정
- 1.0.63 (2026-07-22): Now Playing hover peek, 잠금 화면 위젯 위치
- 1.0.62 (2026-07-22): 아트·오디오 막대 기본 표시, peek 막대 클릭 확장
- 1.0.61 (2026-07-22): AI Usage 대시보드(게이지 링·리셋 카운트다운·키체인·60개 이상 공급자), 일·주·월 사용량 차트, 통합 모션, 6개 범주 설정
- 1.0.60 (2026-07-22): Peek on Hover(재생 중 hover 시 미니 플레이어)
- 1.0.59 (2026-07-22): Calendar Join 수정, 잠금 화면 위젯 암호 칸 회피, 알림 탭 시 앱 열기, idle 애니메이션 가로 오프셋, Feature discovery
- 1.0.58 (2026-07-21): (수정만) FaceTime 감지 비동기화
- 1.0.57 (2026-07-21): AI 에이전트 활동(Claude Code 권한·질문 아일랜드, 승인·거부, 터미널로 이동, 턴 비용, opt-in 훅 설치), 긴 명령 아일랜드(zsh, opt-in), Replace System HUD의 Input Monitoring 안내, DDC 밝기 수정
- 1.0.56 (2026-07-21): (수정만) 익명 활성 설치 집계
- 1.0.55 (2026-07-21): Minimalist Now Playing, Spotify Liked Songs, 터미널 색 구성표, 다운로드 진행, 날씨 체감·습도·대기질·일출일몰, DDC/CI 외부 모니터 밝기, Beta 업데이트 채널, 노치 Mac 밝기 아일랜드
- 1.0.54 (2026-07-20): (수정만) 잠금 화면 음악 진행 막대 드래그
- 1.0.53 (2026-07-20): (수정만) 터미널, 잠금 화면 음악 컨트롤, Top Processes, What's New
- 1.0.52 (2026-07-20): 노치 Mac Caps Lock·잠금 HUD, AI Usage 키체인 프롬프트는 Refresh 때만
- 1.0.51 (2026-07-20): Terminal 탭, 잠금 화면 위젯, GPU·CPU 온도·Top Processes, 카메라·마이크 사용 표시, 새 HUD 스타일·Caps Lock HUD·완충 알림, Liquid Glass 20가지, 사용자 Lottie idle 애니메이션, FFT 오디오 시각화
- 1.0.50 (2026-07-19): 우클릭 메뉴 수정, AI 엔진 갱신(ai&, DeepInfra), 마일스톤 감사와 후원
- 1.0.49 (2026-07-19): App Launcher 탭, OCR 포함 클립보드 검색, GitHub 토큰 입력란 정리
- 1.0.48 (2026-07-18): (수정만) AI 한도 알림 반복
- 1.0.47 (2026-07-18): 실시간 Claude·Codex 게이지 유지, 첫 조회 5분 캐시, 신선도 표시
- 1.0.46 (2026-07-18): CLI 로그인으로 Claude·Codex 실제 한도 조회(키 불필요)
- 1.0.45 (2026-07-18): 노치로 끌어 창 스냅, Snippets, 이미지 텍스트 복사, ⌘K 스크린샷·스포이드·시스템 마이크 음소거, 키보드 청소 잠금, 키 입력 HUD, 메뉴 막대 아이콘 숨김, GitHub PR 추적, AI Usage 페이스 예측·공급자 7곳
- 1.0.44 (2026-07-17): iPhone식 FaceTime 수신 버튼·셀프 미리보기, 미러 시 네이티브 배너 닫기
- 1.0.43 (2026-07-17): 시스템 통계 게이지, 배터리 성능·사이클, 탭 우클릭으로 메뉴 막대에 보내기, 저전력 모드 절전
- 1.0.42 (2026-07-15): Liquid Touch 토글, 노치 안 설정 정리
- 1.0.41 (2026-07-14): macOS 26 네이티브 Liquid Glass 패널
- 1.0.40 (2026-07-12): Apple 디자인 정리, 다중 디스플레이 통화 감지
- 1.0.39 (2026-07-07): 업데이트 확인 결과 아일랜드, About에서 바로 설치, 미디어 헬퍼 누수 정리
- 1.0.38 (2026-07-07): 통화·메시지 아일랜드 정식 공개(FaceTime 응답, iMessage 인라인 답장 등), Knock 설정 페이지와 동작 7종, 전체 화면 상단 터치로 열기, Tabs 페이지, 시스템 색 선택기
- 1.0.37 (2026-07-06): 섀시 노크(가속도계), 앱별 노크 프로필, 노치 안 빠른 동작
- 1.0.36 (2026-07-05): Codex 5시간·주간 창, 개별 한도 알림, 공급자 추가(Claude API, Doubao 등), 새 권한만 업데이트 시 요청
- 1.0.34 (2026-07-03): Knock(수정자 키 두 번), 패널 크기 조절, 기능 팁 아일랜드
- 1.0.33 (2026-07-01): 명령 팔레트, ⌘1–9 탭 이동, 탭을 메뉴 막대 팝오버로 분리, Caffeine 메뉴 막대, AI 한도 알림, Features 갤러리
- 1.0.32 (2026-06-30): 원격 공급자 사용량(API 키·토큰), 키체인 저장, 탭 메뉴 막대 분리
- 1.0.31 (2026-06-19): AI Usage 탭(Claude Code·Codex 로컬 로그, 기본 꺼짐), 타이머 Reset, 충전·잠금 아일랜드 숨김
- 1.0.30 (2026-06-18): 클립보드 스마트 동작, Pomodoro 통계, 가사 탭 탐색
- 1.0.29 (2026-06-17): 셸프 이미지 압축·크기 조절·일괄 변환, Quick Look, Apple Music식 Now Playing
- 1.0.28 (2026-06-12): 배터리 플라이아웃, 키보드 백라이트 HUD, Apple Music 좋아요, 앱 볼륨
- 1.0.27 (2026-06-12): macOS 26 HUD 대체, 133개 언어, Pomodoro 연결·사용자 시간, 잠금·해제 소리, 클래식 블루투스 배터리
- 1.0.26 (2026-06-11): Shortcuts 탭, 다운로드·드라이브·저배터리·스크린샷 아일랜드, Replace System HUD, 클립보드 고정, 셸프 압축·해제
- 1.0.25 (2026-06-09): 설정에서 타이머·Pomodoro 시작
- 1.0.24 (2026-06-09): Now Playing 탭과 노래방식 가사, Reminders 탭·스톱워치, GIF 변환, 출력 전환, 영상 통화 Join
- 1.0.23 (2026-06-08): 133개 언어, AirDrop 개선
- 1.0.22 (2026-06-07): Liquid Glass UI, 9개 언어, 접근성, 설정 검색·전역 단축키
- 1.0.21 (2026-06-07): (수정만) 패키지 빌드 크래시
- 1.0.20 (2026-06-07): 133개 언어 1차 적용
- 1.0.19 (2026-06-05): (수정만) 접힌 알약 드래그 앤 드롭
- 1.0.18 (2026-06-02): 업데이트 아일랜드·자동 확인, 다중 파일 셸프
- 1.0.17 (2026-06-01): (수정만) Caffeine·잠금 화면 hover
- 1.0.16 (2026-05-31): 자동 업데이트 활성화
- 1.0.15 (2026-05-31): (수정만) 유지보수
- 1.0.14 (2026-05-29): (수정만) 유휴 CPU 약 0%로, 폴링을 이벤트 방식으로
- 1.0.13 (2026-05-29): 클립보드 단축키 ⌃⌥C(재지정 가능)
- 1.0.12 (2026-05-28): (수정만) 안정화
- 1.0.11 (2026-05-28): Cuely가 Hide from Screen Capture 준수
- 1.0.10 (2026-05-27): (수정만) Cuely 다듬기
- 1.0.9 (2026-05-27): Cuely 텔레프롬프터(화면 캡처에서 숨김, 대본 보관, 음성 스크롤 베타)
- 1.0.8 (2026-05-24): 클립보드 전역 단축키(⇧⌘V)·1–9 빠른 선택·자동 붙여넣기, Now Playing 어댑터 자동 재시작

## 4. 기술 제약과 규격

### 4.1 로컬 개발자 API

- 켜는 곳: Settings → About → Developer → "Local API". 기본은 꺼짐이고 이 Mac에서만 수신한다. (https://notchy.dev/help/local-api/) 1.0.210에서 Developer가 별도 설정 페이지가 되었다고 하므로 실제 위치는 Developer 페이지일 수 있다. 설정 참조 페이지 About 묶음에는 Developer 항목이 보이지 않는다. (https://notchy.dev/changelog/#v1.0.210)
- 전송: 루프백 TCP `127.0.0.1:9999`. HTTP가 아니다. (help/local-api)
- 메시지 형식: 줄바꿈으로 끝나는 JSON 한 줄. 도움말 예시는 `{"command":"status","token":"…"}`를 `nc 127.0.0.1 9999`로 보내는 형태다. (help/local-api)
- 인증: 요청마다 JSON 안에 `token` 값을 넣는다. 홈페이지는 이를 설치마다 다른 토큰이라고 설명하고 "token-signed JSON"이라는 표현을 쓰지만, 서명(HMAC 등) 방식은 어디에도 설명되지 않는다. 도움말 기준으로는 평문 토큰 필드다. "Regenerate Token"은 이전 토큰을 즉시 무효로 만든다. 1.0.224부터 재발급 전에 확인을 묻고, 1.0.222부터 복사한 API 토큰은 클립보드 기록에 남지 않는다. (help/local-api, https://notchy.dev/changelog/#v1.0.224 , https://notchy.dev/changelog/#v1.0.222)
- 토큰 보관 위치: 자료 없음. 설정 화면에서 보고 복사한다는 점만 확인된다.
- 명령 목록: 공개 문서에 이름이 나온 명령은 `status` 하나다. `command` 없이 보낸 메시지는 제목·부제·선택적 진행률 값으로 아일랜드를 띄운다. 홈페이지는 스크립트·CI·메뉴 막대 도구가 라이브 활동과 알림 아일랜드를 그릴 수 있다고 설명한다. 전체 명령·응답 형식은 자료 없음.
- 단축어·딥링크: Local API와 별개인 "Show in Notchy" 기능을 Settings → General → Automation에서 켜야 한다. 단축어 앱 동작이나 `notchy://show?title=Hello&message=Ready` 링크로 메시지를 띄운다. 제목 최대 120자, 메시지 최대 500자, 표시 시간 1~10초이며 명령 실행이나 파일 열기는 할 수 없다. 이 경로에 토큰이 필요한지는 자료 없음. (help/local-api)
- 도입 시점: 변경 기록에 Local API 도입 항목이 없다.

### 4.2 Face Unlock

- 방식: 내장 카메라(노트북을 덮은 클램셸 상태에서는 USB 웹캠)로 얼굴을 맞춰 본 뒤, 저장해 둔 Mac 로그인 암호를 Accessibility 권한으로 잠금 화면에 입력한다. 덮개를 닫으면 내장 카메라는 쓸 수 없다. (https://notchy.dev/help/set-up-face-unlock/ , https://notchy.dev/help/face-unlock-not-working/)
- 암호 저장: 설정 시 카메라가 켜지기 전에 로그인 암호를 입력하고, macOS로 검증한 뒤 키체인에 저장한다. 얼굴 데이터와 암호는 키체인에만 있고 디스크나 온라인에 저장하지 않으며 인식은 기기 안에서 한다. Touch ID 보호 저장소를 쓰는 Mac은 Notchy 재시작 뒤나 세션 만료 때(기본 7일, "Re-authorize Every" 1~30일) Touch ID로 다시 승인해야 한다. Touch ID를 쓸 수 없는 Mac은 일반 키체인에 저장하고 이 단계가 없다. (help/set-up-face-unlock, https://notchy.dev/help/is-face-unlock-secure/ , help/face-unlock-not-working)
- opt-in: 새 설치는 부가 기능이 모두 꺼져 있고 Face Unlock은 사용자가 직접 설정한다. 도움말은 Settings → Lock Screen → "Set Up Face Unlock"을 안내하지만 1.0.210 이후 전용 페이지로 옮겨졌다(2장 참고). (https://notchy.dev/help/features-off-after-install/)
- 사용: ⌃⌘Q로 잠그고 키를 누른 뒤 Mac을 바라본다. 잠금 화면에서 스페이스로 다시 스캔할 수 있고(1.0.171), 화면이 깨어날 때 스캔하는 "Scan on Wake", "Detection Distance", "Match Strictness", 어두운 방용 화면 조명 옵션이 있다. (help/face-unlock-not-working, https://notchy.dev/changelog/#v1.0.171)
- 풀 수 있는 것과 없는 것:
  - 재시동 직후: 암호를 한 번 입력해야 하고 다음 잠금부터 동작한다. macOS가 재시동마다 암호를 요구한다고 명시한다. (help/face-unlock-not-working, help/is-face-unlock-secure)
  - FileVault 사전 부팅 화면: 자료 없음. 재시동 후 첫 입력이 암호여야 한다는 문구만 있다.
  - 로그아웃 상태의 로그인 창과 세션 잠금 구분: 자료 없음. 문서는 세션 잠금(⌃⌘Q, Touch ID 잠금, 깨우기) 상황만 다룬다.
  - Mac 암호를 바꾸면 Face Unlock을 지우고 다시 설정해야 한다. (help/face-unlock-not-working)
- 보안 경고: 보안 기능이 아니라 편의 기능이라고 명시한다. 웹캠은 Face ID 적외선처럼 깊이를 재지 못하므로 충분히 좋은 사진이나 영상으로 풀릴 수 있다. 1.0.207부터 여러 프레임 일치와 수동적 생체 신호(자연스러운 깜빡임 등)를 요구하지만 재생 영상은 여전히 통과할 수 있다. 민감한 용도에는 암호와 Touch ID를 권한다. (help/is-face-unlock-secure, help/set-up-face-unlock)
- 충돌: 1.0.171은 사진과 화면을 거부한다고 적었지만 도움말(10-11)은 사진·영상으로 풀릴 수 있다고 경고한다. 더 최신이고 보수적인 도움말을 따른다. 1.0.221은 깜빡임·고개 돌리기를 요청하고 5회 실패 시 멈춘다고 적어 도움말의 "지시 없음" 설명과 다르다. 최신 변경 기록을 따른다.
- 기타: 실패 뒤 암호를 입력하면 새 외모를 학습한다(1.0.183). 연속 2회 크래시로 안전 모드가 되면 Face Unlock이 꺼진다. 인식 개선 업데이트 뒤 재등록을 요구할 수 있다(1.0.206, 1.0.208). 설정 창은 잠금 화면 위로 열리지 않는다(1.0.167). 백업을 복원해도 Face Unlock 스위치는 Mac별로 유지된다(1.0.222). 구형 Mac용 "Face Unlock Only" 모드는 노치 기능을 모두 끄고 Face Unlock만 돌린다(1.0.226). "Remove Face Unlock"은 키체인의 얼굴과 암호를 지우고, 앱 제거로도 지워진다. (https://notchy.dev/help/notchy-crashes/ , https://notchy.dev/help/remove-face-unlock/)

### 4.3 잠금 화면 위젯·카드

- 켜기: Settings → Lock Screen → "Lock Screen Widget"(opt-in). (https://notchy.dev/help/lock-screen-widgets/)
- 카드: Now Playing, Timer(실행 중 스톱워치 포함, 1.0.223), Up Next, Reminders, Focus, Weather, Battery, Device Batteries. 2.0.1에서 AirPods 배터리·충전이 추가되었다. 잠금 화면 전체 가사(1.0.99, 1.0.121부터 기본 켬)도 있다.
- 배치: 레이아웃(카드 묶음 또는 Single Strip), Placement, Vertical Position, Card Density(Compact), Card Width, Columns, Match Card Heights, "Preview Layout". "Below Login"은 로그인 묶음 아래 공간이 있을 때만 나온다. 잠금 아이콘·Face Unlock 아일랜드 위치("Pill Vertical Offset")는 위젯 위치와 별개 설정이다. (https://notchy.dev/help/lock-screen-widget-placement/ , https://notchy.dev/help/lock-screen-island-position/)
- 모양: "Album Art Background", "Card Background"(유리·평면 어두운 색·카드 없음), "Same Glass as Panel", Clear 유리(1.0.226).
- 개인정보: "Show Event and Reminder Titles"를 켜야 일정·미리알림 제목이 보이고, 끄면 시간만 보인다(1.0.224부터 기본은 시간만). 메시지 미리보기는 잠금 화면에 나오지 않는다(1.0.196). 잠금 화면의 클릭은 암호 칸으로 넘어가고 플레이어 버튼만 반응한다(1.0.53). 컨트롤을 눌러도 암호 입력 포커스를 뺏지 않는다(1.0.221).

### 4.4 Camera Guard

- 도움말 문서: 없음.
- 변경 기록: 1.0.123에서 헤더 Camera 버튼(카메라를 쓰는 앱이 있으면 녹색)과 함께 도입되었고, 앱이 카메라를 여는 순간 알려 준다. 1.0.166에서 상시 카메라·마이크 사용 아일랜드는 없어졌고 Camera Guard는 켜 두었을 때만 경고한다. (https://notchy.dev/changelog/#v1.0.123 , https://notchy.dev/changelog/#v1.0.166)
- 홈페이지 기능 목록은 "경고(또는 차단)"이라고 적는다. 설정 참조 페이지에는 "When the Camera Goes Live" 선택 항목이 있다(값은 설정 담당 문서 참고).
- 카메라가 켜진 뒤 앱을 종료하는지, 어떤 한계가 있는지: 자료 없음. Pomodoro 앱 차단은 앱을 숨기기만 하고 종료하지 않는다고 명시하는데, 이는 별개 기능이다. (https://notchy.dev/help/pomodoro-block-apps/)

### 4.5 앱별 오디오 믹서·EQ

- "Sound Mixer Tab"(opt-in): 소리를 내는 앱마다 볼륨, 3밴드 EQ(저음·중음·고음 ±12 dB), 출력 장치를 정한다. macOS 14.4 이상과 System Audio Recording 권한이 필요하다. (https://notchy.dev/help/per-app-volume/)
- 100%로 둔 앱은 건드리지 않고, Notchy가 끝나면 모든 앱이 원래 음량으로 돌아간다. (help/per-app-volume)
- 보라색 녹음 표시는 Audio-Reactive Bars와 Sound Mixer가 쓰는 시스템 오디오 탭 때문이다. 소리는 재생되는 동안 기기 안에서만 처리되고 녹음·저장·전송하지 않는다. 두 기능을 모두 끄면 표시가 사라진다. (https://notchy.dev/help/purple-recording-indicator/)
- 변경 기록: 1.0.158 도입, 1.0.172 앱별 출력 장치, 1.0.202 출력·마이크·입력 레벨·마이크 음소거, 2.0.3 앱 볼륨 최대 150%.

### 4.6 알림·메시지 미러링과 직접 답장

- 권한:
  - Accessibility: 필수 권한이며 통화·메시지 배너를 움직인다. (https://notchy.dev/help/permissions-notchy-needs/) 홈페이지는 메시지 아일랜드가 Accessibility로 동작해 Full Disk Access가 필요 없다고 적는다.
  - Full Disk Access: 선택. 오래된 알림 센터 기록과 Focus 모드 목록을 읽는 데 쓴다. macOS가 앱 실행당 한 번만 답을 캐시하므로 실행 중에 부여하면 재시작해야 반영된다(1.0.151). 홈페이지는 알림 센터 미러 탭이 Full Disk Access가 있을 때만 동작한다고 적는다.
  - Automation: Music, Spotify, Messages, Notes, System Events와 대화할 때 쓴다.
  - Contacts: FaceTime 수신 시 발신자 사진.
- 전달 방식: "Notification Delivery"에서 "Notchy Only"를 고르면 macOS 배너를 숨기고 노치에 띄운다. 인라인 답장은 이 방식에서만 가능하다(1.0.138). 배너가 닫히지 않으면 네 번 다시 확인하고 다른 방법으로 닫는다(1.0.148). macOS 26의 배너 위치 변경(1.0.147)과 macOS 27(1.0.207)에 대응했다.
- 답장: iMessage(1.0.38), Teams·Outlook·Slack(1.0.126). 1.0.140에서 잠시 Open으로 바뀌었다가 1.0.219부터 Teams·WhatsApp·Slack 등 답장이 실제로 전송된다.
- 그 밖: 앱별 음소거(1.0.126), 메시지 쌓기(1.0.214), 알림 사본 암호화 저장(1.0.224), 닫힌 노치 옆 읽지 않은 배지(2.0.2), 아이콘 배지를 세는 Unread 카드(1.0.126). 권한이 없는 설정(Incoming Calls, Messages, 알림 미러링, Replace System HUD)은 켤 수 없고 필요한 권한으로 안내한다(1.0.148).
- 통화: FaceTime·iPhone 통화와 Teams·Zoom·WhatsApp·Webex·Slack·Discord. 장치가 음소거를 지원하지 않으면 입력 게인을 낮추는 방식으로 음소거한다(1.0.149).

### 4.7 에이전트 연동

- Claude Code·Codex: Settings → AI Usage → "Agent Permission Islands". 권한이나 입력이 필요하면 아일랜드가 뜨고 터미널로 이동하는 버튼이 있다. "Approve & Deny from the Notch"를 켜면 아일랜드에서 바로 응답한다. (https://notchy.dev/help/claude-code-notifications/)
- 훅 설치·제거: `~/.claude/settings.json`과 `~/.codex/hooks.json`에 훅을 병합하고 다른 설정은 그대로 둔다. 기능을 끄거나 앱을 지우면 훅을 제거한다. Codex는 새 훅을 한 번 검토·신뢰하도록 요구한다. 2분 안에 답하지 않으면 에이전트는 평소처럼 터미널에서 묻는다. Notchy가 꺼져 있으면 훅은 아무것도 하지 않고 오류도 출력하지 않는다. 내장 제거기와 "Reset Everything & Relaunch"도 셸·에이전트 훅을 지운다. (help/claude-code-notifications, https://notchy.dev/uninstall/ , https://notchy.dev/help/reset-notchy-settings/)
- 승인 안전장치: 명령 전체와 실제 끝부분 표시(1.0.210), "Always"는 비슷한 명령에만 적용하고 숨은 문자를 보여 줌(1.0.211), 상시 허용을 AI Usage 페이지에서 1탭으로 철회(1.0.134), 실제로 막혔을 때만 알림(1.0.78), 터미널에서 답하면 노치 프롬프트를 1초 안에 내림(1.0.80), 턴별 비용과 세션 합계(1.0.57).
- 셸 활동: opt-in zsh 훅으로 10초 넘게 도는 명령에 타이머와 성공·실패 결과를 띄운다(1.0.57). 개발 서버·watch 프로세스는 제외하고 5분 뒤 자동으로 사라진다(1.0.65).
- Cursor·Copilot·Antigravity·OpenCode: 사용량 추적만 문서화되어 있다. 승인·터미널 이동 연동은 자료 없음.
- Home의 Coding Agents 카드(1.0.181).

### 4.8 AI 사용량 공급자와 값 가져오는 방식

- 로컬 로그: Claude Code, Codex, Cursor, Antigravity, Copilot이 Mac에 남기는 로그를 읽는다. 권한·키가 필요 없고 외부로 보내지 않는다. OpenCode도 로컬 기록으로 읽는다(1.0.219). (https://notchy.dev/help/ai-usage-setup/)
- 원격 계정: Settings → AI Usage → Accounts & Credentials → "Add Account"에서 공급자를 고르고 API 키나 토큰을 붙여 넣는다. 실제 요청으로 확인한 뒤 키체인에 저장한다. 해당 CLI가 이미 로그인되어 있으면 그 로그인을 쓰고 키가 필요 없다(1.0.46). 브라우저 로그인도 Notchy가 직접 읽는다(1.0.171). 한 공급자에 여러 계정을 둘 수 있다(1.0.79).
- 공급자: 변경 기록에 이름이 나온 곳은 OpenAI, DeepSeek, Claude, Cursor, Mistral(1.0.32), Claude API, Doubao(1.0.36), ai&, DeepInfra(1.0.50), Antigravity, Copilot(1.0.79), OpenCode(1.0.219)다. 규모는 "60개 이상"(1.0.61), 로고 기준 "40여 곳"(1.0.139)으로 적혀 있다. 홈페이지 로고 줄에는 SuperGrok도 있다. 전체 목록은 자료 없음.
- 새로고침: 위젯에서 탭하면 모든 계정을 다시 가져온다(1.0.96). 키체인이 필요한 실시간 조회는 명시적인 Refresh 때만 한다(1.0.52). Claude 첫 조회는 5분 캐시한다(1.0.47). 저전력 모드에서는 5분 주기로 늦춘다(1.0.43). 화면에 필요 없으면 멈춘다(1.0.224). 평상시 자동 갱신 주기는 자료 없음.
- 표시·경고: 5시간·주간 창, 페이스 예측, 오늘·7일·30일 지출, 잔액, 프로젝트·모델별 비용, 공급자 장애, 한도 근접·소진·리셋 경고, "Hide Personal Information"(프로젝트 이름·경로·메일 가림).

### 4.9 AI 클립보드·Ask AI

- AI Rewrite: Apple 기기 내 모델을 쓴다. macOS 26 이상, Apple Intelligence 지원 Mac, Apple Intelligence 켜짐이 필요하고, 켠 직후에는 모델을 내려받는 중일 수 있다. 키·계정·비용이 없고 기기 밖으로 보내지 않는다. 동작은 Proofread, Make Professional, Make Friendly, Make Concise, Summarise, Bullet Points이며 최대 6,000자다. (https://notchy.dev/help/ai-rewrite-unavailable/)
- Ask AI: 사용자의 Anthropic API 키로 Claude와 대화하고 비용은 사용자의 Anthropic 계정에 청구된다. Notchy는 접근권을 재판매하지 않는다. Claude Pro·Max 구독에는 API 접근이 없어 Console 키가 필요하다. 키는 키체인에 두고 대화는 메모리에만 둔다. "Remove API Key"로 지운다. 기본 꺼짐(1.0.202). (https://notchy.dev/help/ask-ai-api-key/)
- Ask About the Screen(2.0.0): 화면 일부를 골라 텍스트 복사, 링크·날짜 열기, 검색, 번역, 질문을 한다. 어떤 모델·키를 쓰는지는 자료 없음.
- 로컬 모델(Ollama 등)이나 다른 외부 API 키: 자료 없음.
- 관련 외부 전송: 번역은 텍스트를 Google로 보낸다(1.0.220). 이미지 텍스트 인식(OCR)은 기기 안에서 한다(1.0.45).

### 4.10 배터리 충전 한도·Sailing·방전·팬 제어

- 충전 한도: Settings → Battery → "Limit Charging", 50~100%. 충전기를 멈추려면 시스템 권한을 가진 백그라운드 헬퍼가 필요하고 설치할 때 관리자 암호를 한 번 묻는다. "Sailing Mode"(몇 %p 떨어질 때까지 재충전 안 함), "Automatic Discharge", "Top Up to 100%"가 있다. "Remove Charge Helper"는 정상 충전으로 돌리고 헬퍼를 지우며, 앱 제거로도 지워진다. "Not supported on this Mac"은 해당 모델이 충전 제어를 지원하지 않는다는 뜻이다. Apple silicon과 Intel MacBook에서 동작한다. (https://notchy.dev/help/charge-limit/ , https://notchy.dev/help/system-requirements/)
- 팬 제어: Settings → Battery & Fans → Fans → "Fan Control (Beta)". 같은 헬퍼를 쓰고 관리자 암호를 한 번 묻는다. 팬마다 Auto, Manual(고정 속도), Curve(온도 따라감)를 고르고 "All Fans Automatic"으로 언제든 되돌린다. macOS 열 보호는 항상 켜져 있고, 설정 속도는 하한일 뿐 macOS가 더 빨리 돌릴 수 있다. 팬의 최소·최대 밖으로는 설정하지 않는다. 95 °C에 이르면 식을 때까지 펌웨어에 넘긴다. 일부 Mac 펌웨어는 속도 설정을 막고 설정 화면에 그렇게 표시한다. (https://notchy.dev/help/fan-control/)
- 덮개 닫고 깨어 있기: Settings → Caffeine → "Stay Awake With the Lid Closed". 시스템 전원 설정을 바꾸므로 관리자 암호를 묻는다. 회사·학교 계정도 마찬가지다(1.0.220). (https://notchy.dev/help/keep-mac-awake/)
- 헬퍼의 구체적 형태(설치 방식, 프로세스 이름): 자료 없음.
- 경로 불일치: 충전 한도 도움말은 "Battery", 팬 도움말은 "Battery & Fans"라고 적는다.

### 4.11 외부 디스플레이 DDC·XDR 추가 밝기·Extra Dim

- DDC/CI: Apple silicon에서 외부 모니터 밝기·대비·입력 소스를 바꾸고 밝기 키로 외부 모니터도 조절한다(1.0.55). 홈페이지는 IOAVService를 쓴다고 적는다. 밝기 슬라이더 수정(1.0.57), 깨어난 뒤 밝기 복구(1.0.76), 모니터 자체 화면에 밝기 표시(1.0.124).
- DDC를 받지 않는 모니터(DisplayLink 독, 대부분의 허브)는 소프트웨어로 어둡게 하고, 어떤 디스플레이가 왜 안 되는지 설정에 표시한다(1.0.130). 내장·까다로운 디스플레이도 소프트웨어 디밍을 얻었다(1.0.131).
- Extra Brightness: XDR 디스플레이용(2.0.0). 설정 참조 페이지는 배터리를 더 쓰고 발열이 늘며 Boost Strength 조절이 있다고 적는다.
- Extra Dim: 변경 기록과 도움말 본문에는 이름이 없다. 설정 참조 페이지 Displays에 모든 디스플레이의 밝기·Extra Dim·주사율 항목이 있고, 외부 디스플레이는 Apple silicon이 필요하며 모든 모니터가 받아들이지는 않는다고 적는다. 도움말 기준으로는 자료 없음.
- 도움말 전용 문서: 없음.

### 4.12 화면 캡처·공유에서 숨기기

- Settings → Behavior → "Screen Sharing Privacy" 3가지:
  - "Hidden from Captures": 캡처 앱에 Notchy를 빼 달라고 요청하고 본인 화면에는 보인다. 일부 공유 앱은 여전히 캡처할 수 있다.
  - "Hidden Everywhere": 본인 화면에서도 숨긴다. 되돌리려면 응용 프로그램에서 Notchy를 다시 열어 설정을 띄운 뒤 Visible이나 Hidden from Captures를 고른다.
  - "Hide While Mirroring": 화면 미러링 중 숨긴다. (https://notchy.dev/help/hide-during-screen-sharing/)
- 보장: 없다. 공유 앱마다 캡처 방식이 달라 중요한 발표 전에는 공유 미리보기를 확인하라고 한다. 특히 Cuely 텔레프롬프터를 쓸 때 그렇다. ⌥Space로 즉시 숨길 수 있다.
- 충돌: 1.0.9는 Cuely가 Zoom·Meet·Teams·OBS 시청자에게 보이지 않는다고 적었지만, 현재 도움말은 일부 앱이 캡처할 수 있다고 경고한다. 도움말을 따른다.
- 관련: 통화·Notchy 녹화·미러링 중에는 명령 팔레트가 클립보드 결과를 숨긴다. AI Usage의 개인정보 가리기가 있다. (https://notchy.dev/help/command-palette-find-files/)

### 4.13 캘린더·미리알림·Todoist·날씨·iCloud 동기화

- 캘린더: macOS 캘린더 앱의 모든 캘린더를 보여 준다("Use macOS Calendars", 기본 켬, Calendar 권한 필요). Google·Microsoft 365·Exchange는 시스템 설정 → 인터넷 계정에서 캘린더를 켜고 추가한다. 인터넷 계정 없이 쓰려면 Settings → Calendar → Connect Another Calendar → Calendar Link 또는 CalDAV로 .ics 링크나 CalDAV 계정을 넣는다. 이 둘은 읽기 전용이다. Notchy는 Google·Microsoft에 직접 로그인하지 않는다. (https://notchy.dev/help/calendar-setup/)
- 회의: "Upcoming Event Island"와 "Lead Time"으로 카운트다운을 띄우고, 지원하는 회의 링크가 있으면 Join을 보여 준다. "Keep Until Joined or Dismissed"는 계속 남는 알림을 준다. (https://notchy.dev/help/calendar-meeting-countdown/) 노치에서 일정 생성·편집(1.0.201, 기본 꺼짐)과 빠른 추가(2.0.3)가 있으나 어느 캘린더에 쓰는지는 자료 없음.
- 미리알림: Apple Reminders 또는 Todoist. Todoist 연결 방식(토큰·OAuth)은 자료 없음. Microsoft To Do는 1.0.208에서 폐기되었다.
- 날씨: Open-Meteo를 쓰며 계정·키가 필요 없다. "City (optional)"에 도시를 쓰면 위치 권한 없이 쓰고, 비우면 현재 위치(위치 권한)를 쓴다. (https://notchy.dev/help/weather-without-location/)
- iCloud: 설정 동기화는 Settings → About → Backup → "Sync Settings via iCloud"(기본 꺼짐)다. 클립보드는 "Sync Saved Items with iCloud"(기본 꺼짐)로 저장한 텍스트 항목과 목록만 동기화하고, 일반 기록과 이미지는 복사한 Mac에만 남는다. Home Quick Note 카드도 백업·iCloud 동기화에 포함된다(1.0.132). (https://notchy.dev/help/backup-settings/ , https://notchy.dev/help/clipboard-sync/)

### 4.14 Homebrew·앱 제거기·데스크톱 위젯·업데이트 채널·설정 가져오기/내보내기

- Packages 탭(Homebrew): 사용자의 Homebrew를 터미널 없이 실행하므로 암호를 입력할 수 없다. `sudo`가 필요한 cask는 Homebrew 오류로 실패하고 터미널에서 직접 올려야 한다. `/opt/homebrew/bin/brew` 또는 `/usr/local/bin/brew`를 쓰고 Homebrew 자체를 설치하지 않는다. 업데이트는 탭을 열거나 Refresh를 누를 때만 확인한다. (https://notchy.dev/help/homebrew-update-fails/)
- Notchy 자체의 Homebrew 배포: `brew install --cask vishvavariya/notchy/notchy`, macOS 13 이상, 웹사이트와 같은 서명·공증 빌드. `brew uninstall --zap notchy`는 macOS 권한 기록만 남기고 내장 제거기와 같은 범위를 지운다. (https://notchy.dev/help/install-with-homebrew/)
- 앱 제거기: Packages 탭 App Cleaner(1.0.181)로 앱 삭제·초기화·캐시 비우기를 하고, 먼저 건드리는 파일을 보여 주며, 삭제된 앱의 잔여물도 치운다. 1.0.178에서 잔여 파일과 함께 휴지통으로 옮기는 기능이 들어왔다. 도움말 문서는 없다.
- Notchy 자체 제거: Settings → About → App → "Uninstall Notchy"는 설정, 권한 기록, 키체인 항목, 캐시, 셸·에이전트 훅, 충전 한도 헬퍼를 지우고 휴지통으로 간다. 수동 제거 경로는 `~/Library/Application Support/Notchy`, `~/Library/Preferences/dev.notchy.app.plist`, `~/Library/Caches/dev.notchy.app`이다. (https://notchy.dev/uninstall/)
- 데스크톱 위젯: Settings → Home → "Desktop Widgets". Clock, World Clock, Now Playing, Weather, Sunrise & Sunset, Calendar, Batteries, System, Photo를 배경화면 위·모든 창 아래에 둔다. 끌어서 옮기고 우클릭으로 크기를 바꾸거나 지운다. "Glass Widgets", "Add Photo Widget", "Lyrics in Now Playing" 옵션이 있다. 항상 위에 뜨는 "Floating Player"는 ⌘1~⌘4로 크기를 바꾼다. (https://notchy.dev/help/desktop-widgets/ , https://notchy.dev/help/floating-player/) 별도로 1.0.79에서 데스크톱·알림 센터용 AI Usage·Activity·Timer 위젯이 생겼다.
- 업데이트: Sparkle 기반이다. 약 1시간마다 확인하고 백그라운드로 받은 뒤 Notchy 종료 시 설치한다. "Check for Updates Automatically", "Download Updates Automatically", "Skip This Version"이 있다. 설치 전 서명을 확인하고(1.0.225부터 자체 키 서명만), 설치에 실패하면 기존 앱을 복원한다(1.0.223). 개발자가 심각한 버전을 막으면 "Update Required" 창만 뜨고, 오프라인이면 그냥 시작한다. Beta 채널은 1.0.55에 들어왔지만 현재 도움말·설정 참조에는 없다. (https://notchy.dev/help/update-notchy/ , https://notchy.dev/help/update-required-window/)
- 설정 가져오기·내보내기: Settings → About → Backup → "Export Settings"는 `.notchysettings` 파일을 만들고 "Import Settings"로 다른 Mac에서 불러온다. 가져오기 전에 확인을 묻고(1.0.224), Face Unlock·링크 자동화 스위치는 Mac별로 유지되며(1.0.222), Cuely 대본은 남는다(1.0.196). 초기화는 페이지별 "Restore Defaults", 전체 "Reset All Settings"(먼저 백업 내보내기 제안), Developer의 "Reset Everything & Relaunch"(권한·키체인·캐시·훅까지)로 나뉜다. (https://notchy.dev/help/backup-settings/ , https://notchy.dev/help/reset-notchy-settings/)

### 4.15 그 밖의 권한·개인정보 문구

- 권한 목록: 필수는 Accessibility뿐이다. 나머지는 기능을 켤 때 묻는다. Camera(미러·Face Unlock), Bluetooth(AirPods 감지·배터리), Calendar·Reminders, Location(날씨, 도시 입력으로 대체 가능), Contacts(FaceTime 발신자 사진), Microphone·Speech Recognition(받아쓰기, 노래 인식, Cuely 음성 따라가기. 소리를 저장하지 않고 기기에서 인식), Full Disk Access(알림 센터 기록·Focus 목록), Input Monitoring(트랙패드 Knock, 미디어 키 처리), Screen Recording(스크린샷·녹화·창 제목), Files & Folders(Screenshot to Shelf), Automation(Music·Spotify·Messages·Notes·System Events). (https://notchy.dev/help/permissions-notchy-needs/)
- Screen Recording은 macOS가 한 번만 묻고, 나중에 시스템 설정에서 허용하면 Notchy가 종료됐다 다시 열린다. 권한은 응용 프로그램 폴더의 단일 사본에 부여해야 하고, 디스크 이미지·다운로드 폴더에서 실행하면 대화상자 없이 거부될 수 있다. 권한별 "Reset & Relaunch"가 있다. (https://notchy.dev/help/permission-granted-not-working/ , https://notchy.dev/help/install-notchy/)
- 인터넷 전송: 하루 한 번 가명 핑(임의 설치 ID, 앱·macOS 버전, Region 설정, 업데이트 상태)을 보내며 끌 수 없다. 업데이트 확인 결과와 후원 안내 탭 여부도 보낸다. 이름·메일·하드웨어 식별자·앱 내 활동은 포함하지 않는다. 기능별로 켰을 때만 LRCLIB(제목·아티스트, 있으면 앨범·길이), Open-Meteo, Yahoo Finance, 연결한 캘린더, 키를 넣은 AI 공급자, Anthropic(Ask AI)과 통신한다. 클립보드·Face Unlock·받아쓰기·OCR·셸프는 Mac을 떠나지 않는다. (https://notchy.dev/help/what-notchy-sends/ , https://notchy.dev/help/lyrics-not-showing/)
- 크래시 보고: "Ask Each Time"(기본), "Send Automatically", "Never Send". 앱·macOS 버전, CPU 종류, 스택만 담고 홈 폴더 경로를 지운다. 하드웨어 모델·일련번호·설치 ID는 없다. 보내지 않은 보고서는 14일 보관한다. (https://notchy.dev/help/crash-report-settings/)
- 클립보드: 기본 40개, 100·200·500으로 늘릴 수 있고 Mac에만 저장한다. 암호 관리자가 숨김 표시한 복사본은 항상 건너뛰고, 지정한 앱이 앞에 있을 때의 복사도 기록하지 않는다. (https://notchy.dev/help/clipboard-history/ , https://notchy.dev/help/clipboard-exclude-apps/)
- 받아쓰기: Microphone·Speech Recognition·Accessibility가 필요하고 기기 안에서 인식하며 한 번에 최대 2분이다. (https://notchy.dev/help/dictation-setup/)
- 브라우저 재생 속도: 브라우저의 "Allow JavaScript from Apple Events"와 Automation 승인이 필요하다. 조직 정책으로 막힐 수 있다. 설정 참조 페이지는 켜져 있는 동안 그 브라우저를 제어하도록 허용된 앱이 페이지에서 스크립트를 실행할 수 있다고 경고한다. (https://notchy.dev/help/browser-playback-speed/)
- Spotify: PKCE 로그인이라 클라이언트 비밀이 없고, Redirect URI는 `http://127.0.0.1:8888/callback`, 갱신 토큰은 키체인에 둔다. Spotify 암호를 묻지 않는다. (https://notchy.dev/help/connect-spotify/)
- HomeKit·Focus: macOS가 직접 접근을 주지 않아 사용자가 만든 단축어(Home 동작, "Set Focus")를 실행한다. (https://notchy.dev/help/homekit-controls/ , https://notchy.dev/help/switch-focus-modes/)
- 메뉴 막대 숨은 아이콘 접근: 다른 앱의 상태 항목을 받는 API가 없어 Accessibility로 실제 항목을 눌러 준다. 타이머로 훑지 않고 카드가 열릴 때와 앱 실행·종료 때만 목록을 다시 만든다. (https://notchy.dev/menu-bar-icons-behind-notch/)
- 배터리 소모 경고: 배터리 사용 중 다른 앱이 3분 연속 CPU 80% 이상이면 경고하고, 같은 앱은 1시간에 한 번까지, 시스템 프로세스는 제외한다. (https://notchy.dev/help/battery-drain-warning/)
- 복구: 12초 무응답이면 자동 재시작하고 몇 분 안에 두 번 멈추면 묻는다. 비상 강제 종료 ⌃⌥⌘⎋. (https://notchy.dev/help/notchy-frozen/)
- 라이선스: 한 번에 Mac 한 대, "Move to This Mac"과 "Deactivate This Mac…", 구매 후 14일 환불, 결제 대행 Dodo Payments(카드 내역 DODOPAY_NOTCHY), 구독 없음. (https://notchy.dev/help/lost-license-key/ , https://notchy.dev/help/charge-on-card-statement/)
- 시스템 요구: macOS 13 Ventura 이상, Apple silicon·Intel 네이티브. 오디오 반응 시각화와 Sound Mixer는 14.4 이상, AI Rewrite는 26과 Apple Intelligence가 필요하다. (https://notchy.dev/help/system-requirements/)
- 웹사이트: 사이트 방문 분석에는 동의 시에만 Google Analytics를 쓴다(사이트 하단 동의 배너).

## 5. 도움말 문서 목록

도움말 센터 분류 순서를 따른다. `/help/settings/`는 범위 밖이라 뺐다.

### 시작하기

- https://notchy.dev/help/install-notchy/ — DMG를 응용 프로그램에 끌어 설치하고 거기서 실행해야 권한 문제가 없다
- https://notchy.dev/help/install-with-homebrew/ — Homebrew cask 설치·`--zap` 제거와 macOS 13 이상 요건
- https://notchy.dev/help/system-requirements/ — macOS 13 이상, Apple silicon·Intel, 기능별 추가 요구 사항
- https://notchy.dev/help/lost-license-key/ — 라이선스 키 찾기, Mac 옮기기·비활성화, 한 대 제한
- https://notchy.dev/help/charge-on-card-statement/ — DODOPAY_NOTCHY 결제 내역의 의미와 14일 환불
- https://notchy.dev/help/where-is-notchy/ — Dock 아이콘 없이 화면 상단 노치·알약에 산다
- https://notchy.dev/help/open-notchy-settings/ — 알약 우클릭·⌘,로 설정 열기와 설정 검색
- https://notchy.dev/help/permissions-notchy-needs/ — 필수는 Accessibility뿐이고 나머지 권한은 기능별 요청
- https://notchy.dev/help/features-off-after-install/ — 새 설치와 업데이트의 새 기능은 꺼진 채 시작한다
- https://notchy.dev/help/launch-at-login/ — 로그인 시 열기 기본 켬, 시스템 로그인 항목 사용

### Notchy 사용

- https://notchy.dev/help/open-the-island/ — 클릭·⌃⌥N·hover·두 손가락 스와이프·Knock으로 패널 열기
- https://notchy.dev/help/stop-opening-on-hover/ — hover 지연·더블클릭 요구로 의도치 않은 열림 막기
- https://notchy.dev/help/keyboard-shortcuts/ — 기본 단축키와 비상 강제 종료 단축키
- https://notchy.dev/help/change-notch-size/ — 닫힌 알약 70~140%, 높이 보정, 패널 너비·크기 방식
- https://notchy.dev/help/choose-display/ — 표시 디스플레이 선택, 디스플레이별 노치/알약 모양
- https://notchy.dev/help/hidden-in-full-screen/ — 전체 화면 숨김 규칙과 상단 터치로 꺼내기
- https://notchy.dev/help/hide-during-screen-sharing/ — 화면 공유 개인정보 3가지 선택과 캡처 보장 없음
- https://notchy.dev/help/change-language/ — 앱 언어 변경(재시작 필요)과 12/24시간 표기
- https://notchy.dev/help/reduce-motion-haptics/ — Reduce Motion과 햅틱 끄기
- https://notchy.dev/help/backup-settings/ — 설정 내보내기·가져오기와 iCloud 설정 동기화
- https://notchy.dev/help/hide-notchy-temporarily/ — ⌥Space로 잠시 숨기기와 Invisible Until Hover
- https://notchy.dev/help/minimal-layout/ — Minimal Layout으로 탭·버튼 줄이기
- https://notchy.dev/help/panel-color/ — 패널 사용자 색·그라데이션과 알약 색 맞추기
- https://notchy.dev/help/keep-clock-visible/ — 음악·타이머 중 시계를 계속 보는 방법(전용 설정은 없음)
- https://notchy.dev/help/tabs-beside-notch/ — 탭은 카메라 왼쪽, 헤더 버튼은 오른쪽에 두기
- https://notchy.dev/hide-macbook-notch/ — Hide the Notch로 상단 띠만 검게 칠해 노치 감추기(모서리 포함, Space별 복원)

### 음악·미디어

- https://notchy.dev/help/now-playing-not-showing/ — macOS Now Playing에 보고하는 앱만 표시, 점검 순서
- https://notchy.dev/help/connect-spotify/ — Spotify 개발자 앱 Client ID·PKCE·루프백 8888 포트로 연결
- https://notchy.dev/help/youtube-music-setup/ — YouTube Music 데스크톱 앱 API Server 플러그인 필요
- https://notchy.dev/help/browser-playback-speed/ — 브라우저 동영상 속도 조절과 Apple Events JavaScript 허용
- https://notchy.dev/help/lyrics-not-showing/ — LRCLIB 동기 가사, 3초 길이 차이 규칙, NetEase 선택
- https://notchy.dev/help/purple-recording-indicator/ — 보라색 표시는 시스템 오디오 탭 때문이며 녹음하지 않는다
- https://notchy.dev/help/per-app-volume/ — Sound Mixer 앱별 볼륨·EQ, macOS 14.4와 System Audio Recording 필요
- https://notchy.dev/help/airpods-not-detected/ — AirPods 감지는 블루투스 권한과 근거리 케이스 열기 필요
- https://notchy.dev/help/floating-player/ — 창 위에 뜨는 플로팅 플레이어와 크기 단축키
- https://notchy.dev/help/square-album-art/ — 앨범 아트를 둥근 사각형으로
- https://notchy.dev/help/spotify-playlist-checkmarks/ — 현재 곡이 이미 든 Spotify 재생목록 표시
- https://notchy.dev/help/music-island-too-wide/ — 음악 아일랜드 폭을 줄이는 설정(최대 폭 설정은 없음)

### AI·개발자

- https://notchy.dev/help/ai-usage-setup/ — 로컬 로그와 원격 계정으로 AI 사용량 추적
- https://notchy.dev/help/claude-code-notifications/ — Claude Code·Codex 권한 아일랜드와 훅 설치·제거 규칙
- https://notchy.dev/help/ask-ai-api-key/ — Ask AI는 사용자 Anthropic API 키가 필요하다
- https://notchy.dev/help/ai-rewrite-unavailable/ — AI Rewrite의 Apple Intelligence·macOS 26 요건
- https://notchy.dev/help/dictation-setup/ — 기기 내 받아쓰기와 Fn 키 사용 설정
- https://notchy.dev/help/local-api/ — 127.0.0.1:9999 줄 단위 JSON API와 Show in Notchy 딥링크

### 클립보드·파일·도구

- https://notchy.dev/help/clipboard-history/ — ⌃⌥C로 열기, 기본 40개 보관, 암호 관리자 복사 제외
- https://notchy.dev/help/clipboard-exclude-apps/ — 특정 앱의 복사 기록 막기
- https://notchy.dev/help/clipboard-sync/ — 저장 텍스트 항목만 iCloud 동기화
- https://notchy.dev/help/file-shelf/ — 파일 셸프 사용, 원본 참조와 독립 사본 선택
- https://notchy.dev/help/calendar-setup/ — 인터넷 계정·.ics·CalDAV로 캘린더 추가(직접 로그인 없음)
- https://notchy.dev/help/switch-focus-modes/ — 단축어로 Focus 전환, Full Disk Access 역할
- https://notchy.dev/help/homekit-controls/ — 단축어를 통한 HomeKit 제어
- https://notchy.dev/help/charge-limit/ — 충전 한도와 관리자 암호가 필요한 헬퍼
- https://notchy.dev/help/keep-mac-awake/ — Caffeine과 덮개 닫고 깨어 있기
- https://notchy.dev/help/weather-without-location/ — 도시 입력으로 위치 권한 없이 날씨 보기
- https://notchy.dev/help/knock-not-working/ — Knock 소스별 요건과 대체 동작
- https://notchy.dev/help/window-snapping/ — 노치로 끌어 창 스냅, 키보드 스냅
- https://notchy.dev/help/lock-screen-widgets/ — 잠금 화면 위젯 켜기·카드·제목 표시 개인정보
- https://notchy.dev/help/homebrew-update-fails/ — Packages 탭에서 sudo 필요한 cask가 실패하는 이유
- https://notchy.dev/help/desktop-widgets/ — 배경화면 위 데스크톱 위젯 종류와 배치
- https://notchy.dev/help/fan-control/ — 팬 제어 모드와 열 보호 규칙
- https://notchy.dev/help/pomodoro-block-apps/ — Pomodoro 집중 중 지정 앱 숨기기
- https://notchy.dev/help/repeat-timer/ — 같은 길이로 다시 시작하는 반복 타이머
- https://notchy.dev/help/command-palette-find-files/ — 명령 팔레트에서 홈 폴더 파일·클립보드 텍스트 찾기
- https://notchy.dev/help/screenshot-background/ — 스크린샷 편집기 배경·여백·모서리·그림자
- https://notchy.dev/help/calendar-meeting-countdown/ — 다음 회의 카운트다운 아일랜드와 Join

### Face Unlock

- https://notchy.dev/help/set-up-face-unlock/ — 암호 확인, 카메라, 얼굴 등록, Accessibility 순서의 설정 과정
- https://notchy.dev/help/face-unlock-not-working/ — 재시동 후 암호, Touch ID 재승인, 조명·카메라 점검
- https://notchy.dev/help/is-face-unlock-secure/ — 편의 기능이며 사진·영상으로 풀릴 수 있다는 경고
- https://notchy.dev/help/remove-face-unlock/ — 키체인의 얼굴·암호 삭제

### 문제 해결

- https://notchy.dev/help/notchy-not-showing/ — Notchy가 안 보일 때 점검 순서
- https://notchy.dev/help/permission-granted-not-working/ — 다른 사본에 권한이 기록된 경우와 Reset & Relaunch
- https://notchy.dev/help/notchy-frozen/ — ⌃⌥⌘⎋ 강제 종료와 자동 재시작
- https://notchy.dev/help/notchy-crashes/ — 크래시 시 업데이트, 안전 모드, 익명 보고
- https://notchy.dev/help/battery-drain-warning/ — 다른 앱의 CPU 과다 사용 경고 기준
- https://notchy.dev/help/update-required-window/ — 개발자가 막은 버전의 강제 업데이트 창
- https://notchy.dev/help/restart-notchy/ — Notchy 재시작 방법
- https://notchy.dev/help/bug-report/ — 버그 보고에 넣을 정보와 진단 복사 기능
- https://notchy.dev/help/lock-screen-island-position/ — 잠금 아이콘·Face Unlock 애니메이션이 낮게 보이는 문제(1.0.208 수정 예고 시점에 쓰인 문서)
- https://notchy.dev/help/lock-screen-widget-placement/ — 잠금 화면 위젯이 시계·로그인 창을 덮을 때 배치 조정
- https://notchy.dev/help/panel-interaction-problems/ — 브라우저가 앞에 있을 때 버튼 무반응 보고 방법
- https://notchy.dev/help/volume-slider-not-working/ — 시스템 볼륨 슬라이더가 안 움직일 때 점검
- https://notchy.dev/help/double-haptic-click/ — 한 번 클릭이 두 번 햅틱으로 느껴질 때
- https://notchy.dev/menu-bar-icons-behind-notch/ — 노치 뒤에 숨은 메뉴 막대 아이콘을 Accessibility로 눌러 주는 방식
- https://notchy.dev/notchy-cpu-battery-usage/ — CPU·배터리 측정치와 측정 방법, 저전력 모드 동작

### 개인정보·업데이트·제거

- https://notchy.dev/help/update-notchy/ — 자동 업데이트 주기와 수동 확인
- https://notchy.dev/help/what-notchy-sends/ — 일일 가명 핑과 기능별 외부 통신 목록
- https://notchy.dev/help/crash-report-settings/ — 크래시 보고 3가지 선택과 담기는 내용
- https://notchy.dev/help/reset-notchy-settings/ — 페이지별·전체·완전 초기화
- https://notchy.dev/uninstall/ — 내장 제거기, Homebrew 제거, 수동 제거 경로
