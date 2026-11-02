# Notchy 기능 목록 (공식 사이트 기준)

Dynamic Notch 기능 맞추기 작업의 기준 자료이다. Notchy 공식 사이트의 홈페이지와 기능 가이드를 읽고 기능 단위로 정리했다. 문장은 사이트 문구를 옮기지 않고 다시 썼다.

## 수집 정보

| 항목 | 내용 |
|---|---|
| 수집일 | 2026-11-02 |
| 주 출처 | https://notchy.dev/ (홈페이지), https://notchy.dev/features/ (기능 가이드 목록), 목록에 연결된 가이드 페이지 전부 |
| 보조 출처 | https://notchy.dev/help/ 일부 문서(가이드에 없는 권한·조건을 보완할 때만 사용, 해당 칸에 URL을 적음), https://notchy.dev/demo/, https://notchy.dev/blog/notchy-productivity-toolkit/ |
| 홈페이지 기능 카드 | 74개 확인(홈페이지의 "All 74 features" 표기와 일치) |
| 기능 가이드 | 131개 확인(/features/ 페이지의 "131 feature guides" 표기와 일치). 사이트 분류별 개수는 The Dynamic Island 13, Music & Audio 14, Focus & Time 17, Files & Clipboard 19, System & Hardware 23, Input, Shortcuts & Windows 19, Notifications & Privacy 16, Developers & AI 10이다. 고유 URL은 130개이며, Tap to Control(F088)은 Knock Gesture 페이지 안의 `#tap-to-control` 구역이다 |
| 기능 가이드 외 링크 | /features/ 하단의 "Guides and roundups" 23개 링크는 가이드 수에 넣지 않고 4절에 따로 적었다 |
| 로드 실패 | 없음. 가이드 130개 URL, roundup 23개, /help/system-requirements/ 모두 HTTP 200으로 받았다. 본문이 서버에서 렌더링된 HTML이라 브라우저 도구는 쓰지 않았다. 홈페이지 인터랙티브 미리보기의 장면별 설명은 HTML에 없고 자바스크립트로 그려져서, 페이지가 불러오는 스크립트 파일의 문자열로 확인했다 |

## 공통 조건

- 가격은 한 대당 $24.99 일회성 결제이고 7일 무료 체험이 있다. 사이트는 모든 기능이 한 라이선스에 들어 있고 Pro 등급·구독·인앱 결제가 없다고 밝힌다. 이 표의 "요구 사항" 칸에 유료 등급을 적은 항목이 없는 이유다.
- 최소 사양은 macOS 13 Ventura이고, Apple silicon과 Intel을 담은 유니버설 빌드 하나로 배포한다. 노치가 없는 화면(iMac, Mac mini, Mac Studio, 외장 모니터, 구형 MacBook)에서는 화면 상단에 떠 있는 알약(pill)으로 표시한다.
- 설치는 서명된 DMG 또는 Homebrew cask(`brew install --cask vishvavariya/notchy/notchy`)이며 계정이 필요 없다. 앱은 Sparkle로 자동 업데이트한다.
- 도움말 기준으로 반드시 필요한 권한은 손쉬운 사용(Accessibility) 하나이고, 나머지 권한(카메라, 블루투스, 캘린더·미리 알림, 위치, 연락처, 마이크·음성 인식, 전체 디스크 접근, 입력 모니터링, 화면 기록, 파일 및 폴더, 자동화)은 해당 기능을 켤 때 요청한다(https://notchy.dev/help/permissions-notchy-needs/).
- 도움말 기준으로 새로 설치하면 선택 기능은 모두 꺼진 상태로 시작하고, 업데이트로 추가된 기능도 꺼진 채 들어온다(https://notchy.dev/help/features-off-after-install/).
- 공식 저장소(https://github.com/vishvavariya/notchy-feedback)는 릴리스와 피드백용이고 앱은 비공개 소스다.

## 홈페이지 인터랙티브 미리보기

홈페이지에는 미리보기가 두 개 있다.

- "Try it on this Mac": Now Playing, Notification, Live Activities, HUDs, Timer, AI Usage, Clipboard, ⌘K Palette, Lock Screen 탭과 노치 모양·알약 모양 전환 버튼이 있다.
- "A tour of the notch": Now Playing, Notifications, AI Usage, Focus timer, Live Activities, HUDs, Clipboard, Window Snap, ⌘K Palette, Lock Screen 탭과 MacBook Pro·MacBook Air·iMac·Studio Display·External display 기기 전환이 있다.
- 스크립트에서 확인한 장면은 다음과 같다. 마우스를 올리면 60ms 뒤 플레이어 미리보기가 열린다. 본체 노크나 수정키 두 번 누르기로 노치가 열린다. 재생 중에는 아트워크와 막대로 접히고 제목은 호버 때 나온다. 알림이 노치 가운데에 뜬다. 음악 옆에 활동마다 캡슐이 붙는다. 볼륨·밝기 HUD가 노치로 옮겨 간다. 노치를 가로로 쓸어 탭을 바꾼다. 다운로드 진행률이 알약에 찬다. 뽀모도로 세션이 마스코트·카운트다운·진행선으로 표시된다. 배터리 완충 알림이 뜬다. AI 사용량 한도 경고가 뜬다. 창을 노치로 끌면 스냅 영역이 내려온다. 잠금 상태 자물쇠 표시가 있다.

## 표기 규칙

- ID는 /features/ 페이지에 나온 순서대로 F001부터 붙였다.
- "분류"는 요청받은 13개 분류로 다시 나눈 것이며 사이트 분류와 다를 수 있다.
- 세부 동작의 "1.0.xxx 도입"이나 "1.0.xxx부터"는 해당 가이드가 밝힌 버전이다.
- 가이드에 없는 권한·조건을 도움말에서 보완한 경우 그 도움말 URL을 함께 적었다. "자료 없음"은 가이드와 확인한 도움말 어디에도 근거가 없다는 뜻이다. "추정"이라고 적은 부분은 사이트 근거가 없는 판단이므로 구현 전에 확인해야 한다.
- 홈페이지 카드에만 있는 세부 동작은 "홈페이지 카드 기준"이라고 표시했다.

## 기능 가이드

| ID | 분류 | 기능 이름 | 세부 동작 | 요구 사항 | 근거 URL |
|---|---|---|---|---|---|
| F001 | 노치 UI·공통 | Dynamic Island for MacBook (맥북용 다이내믹 아일랜드) | 앱을 실행하면 노치를 감지해 그 둘레에 확장형 아일랜드를 그린다; 음악 재생 시 펼쳐지고 볼륨·밝기 조절 시 작은 HUD로 접힌다; 사용자가 요청하면 AirPods 배터리·파일 선반·뽀모도로 타이머를 펼쳐 보인다; 노치가 없는 맥에서는 화면 상단에 떠 있는 알약(pill) 형태로 같은 기능을 보여 준다; 메뉴 막대 상주 앱으로 동작하며 첫 실행 때 필요한 권한을 요청한다 | macOS 13 Ventura 이상; Apple silicon·Intel; 노치 지원 기종은 MacBook Pro 14/16(2021 이후)·MacBook Air M2 이후, 그 외는 알약 모드; 가이드에는 권한 종류가 없고, 도움말 기준 필수 권한은 손쉬운 사용 하나이며 나머지는 기능을 켤 때 요청(https://notchy.dev/help/permissions-notchy-needs/) | https://notchy.dev/dynamic-island-macbook/ |
| F002 | 노치 UI·공통 | Notch Widgets (노치 위젯) | 노치 위에 마우스를 올리면 아일랜드가 열리고 내장 위젯(AI 사용량, 클립보드, 미디어 컨트롤, 드롭 선반, 타이머 등)이 보인다; 위젯은 노치에 고정된 형태로 표시된다 | 손쉬운 사용(Accessibility) 권한: 단축키·창 스냅·노치 상호작용 처리용; macOS 13 이상 | https://notchy.dev/macbook-notch-widgets/ |
| F003 | 노치 UI·공통 | Live Activities (라이브 액티비티) | 맥에서 시작된 활동을 노치 알약에 실시간으로 띄운다; 대상은 카운트다운·스톱워치·뽀모도로, 다운로드 진행률, Zoom·Teams 통화 타이머, 다음 회의까지 남은 시간, Now Playing, Claude Code·Codex 권한 요청; 진행률 바를 실시간 갱신한다; 마우스를 올리면 펼쳐져 음악 탐색이나 파일 드롭을 받는다; AirPods 배터리·볼륨·밝기 표시도 같은 아일랜드에 나온다; 아이폰이 필요 없다 | macOS 13 이상, Intel·Apple silicon; 기능별 권한은 처음 켤 때 요청 | https://notchy.dev/live-activities-mac/ |
| F004 | 기타 | Stock Ticker (주식 시세) | 설정 › Stocks에서 회사명이나 티커로 검색해 관심 종목을 추가한다; 각 행에 당일 분봉 선과 전일 종가 기준선, 현재가 점을 그린다; 고정한 종목은 접힌 알약에서 순환 티커로 표시되고 마우스를 올리면 가격을 보여 준다; Stocks 탭에서 전체 관심 목록과 큰 차트를 본다; 종목별로 "특정 가격 이상/이하" 알림을 문장 형태로 설정하면 가격이 실제로 선을 넘을 때 노치 아일랜드를 띄운다; 장전·정규장·장후·휴장을 표시하고 장외 시간에는 색을 중립으로 바꾼다; 등락을 색과 화살표로 함께 표시한다; 해외 종목·지수·ETF를 지원하고 해당 통화로 표시한다 | 외부 서비스: 시세는 Yahoo Finance(가이드에는 없음, 도움말 https://notchy.dev/help/what-notchy-sends/ 기준); 계정 불필요; 인터넷 연결 | https://notchy.dev/mac-stock-ticker/ |
| F005 | 노치 UI·공통 | Notch Customization (노치 꾸미기) | 노치를 아일랜드로 바꾸고 폭을 조절한다; 노치 주변 메뉴 막대 아이콘을 숨긴다; 도움말 항목상 알약·패널 크기 조절, 패널 색 변경, 탭·헤더 버튼을 노치 옆으로 옮기는 설정이 있다 | 손쉬운 사용 권한(설치 안내 기준) | https://notchy.dev/macbook-notch-customization/ |
| F006 | 노치 UI·공통 | Hide the Notch (노치 숨기기) | 설정 › Appearance › Hardware Notch에서 Hide the Notch를 켠다; 현재 배경화면의 상단 띠만 검게 칠해 메뉴 막대를 검게 만든다; Space마다 배경화면이 다르므로 각 Space에 들어갈 때 적용한다; 원래 배경화면을 기억했다가 끄면 복원하며 비정상 종료 뒤에도 복원한다; 1.0.220부터 화면 둥근 모서리도 검게 칠한다; 숨긴 상태에서도 노치 영역 호버·클릭으로 아일랜드가 열린다; 메뉴와 아이콘 위치는 바뀌지 않는다 | 노치가 있는 맥에서만 옵션이 나타난다; macOS 13 이상 | https://notchy.dev/hide-macbook-notch/ |
| F007 | 노치 UI·공통 | External Monitors (외장 모니터 지원) | 노치가 없는 디스플레이를 감지하면 메뉴 막대 아래에 떠 있는 알약 모드로 자동 전환한다; 폭·높이·디스플레이 오프셋을 조절한다; 디스플레이 선택기로 내장 화면·외장 화면·양쪽 중 어디에 표시할지 고른다; 1.0.197부터 설정 › Behavior › Show On에서 External을 고르면 외장 화면에만 표시한다; 울트라와이드(21:9, 32:9) 화면에서도 가운데 정렬한다 | 외장 디스플레이; macOS 13 이상, Intel·Apple silicon | https://notchy.dev/dynamic-island-external-monitor/ |
| F008 | 노치 UI·공통 | 134 Languages (다국어 지원) | macOS 언어·지역 설정을 따라 자동으로 언어를 고른다; 패널·HUD·설정·권한 안내 문구를 모두 번역한다; 긴 단어 언어와 오른쪽→왼쪽 언어에서 레이아웃을 맞춘다; Localizable.xcstrings로 복수형·변수를 처리한다 | 없음(별도 설정 불필요); 페이지 안에서 133개와 134개 표기가 섞여 있다 | https://notchy.dev/mac-notch-app-languages/ |
| F009 | 노치 UI·공통 | Liquid Glass (리퀴드 글래스 재질) | 펼친 패널·카드·버튼·잠금 화면 위젯을 macOS 26의 시스템 유리 재질로 그린다; Smoke·Onyx·Graphite·Frost·Mist·Crystal 6가지 투명도 프리셋을 고른다; 접힌 알약은 불투명 검정으로 유지한다; macOS 13~15에서는 자체 제작 유리 효과로 대체한다; 노치를 닫으면 뒤쪽 애니메이션을 멈춘다; 설정에서 끌 수 있다 | 시스템 재질은 macOS 26 Tahoe 이상; 그 이하는 대체 효과 | https://notchy.dev/mac-liquid-glass/ |
| F010 | 노치 UI·공통 | Notch Clock (노치 시계) | 쉬고 있는 알약 가운데에 시각과 날짜를 표시한다(기본값 꺼짐); 타이머·음악·다운로드 같은 진행 중 활동이 있으면 시계가 비켜 주고 끝나면 돌아온다; 세계 시계 카드에 원하는 시간대를 원하는 순서로 추가한다; 알약에 상태 링 묶음을 켤 수 있다 | 주 용도는 노치 없는 외장 모니터·Mac mini·Studio | https://notchy.dev/mac-notch-clock/ |
| F011 | 노치 UI·공통 | Siri Island (시리 아일랜드) | Notchy 단축키나 메뉴 항목으로 Siri 요청을 시작한다; Siri UI 프로세스를 감시해 Siri가 화면에 떠 있는 동안 아일랜드를 표시한다; 음성·메뉴 막대·시스템 단축키로 부른 경우에도 표시하고 Siri가 사라지면 지운다; Siri 대화 내용·음성에는 접근하지 않는다 | macOS 13 이상; Siri 화면을 노치 안에 넣는 기능은 아님(macOS가 허용하지 않음) | https://notchy.dev/siri-mac-notch/ |
| F012 | 노치 UI·공통 | Intel Macs (인텔 맥 지원) | arm64·x86_64를 함께 담은 유니버설 빌드 하나로 배포해 Intel 맥에서 Rosetta 없이 실행한다; 노치 없는 화면에서는 알약으로 표시한다; 대기 동작은 이벤트 기반이고 닫힌 노치에서는 애니메이션을 멈춘다; 새 macOS 재질에 의존하는 일부 시각 효과는 지원 OS에서만 나온다 | macOS 13 이상, Intel; 1.0.172에서 일부 Intel 맥 위젯 빈 화면 버그 수정 | https://notchy.dev/dynamic-island-intel-mac/ |
| F013 | 노치 UI·공통 | MacBook Neo (노치 없는 맥북 지원) | 노치가 없는 MacBook Neo에서 메뉴 막대 아래 가운데에 알약을 그린다; 마우스를 올리면 Now Playing·파일 선반·클립보드·캘린더·타이머 패널이 열린다; Tahoe의 Liquid Glass로 그린다; 선택 설정인 Replace System HUD를 켜면 Tahoe의 볼륨·밝기 팝오버 대신 아일랜드에 HUD를 띄운다; "HUDs Beside the Notch" 배치만 노치가 필요해 쓸 수 없다 | macOS 26 Tahoe(기기 기본), Apple silicon; 노치 없음 | https://notchy.dev/dynamic-island-macbook-neo/ |
| F014 | 음악·오디오 | Now Playing (재생 중 컨트롤) | 시스템 미디어 정보를 읽어 Apple Music·Spotify·기타 플레이어의 재생을 감지하면 노치에 앨범 아트와 진행 상태를 접힌 형태로 표시한다; 알약에 마우스를 올리면 펼쳐져 타임라인 드래그·이전/다음·재생/일시정지를 제공한다; 1.0.200부터 접힌 노치의 앨범 아트를 원형 대신 둥근 사각형으로 표시하는 Square Album Art 옵션이 있다; 1.0.199부터 새 곡 시작 시 제목·아티스트를 잠깐 띄우는 Announce New Tracks, 긴 제목을 스크롤 대신 축소하는 Stop Title Scrolling 옵션이 있다; 1.0.201부터 최근 500곡 Local Listening History와 Local Music Bookmarks(로컬 저장, 기본 꺼짐)가 있다; 잠금 화면에 재생/일시정지·건너뛰기 카드를 띄울 수 있다; Now Playing 데스크톱·알림 센터 위젯은 가이드상 제공하지 않는다고 되어 있으나 F120에 배경화면용 Now Playing 위젯이 있다; 도움말상 창 위에 떠 있는 Floating Player(설정 → Home, ⌘1~4로 크기 전환)가 있다(https://notchy.dev/help/floating-player/) | macOS 13 이상, Apple silicon·Intel; 별도 설정 없음; 도움말상 Music·Spotify 연동에 자동화(Automation) 권한 사용 | https://notchy.dev/now-playing-mac/ |
| F015 | 음악·오디오 | Synced Lyrics (동기화 가사) | 재생 위치에 맞춰 현재 가사 줄을 노치 아래에 띄운다; macOS가 Now Playing으로 보고하는 모든 소스(Apple Music, Spotify, 브라우저 탭 등)를 따라간다; 동기화 가사가 있을 때만 표시하고 없으면 일반 Now Playing 알약만 보인다; 1.0.201부터 이동 가능한 데스크톱 가사 창(Desktop Lyrics, 일시정지·잠금·화면 미러링·녹화 중 숨김, 클릭 통과 가능, 기본 꺼짐)을 제공한다; 1.0.201부터 제공처가 준 번역을 원문과 함께 보여 준다(AI 번역 없음); 1.0.201부터 Additional Lyrics Provider를 켜면 LRCLIB보다 먼저 NetEase 공개 가사를 조회한다(제목·아티스트만 전송) | 외부 서비스: LRCLIB(무료, 키·계정 불필요), 선택 시 NetEase(지역에 따라 가용성 다름); 인터넷 연결 | https://notchy.dev/mac-lyrics-app/ |
| F016 | 음악·오디오 | Song ID (노래 찾기) | 노치에서 듣기를 시작하면 아일랜드가 듣는 중 표시로 바뀐다; ShazamKit으로 기기 안에서 오디오 서명을 만들어 대조한다; 일치하면 아트워크·제목·아티스트·Apple Music 열기 버튼을 아일랜드에 보여 준다; 찾지 못하면 시간 초과 메시지와 함께 스스로 종료한다; 녹음본은 기기를 벗어나지 않고 기록을 남기지 않으며 세션 종료 즉시 마이크 탭을 닫는다 | 마이크 권한(도움말은 마이크·음성 인식 권한을 받아쓰기·노래 찾기·Follow My Voice 묶음으로 안내); 외부 서비스: ShazamKit(Apple); 인터넷 연결 | https://notchy.dev/mac-song-identifier/ |
| F017 | 음악·오디오 | Spotify Controller (스포티파이 컨트롤) | 시스템 미디어 채널로 아트워크·스크러버·건너뛰기·재생 제어를 로그인 없이 제공한다; 접힌 미디어 아일랜드를 옆으로 스와이프하면 이전/다음 곡으로 넘어간다; 호버하면 미리보기 플레이어가 열린다; 설정에서 Spotify Integration을 켜고 사용자 본인의 Client ID로 OAuth 인증하면 노치의 ♥가 Liked Songs를 읽고 쓴다; 1.0.192부터 플레이리스트 추가 선택창에서 이미 곡이 들어 있는 플레이리스트에 체크 표시를 하고 중복 추가를 건너뛴다; 도움말상 셔플·플레이리스트 연동도 같은 연결을 쓴다; 모든 동작에 전역 단축키를 지정할 수 있다 | 기본 제어는 계정 불필요; 도움말상 Spotify 자동화(Automation) 권한 사용; ♥·플레이리스트는 Spotify 계정 + 사용자 소유 Spotify 앱 Client ID + OAuth, 토큰은 키체인 저장 | https://notchy.dev/mac-spotify-controller/ |
| F018 | 음악·오디오 | Audio Visualizer (오디오 시각화) | 켜면 시스템 오디오 출력의 실시간 FFT로 막대를 움직인다; 앱과 무관하게 브라우저·게임 소리도 반영한다; 기본은 꺼져 있고 꺼진 상태에서는 반복 애니메이션으로 대체한다; 노치의 재생 아일랜드 아트워크 옆과, 가사가 없을 때 Now Playing 탭에 표시한다 | macOS 14.4 이상(도움말 https://notchy.dev/help/system-requirements/); 시스템 오디오 탭 사용 중 macOS 보라색 녹음 표시가 뜸(도움말 https://notchy.dev/help/purple-recording-indicator/); 가이드 본문에는 권한 명시 없음 | https://notchy.dev/mac-audio-visualizer/ |
| F019 | 음악·오디오 | Audio Output Switcher (오디오 출력 전환) | 노치에 모든 출력 장치(내장 스피커, AirPods, 블루투스 스피커, USB 오디오, HDMI·DisplayPort 모니터)를 나열한다; 한 번 누르면 시스템 기본 출력이 바뀐다; Core Audio를 감시해 장치 연결·해제·기본값 변경을 즉시 반영한다 | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-audio-output-switcher/ |
| F020 | 음악·오디오 | Per-App Volume & EQ (앱별 볼륨·EQ) | 출력 선택기 옆 칩에서 Sound Mixer를 연다; 소리를 내는 앱 목록을 보여 주고 앱별로 볼륨을 낮추거나 음소거한다; 앱별 3밴드 이퀄라이저를 적용하고 앱별로 값을 기억한다; 100%로 둔 앱은 처리하지 않고 조정한 앱만 Core Audio process tap을 거친다; Notchy가 종료되면 탭이 제거되어 모든 앱이 원래 음량으로 돌아간다; 1.0.201부터 Sound Mixer Tab으로 패널에 전용 탭을 둘 수 있다; 볼륨 키는 시스템 볼륨을 그대로 조절한다(1.0.158 도입) | macOS 14.4 이상; 시스템 오디오 녹음(System Audio Recording) 권한 | https://notchy.dev/mac-per-app-volume/ |
| F021 | 음악·오디오 | Per-App Output (앱별 출력 장치) | Sound Mixer에서 앱마다 출력 장치를 지정한다(예: 통화는 AirPods, 음악은 스피커); 지정한 앱만 옮기고 나머지는 시스템 출력에 남는다; 앱별 볼륨·음소거·3밴드 EQ와 함께 쓴다; 한 앱을 두 장치로 동시에 보내지는 못한다; Notchy 종료 시 모든 앱이 시스템 출력으로 돌아간다(1.0.172 도입) | macOS 14.4 이상; 시스템 오디오 녹음 권한 | https://notchy.dev/mac-per-app-audio-output/ |
| F022 | 음악·오디오 | AirPods Battery (AirPods 배터리) | 맥 근처에서 AirPods 케이스를 열거나 연결되면 아일랜드를 펼쳐 배터리 애니메이션을 보여 준다; 노치를 클릭하면 양쪽 이어버드와 케이스 배터리를 각각 보여 준다; 노치 드롭다운의 연결 버튼으로 한 번에 연결한다; 홈페이지 카드 기준 근처 케이스 감지 기능이 있다 | AirPods; 블루투스(Bluetooth) 권한(가이드에는 없음, 도움말 https://notchy.dev/help/airpods-not-detected/ 기준); macOS에서 먼저 페어링 필요 | https://notchy.dev/mac-airpods-app/ |
| F023 | 음악·오디오 | Volume HUD (볼륨 HUD) | 볼륨·밝기·키보드 백라이트·배터리 경고 HUD를 노치(또는 알약)에서 애니메이션 막대로 보여 준다; 설정 › Popups › Volume & Brightness HUD › Replace System HUD를 켜면 macOS 기본 HUD를 숨긴다; Tahoe에서는 볼륨·밝기 키를 직접 받아 값을 바꾸고 자체 HUD를 띄워 Control Center 팝오버가 나오지 않게 한다; 재생·건너뛰기 시 Control Center Now Playing 패널이 아일랜드를 덮지 않게 할 수 있다; 1.0.201부터 Focus 중 볼륨 HUD·밝기 HUD를 각각 숨기는 옵션이 있다; 외장 모니터에서는 알약에 HUD를 띄운다; 끄거나 종료하면 시스템 HUD가 돌아온다 | Replace System HUD에 손쉬운 사용 + 입력 모니터링(Input Monitoring) 권한(도움말은 "미디어 키 가로채기"에 입력 모니터링으로 안내); Touch Bar의 Control Strip 슬라이더는 가로채지 못한다 | https://notchy.dev/mac-volume-hud/ |
| F024 | 음악·오디오 | Mic Mute (마이크 음소거) | 노치의 토글 하나로 CoreAudio를 통해 기본 입력 장치 자체를 음소거한다; Zoom·Meet·Teams·Slack·Discord 등 모든 앱에서 동시에 음소거된다; 음소거 속성이 없는 USB 마이크는 입력 볼륨을 0으로 만들고 해제 시 이전 값을 복원한다; 음소거 상태를 노치에 표시한다; 기능 목록 요약에는 단축키 하나로 음소거한다고 적혀 있다 | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-mic-mute/ |
| F025 | 음악·오디오 | YouTube Music (유튜브 뮤직 연동) | YouTube Music 데스크톱 앱의 API Server 플러그인이 응답하면 시스템 미디어 계층 대신 그 서버에서 위치·길이를 받아 실제로 탐색되는 스크러버를 제공한다; 셔플·반복·👍 상태를 실제 값으로 보여 주고 👍를 앱에 반영한다; 해당 소스일 때만 1초 간격으로 조회한다; 플러그인이 없으면 일반 미디어 컨트롤로 대체한다; 아트워크·동기화 가사·시각화·잠금 화면 가사도 지원한다 | 서드파티 YouTube Music 데스크톱 앱과 API Server 플러그인 활성화; macOS 13 이상 | https://notchy.dev/youtube-music-mac/ |
| F026 | 음악·오디오 | Podcast & Audiobook (팟캐스트·오디오북 컨트롤) | 장편 오디오를 감지하면 이전/다음 버튼을 15초 뒤로/앞으로로 바꾼다; 감지 조건은 알려진 앱(Apple Podcasts, Apple Books, Audible, Overcast, Pocket Casts, Castro, Snipd), 다음/이전이 없다고 보고하는 소스, 20분보다 긴 항목; 건너뛰기 시 스크러버를 즉시 옮긴다; 길이가 없는 라이브 스트림은 시스템 ±15초 명령으로 대체한다; 재생 속도 칩(1×~2×)을 함께 둔다; 재생 카드·잠금 화면·접힌 알약에 같은 컨트롤을 둔다; 설정에서 끌 수 있다 | 브라우저 속도 조절은 F027 조건과 같음 | https://notchy.dev/mac-podcast-controls/ |
| F027 | 음악·오디오 | Playback Speed (재생 속도) | 재생 행의 칩으로 1×, 1.2×, 1.5×, 1.75×, 2× 중 고른다; 현재 재생 중인 플레이어에 적용한다; 브라우저 동영상(Safari, Chrome, Brave, Edge, Vivaldi, Opera, Chromium)은 브라우저의 JavaScript 브리지로 속도를 바꾼다; 먼저 속도를 읽어 와서 성공한 경우에만 칩을 보여 준다 | 브라우저 쪽 "Allow JavaScript from Apple Events" 활성화 + 해당 브라우저에 대한 자동화(Automation) 권한; 확장 프로그램 불필요 | https://notchy.dev/mac-video-speed-controller/ |
| F028 | 타이머·집중 | Pomodoro Timer (뽀모도로 타이머) | 노치에서 집중 세션을 시작하고 남은 시간을 알약에 계속 표시한다; 작업·짧은 휴식·긴 휴식 길이를 사용자가 정한다; 세션이 끝나면 노치가 펼쳐져 휴식 시작·5분 연장·다음 세션으로 건너뛰기 중 고르게 한다; 긴 휴식은 설정한 주기에 맞춰 온다; 세션 통계를 볼 수 있다(홈페이지 카드 기준 연속 기록·7일 집중 차트·세션 연결); 1.0.191부터 원클릭 빠른 시작 버튼·사용자 단축키로 집중을 시작하고 Pomodoro Only로 일반 타이머를 숨긴다; Now Playing 컨트롤이 타이머 옆에 남는다; 도움말상 Block Apps While Focusing(집중 중 지정 앱 숨기기, 종료는 안 함)과 Continue Automatically(휴식·다음 세션 자동 시작) 옵션이 있다(https://notchy.dev/help/pomodoro-block-apps/) | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-pomodoro-timer/ |
| F029 | 타이머·집중 | Focus Sounds (집중용 배경음) | 설정 → Timer에서 Focus Sounds를 켠다; Timer 탭이나 Home 카드에서 빗소리·브라운 노이즈·바람·파도 중 하나를 재생하고 슬라이더로 음량을 맞춘다; 소리는 파일 반복이 아니라 실시간 합성이며 오프라인으로 동작한다; 한 번에 하나만 재생한다; Stop Sounds When Focus Ends를 켜면 뽀모도로 종료·중지 시 멈춘다(일시정지 중에는 계속 재생); 서서히 커지며 시작하고 맥이 잠들거나 출력 장치가 바뀌면 멈춘다(1.0.195 도입, 기본 꺼짐) | 없음 | https://notchy.dev/mac-focus-sounds/ |
| F030 | 타이머·집중 | Typing Sounds (타이핑 소리) | 설정 → Capture에서 Typing Sounds를 켜면 키를 누를 때마다 클릭음을 낸다; Mechanical·Typewriter·Soft·Blip·Beep 5가지 합성음과 사용자 오디오 파일(My Sound) 중 고른다; 음높이를 조금씩 바꾸고 Space·Return은 더 큰 소리, Typewriter는 Return에 벨을 울린다; 모든 앱·선택한 앱만·선택한 앱 제외 중 적용 범위를 고른다; 사용자 단축키로 일시정지·재개한다; 듣기 전용 이벤트 탭을 써서 입력을 지연·변경하지 않는다; 비밀번호 칸(보안 입력)에서는 소리를 내지 않는다; 키 종류만 확인하고 내용은 저장하지 않는다(1.0.200 도입, 기본 꺼짐) | 입력 모니터링 권한 | https://notchy.dev/mac-typing-sounds/ |
| F031 | 타이머·집중 | Countdown & Stopwatch (카운트다운·스톱워치) | 타이머 탭의 프리셋을 눌러 바로 시작한다; 실행 중 1분 추가·일시정지·초기화를 한다; 남은 시간을 노치에 작게 표시하고 전체 화면 앱 위에도 보인다; 같은 화면에서 스톱워치(시작·일시정지·초기화)를 쓴다; 단축키를 지정할 수 있다; 끝나면 노치가 종료 아일랜드로 펼쳐지고 선택적으로 소리를 낸다; 도움말상 Repeat Timer(같은 길이로 자동 반복, 자리 비움 시 중단)와 Controls on Hover 옵션이 있다(https://notchy.dev/help/repeat-timer/) | 없음 | https://notchy.dev/mac-countdown-timer/ |
| F032 | 타이머·집중 | Set a Timer on Mac (맥 타이머 사용법 안내) | macOS 기본 Clock 앱·Siri로 타이머 거는 법을 설명하는 안내 글이다; Notchy 쪽 동작은 1·2·3·5·10·25분 프리셋 또는 드래그로 길이 지정, 실행 중 호버로 일시정지·1분 추가·중지, 스톱워치·뽀모도로 모드 병행; 잠금 화면 위젯에도 실행 중 타이머를 보여 줄 수 있다 | macOS 13 이상, Intel·Apple silicon | https://notchy.dev/how-to-set-a-timer-on-mac/ |
| F033 | 타이머·집중 | Focus Mode (집중 모드) | 노치를 열면 Focus 카드에 현재 켜진 모드와 설정된 모드 목록이 보인다; 모드를 고르면 해당 모드용 Apple 단축어("Set Focus" 동작 하나)를 실행해 전환한다; 단축어는 이름으로 자동 매칭하며 설정 › Notifications › Focus Modes에서 모드별로 지정한다; 단축어가 없는 모드는 시스템 설정을 연다; Focus가 켜져 있으면 노치 주변에 아이콘이나 빛으로 표시한다; Focus 중에는 다운로드·기기 연결·업데이트 같은 낮은 우선순위 아일랜드를 억제하고 볼륨·밝기·카페인·배터리 부족 알림은 계속 보여 준다; macOS를 통해 바꾸므로 iCloud로 다른 기기와 동기화된다 | 전체 디스크 접근(Full Disk Access): 활성 Focus 이름과 모드 목록 읽기에 필요, 없으면 "켜짐 여부"만 안다; 모드 전환에는 사용자가 만든 Apple 단축어 필요 | https://notchy.dev/mac-focus-mode/ |
| F034 | 타이머·집중 | Activity Rings (활동 링) | 커서 이동 거리(Move)·키 입력 수(Type)·실제 입력이 이어진 시간(Focus)을 링 세 개로 노치에 표시한다; 링마다 일일 목표를 정한다; 목표를 모두 채운 날이 이어지면 연속 기록이 쌓인다; 누적 기록이 이정표를 넘으면 짧은 아일랜드를 한 번만 띄운다; 키 입력은 횟수만 세고 내용은 저장하지 않는다; 일일 합계는 로컬 SQLite에 저장하고 업로드·동기화하지 않는다; Apple Watch·HealthKit 데이터는 읽지 않는다 | 키·마우스 입력 감지 권한(입력 모니터링 추정)은 가이드에 명시 없음(자료 없음) | https://notchy.dev/mac-activity-tracker/ |
| F035 | 타이머·집중 | Screen Time (앱 사용 시간) | Activity 탭의 Screen Time 카드에 오늘·이번 주·전체 기간의 총 사용 시간, 사용한 날 기준 일평균, 상위 5개 앱을 보여 준다; 7일 막대 차트에 날마다 상위 3개 앱을 색으로, 나머지는 Other로 묶는다; 입력이 5분 없으면 집계를 멈춘다; 잠금 화면·화면 보호기·Notchy 자신은 집계하지 않는다; 웹사이트별 집계는 하지 않고 앞에 있는 앱에 시간을 준다; 로컬 저장, 언제든 끌 수 있다(1.0.178 도입) | 자료 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-screen-time/ |
| F036 | 타이머·집중 | Break Reminders (휴식 알림) | 기본값으로 20분마다 눈 휴식(20-20-20 규칙), 1시간마다 자세 휴식을 노치 아일랜드로 알린다; 아일랜드에 무엇을 할지 문구로 적는다; 두 간격을 각각 조절하거나 끈다; 화면 잠금·Focus·화면 공유나 녹화 중에 도래한 알림은 쌓아 두지 않고 버린다; 간격보다 오래 자리를 비우면 타이머를 다시 시작한다; 화면을 가리거나 강제로 쉬게 하지 않는다; 뽀모도로와 별개로 하루 종일 동작한다; 도움말에는 Look Away·Stand Up 외에 Drink Water 알림도 나온다(https://notchy.dev/help/pomodoro-block-apps/) | macOS 13 이상 | https://notchy.dev/mac-break-reminder/ |
| F037 | 타이머·집중 | Keep Awake (잠자기 방지) | 노치를 내려 커피잔(Caffeine) 아이콘을 누르면 맥이 잠들지 않는다; 길게 누르면 지속 시간이나 특정 시각(예: 오후 6:30까지)을 고르고 그때 자동으로 꺼진다; 드롭다운에서 강제 깨움 상태를 확인한다; 설정 → Caffeine의 Stay Awake With the Lid Closed를 켜면 덮개를 닫아도 깨어 있게 시스템 전원 설정을 바꾼다; macOS caffeinate API를 쓴다 | 덮개 닫힘 옵션은 관리자 비밀번호 1회 입력 필요 | https://notchy.dev/mac-keep-awake-app/ |
| F038 | 일정·할 일·메모 | Calendar (캘린더) | 노치에서 다가오는 일정과 한 달 달력을 펼쳐 보여 준다; EventKit으로 macOS 캘린더의 모든 일정(iCloud, 인터넷 계정에 추가한 Google·Microsoft 365·Exchange)을 읽는다; .ics 링크·CalDAV 계정을 앱 안에서 읽기 전용으로 구독한다; 1.0.200부터 메뉴 막대에 "Standup in 12m"·"12m left" 형식의 다음 회의 표시(제목 숨김 가능, 클릭 시 Calendar 탭)와 캘린더 열기 단축키가 있다; 1.0.201부터 Manage Calendar Events로 빠른 일정 날짜 미리보기·쓰기 가능한 Apple 캘린더에 저장·본인의 단일 일정 편집·삭제를 한다(공유·반복 일정은 Calendar 앱으로 연다); Calendar with Due Tasks로 그날 일정 옆에 마감 미리 알림을 보여 준다; 도움말상 다음 회의까지 카운트다운을 아일랜드에 고정할 수 있다 | 캘린더 접근 권한; .ics 비밀 주소·CalDAV 비밀번호는 키체인 저장; Notchy 서버를 거치지 않음 | https://notchy.dev/mac-menu-bar-calendar/ |
| F039 | 일정·할 일·메모 | Google & Outlook Calendars (구글·아웃룩 캘린더) | 시스템 설정 → 인터넷 계정에 Google·Microsoft 365를 캘린더 켬으로 추가하면 해당 일정이 Notchy에 나온다(앱 안에서 Google·Microsoft 로그인은 하지 않음); 설정 → Calendar → Connect Another Calendar에서 .ics 링크나 CalDAV 계정을 읽기 전용으로 구독하고 반복 일정은 앞으로 90일치를 펼친다; 표시할 캘린더를 고른다; 다음 일정 카운트다운을 보여 준다; 화상회의 링크가 있는 일정 카드에 Join 버튼을 둔다; Todoist 작업을 Apple Reminders 옆에 보여 주고 Quick Add 저장 위치를 고른다; Microsoft To Do는 지원하지 않는다 | 캘린더 접근 권한; macOS 인터넷 계정 등록; Todoist 연동 시 Todoist 토큰(키체인 저장) | https://notchy.dev/google-calendar-mac-menu-bar/ |
| F040 | 일정·할 일·메모 | Full-Screen Meeting Reminder (전체 화면 회의 알림) | 설정한 시간(분) 전에 연결된 모든 화면을 어둡게 덮고 회의 제목·시간·캘린더 색을 보여 준다; Return은 회의 링크(Zoom·Meet·Teams 등) 열기, Escape는 닫기, Snooze는 1분 뒤 다시 표시; 알림 시점에 맥이 잠들어 있었으면 시작 후 5분까지는 "시작 후 N분" 형태로 표시한다; 화상회의 링크가 있는 일정만으로 제한할 수 있다; 대안으로 참여하거나 닫을 때까지 노치에 남는 Join 아일랜드를 쓸 수 있다; Preview로 미리 본다; 기본 꺼짐(1.0.179 도입) | 캘린더 접근 권한 | https://notchy.dev/mac-meeting-reminder/ |
| F041 | 일정·할 일·메모 | Reminders (미리 알림) | 노치의 Reminders 탭에서 한 줄 입력 후 Return으로 Apple 미리 알림에 추가한다; EventKit으로 읽고 써서 iCloud로 다른 기기와 동기화된다; 미완료 항목과 곧 마감인 항목을 보여 주고 기한 지난 항목을 강조한다; 1.0.195부터 자연어 날짜("tomorrow at 9 call Alex")를 해석해 날짜를 채우고 추가 전에 확인하게 한다 | 미리 알림 접근 권한; iCloud 동기화는 Apple 계정 | https://notchy.dev/mac-reminders-app/ |
| F042 | 일정·할 일·메모 | To-Do List (할 일 목록) | 노치를 열고 할 일을 입력한 뒤 Return으로 추가한다; 체크한 항목은 하루 뒤 자동으로 사라진다; 패널을 닫아도 작성 중이던 초안을 유지한다; 최대 200개; 이 맥의 설정에만 저장하고 동기화하지 않는다(1.0.172 도입, 기본 켜짐) | 권한 불필요 | https://notchy.dev/mac-todo-list/ |
| F043 | 일정·할 일·메모 | Quick Notes (빠른 메모) | 노치에 마우스를 올리고 바로 입력해 임시 메모를 남긴다; 노치를 닫아도 메모를 보관했다가 다시 열면 보여 준다; 로컬 저장; 1.0.201부터 Recover Notes Drafts로 저장 안 된 메모를 재시작 후 복구하고, Capture Checklist Tasks로 체크 안 된 체크리스트 줄을 Notchy Tasks로 복사한다(둘 다 기본 꺼짐) | 없음 | https://notchy.dev/mac-quick-notes-app/ |
| F044 | 일정·할 일·메모 | World Clock (세계 시계) | 설정 → Home에서 도시를 추가하고 World Clock 카드를 켠다; 지정한 순서로 각 도시의 현지 시간을 보여 준다; 칸 높이에 따라 2개 또는 최대 4개를 표시한다; 분 단위로 갱신하고 노치가 닫히면 갱신을 멈춘다; 일광 절약 시간은 시스템 시간대 DB를 따른다; Home 카드 배치(순서, 1~3열)를 사용자가 정한다 | 없음 | https://notchy.dev/mac-world-clock/ |
| F045 | 클립보드·텍스트 | Clipboard History (클립보드 기록) | 노치를 아래로 쓸거나 클릭하면 복사 기록 선반이 열린다; 텍스트·링크·이미지·색상 코드를 미리보기로 보여 준다; 텍스트·파일 이름·OCR로 읽은 단어로 검색한다; 항목을 고정하면 맨 위에 뜨고 개수 제한·Clear·재시작 후에도 남는다(1.0.172부터 재시작 유지); 1.0.179부터 Keep History After Quitting(기본 켜짐)으로 기록을 Application Support에 소유자 전용으로 저장하고 끄면 메모리에만 둔다; 1.0.179부터 저장한 클립을 사용자 이름의 목록으로 묶는다; 1.0.179부터 저장한 텍스트 클립과 목록을 iCloud로 맥 사이에 동기화할 수 있다(기본 꺼짐, 이미지·전체 기록은 제외); 1.0.200부터 새 복사 시 클릭음을 내는 Capture Sound(기본 꺼짐); 일정 시간 뒤·잠자기·잠금 시 기록 자동 삭제; 비밀번호 관리자가 표시한 concealed·transient 복사와 무시 목록 앱의 복사는 기록하지 않는다; 홈페이지 카드 기준 링크·색상·이메일에 맞는 스마트 동작, 연속 복사 묶기, 선택 시 앞 앱에 자동 붙여넣기가 있다 | 동기화는 iCloud 계정; 자동 붙여넣기 권한은 가이드에 명시 없음(F046 기준 손쉬운 사용 필요 추정) | https://notchy.dev/mac-clipboard-manager/ |
| F046 | 클립보드·텍스트 | Paste as Plain Text (서식 없이 붙여넣기) | 설정에서 지정한 전역 단축키나 ⌘K 팔레트의 "Paste as Plain Text"로 실행한다; 한 번만 평문 사본으로 바꿔 붙여넣고 원래 서식 있는 클립보드를 복원한다(그 사이 새로 복사하면 새 것이 우선); 수정키가 떼어질 때까지 기다렸다가 ⌘V를 보낸다; 임시 사본은 transient로 표시해 다른 클립보드 관리자와 자체 기록에 남지 않게 한다; 읽을 수 없는 구형 형식은 건너뛰고 텍스트 대체본을 만든다; 모든 붙여넣기를 평문으로 바꾸는 모드는 없다(1.0.178 도입) | 손쉬운 사용 권한(⌘V 키 입력 전송) | https://notchy.dev/mac-paste-plain-text/ |
| F047 | 클립보드·텍스트 | Clean Links (추적 파라미터 제거) | 복사한 링크에서 utm_·fbclid·gclid·YouTube si 같은 추적 파라미터를 찾는다; 기본은 클립보드 기록에서 한 번 눌러 정리하는 동작을 제안하고, Clean Automatically를 켜면 복사 즉시 바꾼다; 페이지 내용을 바꾸는 파라미터(영상 ID, 검색어)와 애매한 파라미터는 남긴다; 전역 목록 외에 YouTube·X·Instagram·Facebook·Spotify·Reddit·Amazon·eBay·LinkedIn·Etsy 등 사이트별 규칙을 둔다; 시스템 클립보드를 일정 시간 미사용·잠자기·화면 잠금 시 비우는 옵션이 있다(기본 꺼짐, Notchy 기록은 유지); 1Password·Apple Passwords·Keychain Access·Bitwarden·KeePassXC·LastPass·Enpass 복사를 무시하고 무시 앱을 추가할 수 있다(1.0.172 도입) | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-clean-links/ |
| F048 | 클립보드·텍스트 | OCR & Text Capture (이미지 글자 인식) | Clipboard 탭에서 이미지 항목을 한 번 누르면 Apple Vision으로 기기 안에서 글자를 인식해 선택·복사 가능한 텍스트로 만든다; 인식한 단어를 클립보드 검색 색인에 넣어 나중에 단어로 스크린샷을 찾는다; 노치에서 한 번 눌러 macOS 영역 선택기로 캡처하면 결과가 클립보드와 선반(PNG)에 동시에 들어간다; 네트워크 요청 없음 | 캡처 기능은 화면 기록 권한(F052·F063 기준); OCR 자체는 권한 언급 없음 | https://notchy.dev/mac-ocr-app/ |
| F049 | 파일·선반 | File Drop Shelf (파일 드롭 선반) | 파일을 끌고 노치로 가져가면 노치가 펼쳐져 선반이 된다; 이미지·문서·URL·텍스트 조각을 보관하고 Space나 앱을 바꾼 뒤 끌어낸다; 여러 개를 한꺼번에 담는다; 쓰지 않을 때는 노치 안으로 접힌다; 선반 항목은 앱을 종료·재실행해도 남는다; 스크린샷이 자동으로 선반에 올라온다; 둘 이상 선택해 zip으로 묶거나 압축을 푼다 | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-file-drop-app/ |
| F050 | 파일·선반 | AirDrop From the Shelf (선반에서 에어드롭) | 선반에 올린 파일을 시스템 AirDrop으로 iPhone·iPad·다른 맥에 보낸다; 시스템에 보이는 대상이 그대로 나온다; 홈페이지 카드 기준 노치에 붙은 전송 애니메이션과 성공·실패 피드백을 보여 준다; 같은 파일을 압축·변환·Quick Look·드래그로도 내보낸다 | AirDrop 사용 가능 환경(Wi-Fi·Bluetooth 켜짐); 계정 불필요 | https://notchy.dev/mac-airdrop-shelf/ |
| F051 | 화면 캡처·회의 | Screenshot Shelf (스크린샷 선반) | 노치에서 한 번 누르면 macOS 영역 선택기가 열린다; 결과를 클립보드에 넣고 동시에 선반에 실제 PNG 파일로 올린다; 시스템 단축키로 찍은 스크린샷도 노치에 끌어 쓸 수 있는 아일랜드로 자동 등록한다; 캡처를 OCR로 보내 글자를 클립보드에 넣는다; 선반에서 압축·크기 조절·Quick Look을 한다 | 화면 기록 권한; 시스템 스크린샷을 선반으로 가져오는 Screenshot to Shelf는 파일 및 폴더(Files & Folders) 권한(도움말 https://notchy.dev/help/permissions-notchy-needs/) | https://notchy.dev/mac-screenshot-tool/ |
| F052 | 화면 캡처·회의 | Scrolling Screenshot (스크롤 캡처) | ⌘K 팔레트에서 Capture Scrolling Screenshot을 고르고 영역을 지정한다; 노치를 비켜 두고 영역 위에 실제 스크롤 이벤트를 보내며 반복 캡처한다; 겹치는 행을 찾아 하나의 긴 이미지로 이어 붙인다; 페이지가 더 이상 움직이지 않으면 멈추고 무한 피드는 30장에서 자른다; 결과를 클립보드·선반(PNG)·스크린샷 편집기로 보낸다; 브라우저와 손쉬운 사용을 노출하지 않는 앱에서도 동작한다(1.0.172 도입) | 화면 기록 권한 | https://notchy.dev/mac-scrolling-screenshot/ |
| F053 | 화면 캡처·회의 | Screenshot Markup (스크린샷 주석) | 설정 › Notifications의 Annotate After Capture를 켜면 캡처 직후 편집기가 열린다; 시스템 캡처(⇧⌘4/⇧⌘5)는 Screenshot to Shelf가 켜져 있어야 적용된다; 도구는 화살표·사각형·타원·직선·형광펜·텍스트·가림(단색 블록), 7색·3가지 굵기, ⌘Z 실행 취소/다시 실행; 주석은 도형 데이터로 두었다가 원본 해상도로 합친다; 저장하면 원본 옆에 "annotated" 사본을 만들고 선반에 올린다(원본 보존); 복사한 아무 이미지에 ⌘K의 "Annotate Screenshot"을 실행할 수 있다; 스크롤 캡처 문서에는 워터마크 적용도 언급된다 | 화면 기록 권한(캡처 시); 시스템 캡처 연동은 Screenshot to Shelf(파일 및 폴더 권한) 필요 | https://notchy.dev/mac-screenshot-annotation/ |
| F054 | 클립보드·텍스트 | AI Clipboard (AI 문장 다듬기) | 클립보드 기록 행에 마우스를 올리고 교정·격식체·친근체·간결하게·요약·글머리표 6가지 중 하나를 고른다; Apple Intelligence의 온디바이스 모델로 처리하고 결과를 클립보드에 넣는다(원본은 기록에 남김, 중복 항목 생성 안 함); 이미 종료한 앱에서 복사한 예전 항목에도 적용한다; 각 동작을 ⌘K 팔레트에서 현재 클립보드에 실행한다; 쓸 수 없는 환경이면 빠진 조건을 알려 준다 | macOS 26 이상 + Apple Intelligence 지원 맥 + Apple Intelligence 켜짐; API 키·계정 불필요 | https://notchy.dev/mac-ai-clipboard/ |
| F055 | 파일·선반 | Image Converter (이미지 변환) | 이미지를 선반에 올리고 변환을 눌러 JPG·PNG·TIFF·PDF(홈페이지 기준 HEIC 포함) 중 고른다; 변환본을 만들어 바로 끌어낸다; 이미지를 한 장짜리 PDF로 감싼다; Apple ImageIO로 오프라인 처리한다; PNG·TIFF·PDF는 무손실, JPEG·HEIC는 고품질 인코딩 | 없음 | https://notchy.dev/mac-image-converter/ |
| F056 | 파일·선반 | Zip & Unzip (압축·해제) | 선반에서 파일을 골라 압축하면 zip이 선반에 생기고 바로 끌어낸다; macOS ditto를 써서 __MACOSX 폴더 없이 만든다; 압축 파일을 풀면 내용이 선반에 올라온다; zip 외 rar·7z 등은 다루지 않는다 | 없음 | https://notchy.dev/mac-zip-unzip/ |
| F057 | 파일·선반 | Merge PDFs (PDF 합치기) | 선반에 PDF·이미지를 올리고 둘 이상 선택하면 Merge 버튼이 나타난다; 선반 타일 순서(왼쪽→오른쪽)대로 페이지를 합친다; 이미지는 한 장당 한 페이지로 섞어 넣는다; PDFKit으로 로컬 처리하고 기존 페이지는 재렌더링하지 않는다; 결과는 첫 문서 이름의 "(merged).pdf" 새 파일로 임시 폴더에 쓰고 선반에 올린다; 원본은 건드리지 않으며 페이지 제한이 없다 | 없음 | https://notchy.dev/mac-pdf-merge/ |
| F058 | 파일·선반 | Image Compressor (이미지 용량 줄이기) | 선반의 이미지 타일을 오른쪽 클릭해 Compress to에서 200 KB·500 KB·1 MB·2 MB·5 MB 중 고른다(원본보다 작은 값만 표시); 목표 이하가 될 때까지 품질을 낮춰 인코딩한다; 여러 이미지를 선택해 한 번에 처리한다; 별도 메뉴로 긴 변 기준 크기 줄이기를 한다(원본보다 작은 프리셋만); 결과는 새 파일로 선반에 두고 원본은 보존한다; Image I/O로 오프라인 처리 | macOS 13 이상 | https://notchy.dev/mac-image-compressor/ |
| F059 | 파일·선반 | Video to GIF (동영상→GIF) | .mov·.mp4·.m4v를 선반에 올리고 타일을 오른쪽 클릭해 GIF를 고른다; 앞 8초를 초당 12프레임, 긴 변 최대 480px로 변환한다(비율 유지); 결과를 원본 옆 선반에 둔다; AVFoundation으로 로컬 처리, 워터마크 없음 | 없음 | https://notchy.dev/mac-gif-converter/ |
| F060 | 파일·선반 | Download Progress (다운로드 완료 알림) | 다운로드 폴더를 파일 시스템 수준에서 감시한다; .crdownload·.download·.part 같은 임시 파일은 무시하고 파일이 안정되면 한 번만 "Download finished" 아일랜드를 띄운다; Reveal 버튼으로 Finder에서 파일을 선택해 연다; 모든 브라우저에 동작하며 확장 프로그램이 필요 없다; Focus 중에는 이 알림이 억제된다(F033) | ~/Downloads 폴더 접근(권한 언급은 없음) | https://notchy.dev/mac-download-progress/ |
| F061 | 파일·선반 | Eject Drives (드라이브 꺼내기) | 드라이브가 마운트되면 Eject 버튼이 있는 아일랜드를 띄운다; 누르면 꺼내고 실제로 언마운트가 끝난 뒤 "Safe to disconnect"를 표시한다 | 외장 USB 드라이브 | https://notchy.dev/mac-eject-usb-drive/ |
| F062 | 화면 캡처·회의 | Screen Recording (화면 녹화) | 노치에서 한 번 눌러 macOS 기본 녹화기(⇧⌘5와 같은 screencapture)를 시작한다; 녹화 중 경과 시간을 노치에 표시하고 같은 컨트롤로 멈춘다; 영역 선택(선택기의 동영상 탭)·창·전체 화면 중 기본 모드를 설정한다; 녹화 시작 전에 패널을 닫아 화면에 나오지 않게 한다; 파일 저장 위치·형식은 macOS를 따르며 재인코딩하지 않는다; 워터마크·시간 제한 없음 | 화면 기록 권한(시스템 녹화기 권한 프롬프트) | https://notchy.dev/mac-screen-recorder/ |
| F063 | 화면 캡처·회의 | QR Code Scanner (화면 QR 스캔) | 설정에서 Scan QR Code Button을 켜면 패널 헤더에 버튼이 생긴다(⌃⌥K 팔레트로도 실행); 십자선으로 코드 주변을 드래그하고, 길게 누르면 화면 전체를 읽는다; Apple Vision으로 QR과 기타 바코드를 기기 안에서 해독하고 내용을 클립보드에 복사한다; 웹·메일·전화·FaceTime·SMS 링크에만 Open 버튼을 주고 Wi-Fi·vCard 등은 복사만 한다; 한 캡처에 코드가 여러 개면 개수를 알려 준다; 임시 캡처는 바로 삭제한다; 웹캠 스캔은 하지 않는다(1.0.186 도입) | 화면 기록 권한 | https://notchy.dev/mac-qr-code-scanner/ |
| F064 | 시스템·하드웨어 | System Monitor (시스템 모니터) | 노치 헤더의 게이지를 누르면 CPU 사용률, Activity Monitor 방식의 메모리 압력(active+wired+compressed), 실시간 네트워크 처리량을 보여 주는 플라이아웃이 열린다; 플라이아웃이 열려 있을 때만 샘플링한다; 1.0.201부터 Network Traffic History로 최대 1년치 송수신 합계를 저장한다(F065) | 없음(가이드에 권한 언급 없음) | https://notchy.dev/mac-system-monitor/ |
| F065 | 시스템·하드웨어 | Data Usage History (데이터 사용량 기록) | 설정 → Connectivity에서 Network Traffic History를 켜면 그때부터 물리 네트워크 인터페이스의 바이트 수만 기록한다; 오늘·이번 주·이번 달·올해 합계를 다운로드·업로드로 나눠 보여 준다; 일별 합계를 로컬 파일에 최대 1년 보관하고 버튼으로 지운다; 잠든 시간·샘플 사이 시간은 추정하지 않고 빼며 실제 관측한 분을 표시한다; 앱별·사이트별 집계와 데이터 한도 경고는 없다(1.0.201 도입, 기본 꺼짐) | 없음 | https://notchy.dev/mac-network-usage-monitor/ |
| F066 | 앱 관리·위젯·유지보수 | App Updater (앱 업데이트 목록) | 노치의 Packages 탭(기본 켜짐)에서 Homebrew cask·formula, Mac App Store 앱, Sparkle로 업데이트하는 앱의 업데이트를 한 목록으로 보여 준다; Homebrew 항목은 패널에서 하나씩 또는 전부 업그레이드한다; App Store 항목은 App Store 페이지를, Sparkle 항목은 해당 앱을 열어 그 앱의 업데이터에 넘긴다; 탭을 열거나 Refresh를 누를 때만 확인하고 백그라운드 확인은 하지 않는다; 자동 설치는 하지 않는다(1.0.172 도입) | Homebrew 항목은 사용자가 설치한 brew 필요(Notchy가 설치하지 않음); App Store 항목은 mas CLI 필요(brew install mas); 인터넷 연결 | https://notchy.dev/mac-app-updater/ |
| F067 | 시스템·하드웨어 | CPU Temperature (CPU 온도) | SMC에서 가장 뜨거운 CPU 센서 값을 읽어 노치의 시스템 플라이아웃에 CPU·GPU·메모리·네트워크와 함께 보여 준다; 설정 토글로 °C/°F를 바꾼다; 센서를 보고하지 않는 맥에서는 행을 숨긴다 | Apple silicon·Intel; 센서 보고 여부에 따라 다름 | https://notchy.dev/mac-cpu-temperature/ |
| F068 | 앱 관리·위젯·유지보수 | App Uninstaller (앱 삭제) | Packages 탭의 Uninstall 모드에서 앱을 고르면 ~/Library의 Application Support·캐시·환경설정·컨테이너·스크립트·저장 상태·웹 데이터·쿠키·로그·런치 에이전트를 종류별로 나열한다; 지원 파일을 먼저, 앱을 마지막으로 휴지통에 옮긴다(영구 삭제 안 함, Put Back 가능); 번들 ID·이름이 정확히 일치하는 항목만 고른다; 실행 중이거나 로그인 도우미가 돌고 있는 앱은 건드리지 않는다; root 소유 App Store·설치 프로그램 앱은 Finder 방식으로 macOS에 넘긴다; 이미 지운 앱의 잔여 파일은 찾지 않는다(1.0.178 도입) | root 소유 앱 삭제 시 관리자 비밀번호 | https://notchy.dev/mac-app-uninstaller/ |
| F069 | 기타 | Desktop Pet (데스크톱 펫) | 화면 아래쪽을 걸어 다니는 픽셀 펫을 입양한다(23종, 1.0.198부터 일러스트 캐릭터 52종 추가); 돌아다니기·낮잠·커서 쫓기를 한다; CPU 과열·스로틀링·배터리 부족·충전기 연결·뽀모도로 실행·동영상 재생·음악 재생에 반응하고 가장 급한 상태를 우선한다; 먹이·놀기·쓰다듬기·재우기로 포만감·에너지·친밀도 수치를 관리하고 매일 돌봄 연속 기록(3~365일 이정표)을 센다; 품종별 1/50 확률 이로치, 숨은 발견 16개, 10월·12월 한정 모자, 순간 공유 카드; 1.0.197부터 펫 게임(물어오기·기억력)·창 제목 표시줄 타기·다른 디스플레이 방문·밤잠(각각 기본 꺼짐); 1.0.199부터 낚시·생일·명절·성장·일일 퀘스트(기본 꺼짐); Apple silicon 맥북을 기울이면 펫이 낮은 쪽으로 미끄러진다; 고정하면 한 곳에 머문다; 화면이 잠들거나 잠기면 애니메이션·타이머·모션 센서를 멈추고 저전력 모드에서 애니메이션을 멈춘다; 펫 백업·복원 | 기울이기 기능은 Apple silicon 맥북의 모션 센서 필요; 그 외 Intel 지원; 1.0.178 도입 | https://notchy.dev/mac-desktop-pet/ |
| F070 | 시스템·하드웨어 | Battery Charge Limit (충전 한도) | Limit Charging을 켜고 50~100% 사이 한도를 정하면 어댑터 연결 상태에서 그 이상 충전하지 않는다; Sailing Mode는 한도 도달 후 사용자가 정한 만큼(최대 20%p) 내려간 뒤에 충전을 다시 시작한다; Automatic Discharge는 한도보다 높은 상태로 연결하면 어댑터를 우회해 배터리로 돌다가 한도까지 내려가게 한다; Top Up은 한 번 100%까지 충전한 뒤 한도로 돌아간다; 처음 켤 때 SMC 접근용 root 도우미를 설치하고 끄거나 삭제하면 도우미를 제거하고 정상 충전을 복원한다 | 관리자 비밀번호 1회(root 헬퍼 설치); MacBook(배터리 탑재 기종); Intel·Apple silicon, macOS 13 이상 | https://notchy.dev/mac-battery-charge-limit/ |
| F071 | 시스템·하드웨어 | Battery Health (배터리 상태) | 노치를 조작하거나 충전기를 꽂으면 배터리 알약이 펼쳐져 충전량과 충전 상태를 보여 준다; 다른 문서(F064·F072) 기준 사이클 수·최대 용량을 보여 준다; AirPods 케이스·각 이어버드·블루투스 기기 배터리를 함께 보여 준다; 내장 충전 한도 기능(F070)과 연결된다 | 배터리 탑재 맥 | https://notchy.dev/mac-battery-health-app/ |
| F072 | 시스템·하드웨어 | Battery Alerts (배터리 알림) | 사용자가 정한 낮은 배터리 비율에서 아일랜드를 띄우고 선택적으로 소리를 낸다; 사용자가 정한 완충 기준(예: 80%)에 도달하면 Full Charge 알약을 띄운다; 충전기 연결 시 짧은 충전 아일랜드를 띄운다; 마우스·키보드·트랙패드·AirPods가 10% 아래로 내려가면 경고한다; 저전력 모드가 켜지면 아일랜드로 알린다; 배터리 수준을 색으로 구분한다; 충전 동작 자체는 바꾸지 않는다 | 배터리 탑재 맥; 주변기기 경고는 배터리 값을 보고하는 블루투스 기기 | https://notchy.dev/mac-battery-notifications/ |
| F073 | 시스템·하드웨어 | Device Batteries (주변기기 배터리) | Magic Mouse·Magic Keyboard·Magic Trackpad와 배터리를 보고하는 다른 블루투스 입력 장치의 충전량을 아이콘과 함께 노치에 보여 준다; 연결된 iPhone·iPad도 기기 이름으로 같은 줄에 보여 준다; 제품명으로 기기별 아이콘을 고른다; 기본 10%(변경 가능)에서 저전력 아일랜드를 한 번 띄우고 10%p 이상 충전되기 전에는 다시 띄우지 않는다; 느린 주기로 읽는다; 홈페이지 카드 기준 서드파티 블루투스 헤드폰·스피커도 포함한다 | 블루투스 기기; 블루투스 권한 언급 없음(자료 없음) | https://notchy.dev/mac-device-battery/ |
| F074 | 시스템·하드웨어 | Brightness HUD (밝기 HUD) | 밝기 키를 가로채 화면 중앙 대신 노치에서 애니메이션 막대로 밝기를 보여 준다; 볼륨·키보드 백라이트·배터리 경고에도 같은 형식을 쓴다; 설정에서 macOS 기본 오버레이를 숨긴다(선택, 끄거나 종료하면 복원); 1.0.201부터 Focus 중 밝기 HUD를 숨기는 옵션이 있다 | 기본 HUD 숨기기에는 F023과 같은 권한(손쉬운 사용·입력 모니터링) 필요로 보임 | https://notchy.dev/mac-brightness-hud/ |
| F075 | 시스템·하드웨어 | External Display Brightness (외장 모니터 밝기) | Apple silicon의 IOAVService를 통해 DDC/CI로 서드파티 모니터 밝기를 조절한다; 기존 밝기 키(F1·F2)와 노치 HUD가 지금 보고 있는 외장 모니터에 적용된다; 외장 밝기도 볼륨·내장 밝기와 같은 노치 아일랜드로 보여 준다; 기본 꺼짐이며 모니터가 DDC에 응답하면 켜진다 | Apple silicon; DDC/CI 지원 외장 모니터(일부 허브·KVM 미지원) | https://notchy.dev/mac-external-display-control/ |
| F076 | 시스템·하드웨어 | Monitor Colour Temperature (모니터 색온도) | DDC로 모니터 자체의 화이트 포인트를 Native·sRGB·5000K·6500K·7500K·9300K 중 하나로 바꾼다; 신호에 색을 입히지 않고 패널 설정을 바꾸므로 입력 전환·재부팅 후에도 유지된다; 같은 패널에서 밝기·명암·입력 소스·주사율을 함께 조절한다; 모르는 프리셋은 모니터가 무시하고 DDC를 노출하지 않는 모니터는 제어 불가로 표시한다 | Apple silicon + DDC/CI 지원 모니터; 권한·커널 확장 불필요 | https://notchy.dev/mac-monitor-color-temperature/ |
| F077 | 시스템·하드웨어 | Refresh Rate Switcher (주사율 전환) | 현재 해상도에서 가능한 주사율(예: 60·120·144Hz)만 메뉴로 보여 주고 고르면 바꾼다; CoreGraphics 디스플레이 모드 전환이라 내장·외장 화면 모두 적용된다; 선택한 값은 재부팅 후에도 유지된다; 가능한 값이 하나뿐인 화면은 메뉴를 숨긴다 | 권한 불필요 | https://notchy.dev/mac-refresh-rate-switcher/ |
| F078 | 시스템·하드웨어 | Keyboard Backlight (키보드 백라이트) | ⌘K 팔레트의 "Keyboard Backlight Up/Down/Off"나 조명 키로 노치에 끌어서 조절하는 슬라이더 아일랜드를 띄운다; Control Center와 같은 CoreBrightness 클라이언트로 값을 바꾸고 유지한다; 완전히 끌 수 있다; 백라이트가 없는 맥에서는 컨트롤을 숨긴다 | 백라이트 내장 키보드가 있는 맥 | https://notchy.dev/mac-keyboard-backlight/ |
| F079 | 시스템·하드웨어 | Caps Lock Indicator (캡스락 표시) | Caps Lock을 켜고 끌 때마다 노치에 짧은 아일랜드를 띄웠다가 사라진다; 키 입력이 아니라 수정키 플래그 상태만 읽는다; 소리 없음 | 입력 모니터링 권한 불필요 | https://notchy.dev/mac-caps-lock-indicator/ |
| F080 | 시스템·하드웨어 | Keyboard Cleaner (키보드 청소 잠금) | ⌘K 팔레트의 Lock Keyboard for Cleaning이나 노치 헤더의 키보드 버튼으로 잠금을 건다; 글자·수정키·상단 미디어·볼륨 키를 시스템 전체에서 무시한다; 남은 시간을 노치에 카운트다운으로 보여 준다; ⌘⎋로 풀거나 60초가 지나면 자동으로 풀린다; 마우스·트랙패드는 계속 동작한다 | 손쉬운 사용 권한 | https://notchy.dev/mac-keyboard-cleaner/ |
| F081 | 기타 | Weather (날씨) | 위치를 기준으로 현재 기온과 날씨 상태를 Home 탭 날씨 카드에 보여 주고 자동 갱신한다; 1.0.197부터 Weather Forecast를 켜면 앞으로 며칠의 날씨와 최고·최저 기온을 보여 준다; 도움말상 위치 권한 없이 쓰는 방법 항목이 있다 | 위치(Location) 권한, 단 설정 → Weather에 도시를 입력하면 위치 권한 없이 사용(도움말 https://notchy.dev/help/weather-without-location/); 외부 서비스: Open-Meteo(계정·API 키 불필요) | https://notchy.dev/mac-menu-bar-weather/ |
| F082 | 시스템·하드웨어 | Disk Space (디스크 용량) | 시스템 플라이아웃에 부트 디스크를 먼저, 이어서 마운트 순서대로 외장 볼륨의 전체·남은 용량을 보여 준다; 외장 드라이브 연결 시 Eject가 붙은 아일랜드를 띄우고 언마운트 완료를 확인해 준다; 디스크 이미지·네트워크 공유·Time Machine 스냅샷은 알리지 않는다; 설정에서 드라이브 행을 끌 수 있다; 카드가 보일 때만 갱신한다 | 없음 | https://notchy.dev/mac-disk-space-monitor/ |
| F083 | 시스템·하드웨어 | Wi-Fi Signal (와이파이 신호) | 노치의 네트워크 카드에 RSSI(dBm), 같은 기준으로 그린 막대, 협상된 링크 속도(Mbps), 채널·대역(2.4/5/6GHz), 보안 방식, 로컬 IPv4를 보여 준다; 공인 IP는 요청할 때 가져와 보관한다; SSID가 Location Services 때문에 가려지면 그 사실을 표시한다; 카드가 보일 때만 갱신한다 | 네트워크 이름(SSID) 표시에는 위치 서비스(Location) 권한 필요(macOS Sonoma 이후); 공인 IP 조회는 외부 요청(조회처 자료 없음) | https://notchy.dev/mac-wifi-signal-strength/ |
| F084 | 시스템·하드웨어 | Wi-Fi Password (와이파이 비밀번호 보기) | 네트워크 카드의 버튼을 명시적으로 눌렀을 때만 현재 연결된 네트워크의 키체인 항목을 조회한다; macOS 관리자 인증 창을 거쳐 비밀번호를 화면에 보여 준다; 카드를 닫으면 메모리에서 지우고 저장·전송하지 않는다; 다른 네트워크의 비밀번호는 읽지 않는다 | 키체인 접근 시 macOS 관리자 인증(매번) | https://notchy.dev/show-wifi-password-mac/ |
| F085 | 시스템·하드웨어 | GPU Monitor (GPU 모니터) | 가속기 자체 성능 통계에서 GPU 사용률을 읽어 시스템 카드에 CPU·온도·메모리·네트워크·드라이브 여유 공간과 함께 보여 준다; Top Processes를 CPU 대신 에너지 영향(CPU 시간+깨우기 횟수) 기준으로 정렬한다; GPU 온도는 표시하지 않는다; 카드가 보일 때만 샘플링한다 | Intel·Apple silicon(내장 GPU 수치) | https://notchy.dev/mac-gpu-monitor/ |
| F086 | 시스템·하드웨어 | USB Devices (USB 장치 정보) | Devices 카드에 연결한 장치마다 IO 레지스트리에서 읽은 실제 협상 링크 속도와 제품명·제조사를 보여 준다; 빠른 순, 그다음 이름순으로 정렬한다; 내부 컨트롤러·루트 허브는 걸러 낸다; 도크에 매달린 장치도 각자 속도로 보여 준다; 연결·해제 시 즉시 반영하고 드라이브 마운트 시 Eject 아일랜드를 띄운다; 설정 → Home에서 카드를 추가·배치·제거한다 | 없음 | https://notchy.dev/mac-usb-device-info/ |
| F087 | 실행·검색·입력 | Knock Gesture (노크 제스처) | Apple silicon 노트북 본체의 가속도계로 날카로운 두 번 충격(노크)을 감지하고 일상적인 움직임은 무시한다; 감도를 light·medium·firm 중 고른다; 노크에 동작을 지정한다(노치 열기·닫기, 파일 선반, 클립보드 기록, 명령 팔레트, 카메라 미러, 재생/일시정지, 곡 넘기기, 음소거, 카페인, 스크린샷, 뽀모도로 시작, 화면 잠금); 앱별로 다른 동작을 지정한다; 센서 스트림이 열리지 않으면 수정키 두 번 누르기로 자동 대체한다; 홈페이지 카드 기준 한 번·두 번·세 번 탭에 각각 다른 동작을 줄 수 있고 타이핑 보호가 있다 | Apple silicon 노트북(본체 가속도계); 수정키 트리거는 손쉬운 사용 권한(입력 모니터링 불필요); 설정 → Knock에서 Knock to Open을 켜고 소스 선택(도움말 https://notchy.dev/help/knock-not-working/) | https://notchy.dev/mac-knock-gesture/ |
| F088 | 실행·검색·입력 | Tap to Control (탭 제스처) | Force Touch 트랙패드에서 클릭으로 이어지지 않는 가벼운 탭을 압력 곡선으로 구분해 동작을 실행한다(감도 light·medium·firm); 트랙패드가 없는 데스크톱·외장 키보드 환경에서는 Control·Option·Command·Shift를 단독으로 두 번 눌러 실행한다; 단축키 조합 중의 수정키 입력(예: ⌘C)은 무시한다; 노크와 같은 동작 목록·앱별 재지정을 공유한다; 기본 대상은 노치·선반·클립보드·카페인·재생/일시정지 | Force Touch 트랙패드(탭) 또는 아무 키보드(수정키 두 번, 기본 Control); 수정키는 손쉬운 사용 권한; 트랙패드 탭은 입력 모니터링 권한(가이드에는 없음, 도움말 https://notchy.dev/help/knock-not-working/ 기준) | https://notchy.dev/mac-knock-gesture/#tap-to-control |
| F089 | 실행·검색·입력 | Keyboard Shortcuts (전역 단축키 관리) | Hotkey Manager에서 Notchy 동작(클립보드 열기, 파일 드롭, 뽀모도로 시작, Focus 전환, 캘린더 보기 등)에 전역 단축키를 지정한다; 앱 실행이나 bash·AppleScript 워크플로를 단축키에 묶는다; 단축키 실행 시 노치에서 확인 애니메이션을 보여 줄 수 있다; ⌃⌥K 명령 팔레트와 ⌘1–9 탭 전환을 포함한다; 수정키 두 번 누르기로 노치·선반·클립보드·카페인·재생/일시정지를 연다 | 손쉬운 사용 권한(F002 설치 안내 기준) | https://notchy.dev/mac-keyboard-shortcuts-app/ |
| F090 | 실행·검색·입력 | App Launcher (앱 런처 탭) | 노치의 Launcher 탭에서 선택기로 앱을 추가하면 한 번 눌러 실행하는 타일 그리드가 된다; 드래그로 순서를 바꾸고 마우스를 올려 제거한다; 아이콘·이름을 표시할 때마다 파일 시스템에서 읽어 이름 변경·이동 후에도 동작한다; 전체 화면 앱과 모든 데스크톱에서 쓸 수 있다(1.0.49 도입) | 없음 | https://notchy.dev/mac-app-launcher/ |
| F091 | 실행·검색·입력 | Launcher Wheel (런처 휠) | 기본 ⌃⌥L(변경 가능)을 누르면 노치 아래에 고정 앱이 12시 방향부터 시계 방향 원형으로 펼쳐진다; 화살표·Tab으로 이동, Return으로 열기, 숫자 키로 바로 이동, Escape로 닫기, 마우스 클릭도 된다; Launcher 탭의 고정 앱과 실행 중인 앱 사이를 전환한다; 현재 Space와 전체 화면 앱 위에 열리고 선택하거나 다른 곳을 누르면 닫힌다; 설치된 모든 앱을 보여 주지는 않는다(1.0.178 도입) | macOS 13 이상 | https://notchy.dev/launchpad-alternative-mac/ |
| F092 | 실행·검색·입력 | Command Palette (명령 팔레트) | 단축키 하나로 검색창을 열고 몇 글자 입력 후 Return으로 Notchy 명령을 실행한다; 각 명령에 제목과 키워드를 붙여 "copy"로 클립보드, "text"로 OCR을 찾는다; 실행 대상은 타이머 시작, 클립보드 기록, OCR, 스크린샷, 창 스냅, Focus·카페인 전환, Shortcut 실행, 탭 이동 등; 팔레트의 모든 항목에 개별 전역 단축키를 줄 수 있다; 범용 런처는 아니다; 도움말 기준 두 글자 이상 입력하면 명령 아래에 홈 폴더의 파일·폴더(Spotlight, 최대 8개)와 클립보드 기록 텍스트(최대 5개)를 함께 보여 주고 Return으로 열기, ⌘Return으로 Finder에서 보기를 한다(https://notchy.dev/help/command-palette-find-files/) | 노치 불필요; 도움말 기준 전역 단축키는 ⌃⌥K, 패널이 열린 상태에서는 ⌘K(가이드 본문은 ⌘K로만 표기) | https://notchy.dev/mac-command-palette/ |
| F093 | 실행·검색·입력 | Quick Search & Translate (빠른 검색·번역·계산) | Search 탭에서 질의를 입력하고 Return으로 브라우저에서 연다; 기본 엔진 9개(Google, DuckDuckGo, Bing, Perplexity, YouTube, GitHub, Wikipedia, Maps, Amazon)와 "yt"·"gh"·"map" 같은 접두어를 지원한다; 1.0.142부터 이름·URL로 사용자 엔진을 추가하면 칩·접두어·⌘1–9 단축키가 생긴다; 링크를 붙여넣으면 검색 대신 바로 연다; Translate 탭은 원문 언어를 자동 감지하고 입력하는 대로 번역을 갱신하며 Copy로 복사한다; 계산기 탭은 입력하는 대로 답을 보여 주고 Return으로 확정·복사하며 이전 계산 기록을 유지한다; 동영상 링크를 붙여넣으면 최고 화질·작은 사본·오디오만 중 골라 저장한다(1.0.141 도입) | 인터넷 연결; 번역은 Google Translate 공개 엔드포인트; 동영상 저장은 오픈소스 yt-dlp를 첫 사용 때 자동으로 내려받아 사용 | https://notchy.dev/mac-quick-search-translate/ |
| F094 | 실행·검색·입력 | Unit Converter (단위·환율 변환) | 계산기에 "90 f to c", "50 usd in eur"처럼 입력하면 입력하는 대로 답을 보여 준다; "in"·"to" 둘 다 구분자로 받는다; 숫자 부분은 계산기를 먼저 거쳐 괄호·퍼센트·함수·직전 답을 쓸 수 있다; Apple Measurement로 길이·질량·온도·부피·면적·속도·시간·데이터 크기·에너지·압력·각도와 통화를 변환한다; 환율은 무료 공개 출처의 중간값을 통화 변환 시에만 가져오고 최대 12시간마다 갱신하며, 못 가져오면 그렇다고 표시한다; 결과를 기록에 남긴다(1.0.172 도입) | 통화 변환은 인터넷 연결(환율 출처 이름은 자료 없음); API 키 불필요 | https://notchy.dev/mac-unit-converter/ |
| F095 | 실행·검색·입력 | Emoji Picker (이모지 선택기) | Emoji 탭에서 이름으로 검색하고 Return을 누르면 패널을 열기 전 포커스가 있던 앱에 이모지를 넣는다; 자주 쓴 12개를 맨 위에 둔다; 피부톤을 한 번 정하면 지원 이모지 전체와 최근 목록에 적용한다; 맥 폰트가 그릴 수 있는 이모지만 Character Viewer와 같은 이름으로 목록화한다; 국가 이름(사용자 언어)으로 국기를 찾는다; 오른쪽 클릭 Copy로 복사만 한다; 이 붙여넣기는 클립보드 기록에 남기지 않는다(1.0.172 도입) | 앞 앱에 붙여넣기 권한은 가이드에 명시 없음(F046 기준 손쉬운 사용으로 추정) | https://notchy.dev/mac-emoji-picker/ |
| F096 | 실행·검색·입력 | Window Snapping (창 스냅) | 창을 노치 쪽으로 끌면 아일랜드에 왼쪽·오른쪽·반쪽·전체 화면 스냅 영역이 나타나고 놓으면 그 영역으로 배치한다; 실제 창 드래그가 시작될 때만 동작한다; 1.0.184부터 설정 → Windows & Spaces의 Window Snap Shortcuts로 왼쪽 반·오른쪽 반·전체 화면을 ⌃⌥⌘←/→/↩(변경 가능)로 실행한다; 1.0.191부터 같은 방향을 다시 누르면 다음 디스플레이로 보낸다; 디스플레이마다 스냅 영역을 따로 둔다; 기능 목록 요약에는 1/4·1/3 배치도 언급된다 | 손쉬운 사용 권한 | https://notchy.dev/mac-window-snapping/ |
| F097 | 실행·검색·입력 | Spaces (데스크톱 공간 전환) | Home 카드에 현재 디스플레이의 데스크톱을 Mission Control 순서로 보여 주고 현재 위치를 표시한다; 각 Space에 이름을 붙이면 WindowServer UUID 기준으로 재부팅 후에도 유지한다(UUID가 없으면 번호로 대체); 카드 클릭·알약 스와이프·단축키로 전환하며 내부적으로 macOS Mission Control 단축키를 보낸다; 커서가 있는 디스플레이의 Space를 보여 준다; 전체 화면 앱은 Full Screen으로 표시하고 번호에서 뺀다 | 시스템 설정 → 키보드 → 단축키 → Mission Control의 Space 이동·Ctrl-1~9 단축키가 켜져 있어야 함 | https://notchy.dev/mac-spaces-switcher/ |
| F098 | 클립보드·텍스트 | Text Snippets (텍스트 스니펫) | 주소·답장·코드 블록을 스니펫으로 저장한다; ⌃⌥K 팔레트에서 이름 몇 글자를 입력하고 Return을 누르면 직전에 쓰던 앱에 붙여넣고 포커스를 되돌린다; 스니펫 붙여넣기는 클립보드 기록에 남기지 않는다; 로컬 저장, 계정·동기화 없음; 입력 중 약어를 자동 확장하는 방식은 가이드에 없다 | 앞 앱에 붙여넣기 권한은 가이드에 명시 없음 | https://notchy.dev/mac-text-expander/ |
| F099 | 실행·검색·입력 | Dictation (받아쓰기) | ⌘K의 "Dictate Text"나 지정 단축키로 시작·종료한다(도움말상 Fn 키 사용 항목 있음); Apple 온디바이스 음성 모델만 쓰도록 고정해 오디오를 내보내지 않는다; 듣는 동안 노치에 단어 수가 올라가는 라이브 칩을 보여 주고, 설정 → Capture의 Live Transcript를 켜면 최근 단어를 보여 준다; 끝나면 포커스가 있던 입력란에 텍스트를 붙여넣는다; 2.5초 침묵이면 종료·붙여넣기, 최대 2분에서 강제 종료한다; 시스템 언어의 오프라인 모델을 쓰고 없으면 알린다 | 마이크·음성 인식(Speech Recognition)·손쉬운 사용 권한(가이드에는 없음, 도움말 https://notchy.dev/help/dictation-setup/ 기준); 해당 언어의 오프라인 음성 모델; 도움말상 설정 → Capture & Files의 Dictation Shortcut 또는 Press Fn to Dictate로 시작 | https://notchy.dev/mac-dictation-app/ |
| F100 | 실행·검색·입력 | Apple Shortcuts (단축어 실행) | Shortcuts 탭에 단축어 앱 순서대로 전체 단축어를 색깔 칩 그리드로 보여 준다; 칩을 누르면 macOS shortcuts CLI로 실행하고 실행 중 스피너, 끝나면 성공·실패 표시를 한다; 새로 만들거나 이름을 바꾼 단축어는 탭 새로고침으로 반영한다; 1.0.201부터 Show in Notchy 단축어 동작과 notchy://show 링크로 제목·메시지를 1~10초간 노치에 띄운다(설정 → General에서 켜야 함, 텍스트 표시만 가능) | 별도 권한 없음(단축어가 필요로 하는 권한은 macOS가 요청) | https://notchy.dev/mac-shortcuts-app/ |
| F101 | 화면 캡처·회의 | Keystroke Visualizer (키 입력 표시) | 켜 두면 누르는 단축키·키를 노치에 아일랜드(키캡)로 보여 준다; 듣기 전용 이벤트 탭으로 입력을 지연시키지 않는다; 비밀번호 칸은 macOS 보안 입력 때문에 보이지 않는다; 기본 꺼짐, 발표·녹화 때 켜고 끄는 모드다 | 입력 감지 권한(입력 모니터링 추정, 가이드에 명시 없음) | https://notchy.dev/mac-keystroke-visualizer/ |
| F102 | 화면 캡처·회의 | Cursor Highlighter (커서 강조) | 설정 → Pointer에서 Click Ripples를 켜면 클릭마다 원형 파동(오른쪽 클릭은 이중 원)을 그린다; Pointer Halo는 커서를 따라다니고 누를 때 줄어든다; ⌃⌥를 누르고 있으면 커서 주변 원만 남기고 화면을 어둡게 하는 스포트라이트를 켠다(짧은 지연으로 일반 단축키와 구분); 포인터 테마 9종(Snow, Accent, Amber, Frost, Neon, Candy, Aurora, Sunset, Retro)으로 Apple 기본 커서 전체를 다시 칠하고 최대 2배로 키운다; 커서 꼬리 효과(Comet, sparkles, hearts, rainbow)는 저전력 모드·동작 줄이기에서 멈춘다; 사용자 커서 이미지는 지원하지 않는다; 모두 기본 꺼짐 | 스포트라이트는 손쉬운 사용 권한; 파동·후광·꼬리는 권한 불필요; SIP 해제 불필요 | https://notchy.dev/mac-cursor-highlighter/ |
| F103 | 클립보드·텍스트 | Text Actions (텍스트 선택 동작) | 설정 → Pointer → Text에서 Text Actions를 켠다; 드래그나 더블·트리플 클릭으로 텍스트를 선택하면 위쪽(공간이 없으면 아래)에 Copy·Search·Look Up·Translate 막대를 띄운다; URL은 추적 파라미터를 지운 Open Link, 이메일은 New Email, 전화번호는 Call, 수식은 Copy Result, JSON은 Copy Formatted 버튼을 더한다; Translate는 막대 아래 카드에 감지 언어와 번역을 펼친다; Search는 Quick Search에서 고른 엔진을 쓴다; 비밀번호 칸·보안 입력, 버튼·슬라이더·제목 표시줄 드래그, ⌘-드래그는 무시하고 PopClip 실행 중에는 숨는다; 사용자 동작 추가는 불가(1.0.198 도입, 기본 꺼짐) | 손쉬운 사용 권한; 번역은 Google Translate(인터넷) | https://notchy.dev/mac-text-selection-actions/ |
| F104 | 실행·검색·입력 | Color Picker (색상 추출) | 노치에서 스포이트를 실행하면 시스템 확대 루페가 뜨고 화면의 아무 픽셀을 클릭한다; HEX 코드를 즉시 클립보드에 복사하고 색상 아일랜드로 확인해 준다; 고른 색은 견본과 함께 클립보드 기록에 들어가 고정할 수 있다; 1.0.195부터 Color Tools를 켜면 Home 카드에 최근 12색을 두고 HEX·RGB·HSL·SwiftUI Color로 복사한다; NSColorSampler 사용 | 화면 기록 권한 불필요 | https://notchy.dev/mac-color-picker/ |
| F105 | 기타 | Home & HomeKit (홈 제어) | Apple 단축어 라이브러리에서 이름(light, lamp, thermostat, plug, blinds, lock, 방 이름 등)으로 홈 관련 단축어를 찾아 Home 탭을 자동 구성한다; 장면(Scenes)과 기기(Accessories)를 나눠 보여 준다; 타일을 누르면 단축어를 실행하고 패널을 닫는다; 잘못 분류된 타일은 고정·해제로 바로잡는다; 노치·전역 단축키·명령 팔레트·노크로 탭을 연다; HomeKit 데이터에 직접 접근하지 않는다 | 사용자가 만든 홈 제어 Apple 단축어; 허브 필요 여부는 해당 단축어 조건을 따름 | https://notchy.dev/mac-homekit-control/ |
| F106 | 알림·통화·개인정보 | Notifications in the Notch (노치 알림 미러링) | macOS 알림을 노치 가운데에 아일랜드로 띄우고 따로 닫지 않아도 사라진다; 수신 전화는 아일랜드 전체를 차지한다; 메시지(WhatsApp·Telegram 등) 알림도 아일랜드로 띄운다; 알림 센터를 열 때 예전 배너가 다시 재생되지 않게 한다(1.0.79 수정); 알림 센터 자체는 대체하지 않는다; 홈페이지 카드 기준 알림 센터 내용을 노치 탭(Notifications 탭)에 비추는 기능은 전체 디스크 접근이 있을 때만 동작한다 | 알림 기록 탭은 전체 디스크 접근(F107·홈페이지 카드 기준); 배너 제어는 손쉬운 사용 | https://notchy.dev/mac-notification-center-notch/ |
| F107 | 알림·통화·개인정보 | Move Notification Banners (알림 배너 위치 변경) | 설정 › Calls & Messages › App Notifications에서 macOS Banner Position을 왼쪽 위·가운데 위·오른쪽 위·왼쪽 아래·가운데 아래·오른쪽 아래 중 고르고 미리보기로 확인한다; 미러링을 "Notchy Only"로 두면 기본 배너를 닫고 노치 아일랜드만 보여 준다; 배너가 닫히지 않으면 다시 확인하고 두 번째 방법으로 닫는다(macOS 26 대응); 미러링된 알림의 Open을 누르면 해당 메시지로 바로 이동한다; App Notifications에서 Teams·Slack·Outlook을 음소거하면 아일랜드도 멈춘다(1.0.153 도입) | 손쉬운 사용 권한(배너 이동·닫기); 전체 디스크 접근(Notifications 탭 기록); macOS 13 이상 | https://notchy.dev/mac-notification-banner-position/ |
| F108 | 알림·통화·개인정보 | Incoming Calls (수신 전화 아일랜드) | FaceTime 수신 전화와 Calls on Other Devices로 넘어온 iPhone 전화를 노치 아일랜드로 띄운다; 번호를 연락처와 대조해 이름을 보여 준다; Answer·Decline을 아일랜드에서 누르면 기본 통화 패널의 동작을 대신 실행한다; 기본 패널은 그 자리에서 숨기고 Notchy를 종료하면 바로 돌아온다; 1.0.201부터 Outgoing Calls를 켜면 거는 전화에도 음소거·카메라·끊기 컨트롤을 준다(기본 꺼짐); 노치가 없는 맥에서는 알약에 표시한다 | 손쉬운 사용 권한(통화 패널 읽기·버튼 누르기); 연락처(Contacts) 권한(이름 표시 시, 도움말은 발신자 사진 용도로 안내); iPhone 전화는 Apple의 Calls on Other Devices 설정 필요; 전체 디스크 접근 불필요 | https://notchy.dev/mac-incoming-call-notification/ |
| F109 | 알림·통화·개인정보 | Message Reply (메시지 답장) | 메시지가 오면 보낸 사람과 본문을 노치에 보여 주고 답장 입력란을 둔다; 입력·전송을 노치에서 끝내고 Messages 앱은 앞으로 나오지 않는다; 손쉬운 사용으로 알림 배너를 읽고 배너의 답장 동작을 실행하므로 메시지 기록에는 접근하지 않는다; iMessage와 iPhone에서 전달된 SMS 모두 지원한다; 기본 배너는 그 자리에서 숨기고 Notchy 종료 시 돌아온다 | 손쉬운 사용 권한; 전체 디스크 접근 불필요; SMS는 iPhone 문자 전달 설정 필요 | https://notchy.dev/mac-imessage-reply/ |
| F110 | 화면 캡처·회의 | Zoom & Teams Calls (화상회의 통화 표시) | 허용 목록의 회의 앱(Teams, Zoom, Slack, Discord, Webex 등)이 열려 있고 입력 장치가 동작하면 통화로 판단한다; 노치 한쪽에 전화 아이콘과 경과 시간, 다른 쪽에 마이크 레벨 미터를 띄운다; 시작·종료 모두 지연 판정을 두어 접속음이나 헤드셋 교체로 깜빡이지 않게 한다; Teams 통화가 Now Playing 음악으로 잡히던 문제를 막는다; 오디오를 녹음하지 않는다 | 권한 언급 없음(시스템 마이크 사용 신호만 읽음) | https://notchy.dev/mac-meeting-call-indicator/ |
| F111 | 알림·통화·개인정보 | Camera Guard & Mic Mute (카메라 감시·마이크 음소거) | CoreMediaIO 장치 상태로 어떤 앱이든 카메라를 쓰면 열린 노치 헤더의 카메라 버튼을 초록색으로 표시한다; Camera Guard를 켜면 카메라를 연 앱이 생길 때 경고하고, Block으로 두면 그 앱에 종료를 요청한다; 헤더의 마이크 칩으로 입력 장치를 시스템 전체에서 음소거하고 음소거 중 빨간색으로 표시한다; 1.0.166부터 카메라·마이크 시작 때마다 아일랜드를 띄우지 않는다; 홈페이지 카드 기준 카메라·마이크가 켜지면 알약으로 알리는 Privacy Indicator(CoreAudio 포함)도 있다 | 카메라·마이크 권한 불필요(장치 상태 플래그만 읽음) | https://notchy.dev/mac-camera-mic-indicator/ |
| F112 | 화면 캡처·회의 | Camera Mirror (카메라 미러) | 노치를 쓸어내리거나 호버·클릭하면 둥근 창에 카메라 미리보기가 내려온다; 화면에만 보여 주고 녹화·저장·업로드하지 않는다; 노치 없는 맥에서는 알약에서 내려온다 | 카메라 권한(가이드에는 없음, 도움말 https://notchy.dev/help/permissions-notchy-needs/ 기준); 카메라 장치 | https://notchy.dev/mac-camera-mirror/ |
| F113 | 화면 캡처·회의 | Teleprompter (텔레프롬프터 Cuely) | Cuely가 노치 바로 아래(웹캠 옆)에서 대본을 스크롤한다; 설정한 속도로 자동 스크롤하거나 마우스 휠·트랙패드로 넘긴다; 설정 → Cuely의 Follow My Voice를 켜면 읽는 음성에 맞춰 위치를 따라간다(기본 꺼짐); Zoom·Teams·Meet·OBS·QuickTime 위에 떠 있다; 쓰지 않을 때는 노치 안으로 숨는다; 설정 → Behavior의 Screen Sharing Privacy를 Hidden from Captures로 두면 캡처 제외를 지원하는 앱의 공유·녹화에서 빠진다; 대본 길이·워터마크 제한 없음 | Follow My Voice는 음성 인식(Speech Recognition) 권한; 노치 없는 맥은 알약 | https://notchy.dev/mac-teleprompter-app/ |
| F114 | 알림·통화·개인정보 | Hide Menu Bar Icons (메뉴 막대 아이콘 숨기기) | 설정에서 켜면 메뉴 막대에 드래그 가능한 구분자와 화살표(chevron) 두 항목이 생긴다; ⌘-드래그로 아이콘을 구분자 왼쪽에 옮기면 숨김 대상이 된다; 화살표를 눌러 접고 펼친다; 구분자를 화면 밖으로 늘리는 공개 AppKit 방식이며 메뉴 막대 내용을 읽거나 업로드하지 않는다; 아이콘 재정렬·그룹 관리는 하지 않는다(홈페이지 비교표 기준) | 권한 불필요(공개 API) | https://notchy.dev/hide-menu-bar-icons-mac/ |
| F115 | 알림·통화·개인정보 | Icons Behind the Notch (노치에 가린 아이콘) | Menu Bar 카드에 보이는 것·숨긴 것·노치에 가린 것을 포함한 모든 메뉴 막대 항목을 나열한다; 행을 누르면 손쉬운 사용으로 실제 상태 항목을 눌러 그 앱의 메뉴를 연다; 패널이 열린 상태에서도 쓴다; 카드가 나타날 때와 앱 실행·종료 때만 목록을 다시 만든다 | 손쉬운 사용 권한 | https://notchy.dev/menu-bar-icons-behind-notch/ |
| F116 | 알림·통화·개인정보 | Lock Screen Widgets (잠금 화면 위젯) | 화면이 잠기거나 화면 보호기가 돌 때 잠금 화면 위에 알약 위젯을 띄운다; 시계·날씨·배터리·Now Playing·Focus를 보여 주며 표시 항목을 고른다; 홈페이지 카드 기준 날씨·타이머·캘린더·미리 알림·블루투스·Focus 위젯을 각각 켜고 끄며 전체 화면 가사와 재생 컨트롤을 띄운다; 클릭은 비밀번호 입력란으로 통과한다; Liquid Glass 재질 적용(F009) | 설정 → Lock Screen에서 Lock Screen Widget을 켜야 함; 도움말 기준 카드 종류는 Now Playing·Timer·Up Next·Reminders·Focus·Weather·Battery·Device Batteries이고 배치·밀도·앨범 아트 배경을 고름(https://notchy.dev/help/lock-screen-widgets/); 날씨는 위치 권한(F081) | https://notchy.dev/mac-lock-screen-widget/ |
| F117 | 알림·통화·개인정보 | Face Unlock (얼굴 잠금 해제) | 설정 → Lock Screen에서 안내 창을 따라 로그인 비밀번호 입력(계정과 즉시 대조)과 9방향 얼굴 스캔으로 등록한다; 잠긴 상태에서 화면이 깨어나거나 화면 보호기가 멈추거나 키·트랙패드를 건드리면 짧은 카메라 스캔을 시작하고, 옵션으로 스페이스바로 시작한다; 충분한 프레임이 일치하면 잠금 화면에 비밀번호를 대신 입력한다; 노치에 "Looking for your face"·"Face recognised" 상태를 표시한다; 깜빡임·고개 움직임으로 생체 여부를 보고 사진·화면을 거부하며 Light·Strict 모드를 고른다; Apple Vision으로 기기 안에서 인식하고 얼굴 데이터·비밀번호는 키체인에 둔다; 스캔마다 카메라를 다시 골라 외장 웹캠·클램셸·데스크톱 맥에서도 동작한다; 재시작 후에는 macOS가 비밀번호를 요구한다(1.0.166 도입) | 카메라(내장 또는 외장 웹캠, 덮개를 닫으면 USB 웹캠); 카메라 권한 + 손쉬운 사용 권한(비밀번호 입력용, 가이드에는 없음, 도움말 https://notchy.dev/help/set-up-face-unlock/ 기준); 로그인 비밀번호를 키체인에 저장; Touch ID 보호 저장소를 쓰는 맥은 1~30일마다 재인증(도움말 https://notchy.dev/help/face-unlock-not-working/); macOS 13 이상, Intel·Apple silicon | https://notchy.dev/mac-face-unlock/ |
| F118 | 알림·통화·개인정보 | Face ID on Mac? (맥 Face ID 안내) | 맥에 Face ID가 없다는 설명과 Touch ID·Apple Watch 잠금 해제 안내를 담은 글이다; 대안으로 F117 Face Unlock 설정 경로(설정 → Lock Screen → Set Up Face Unlock)를 소개한다 | F117과 같음 | https://notchy.dev/does-macbook-have-face-id/ |
| F119 | 음악·오디오 | Lock Screen Lyrics (잠금 화면 가사) | 화면이 잠긴 동안 잠금 화면에 아트워크·곡 정보·재생 컨트롤·동기화 가사를 띄운다; 작은 카드, 플레이어 옆 가사 열, 전체 화면 세 가지 크기를 제공한다; 전체 화면은 넓은 화면에서 로그인 영역 양옆에 아트워크와 가사를 배치하고 좁으면 띠 형태로 바꾼다; 재생 버튼을 뺀 클릭은 비밀번호 입력란으로 통과한다; 잠금 해제 즉시 창을 없앤다; 가사는 기본 켜짐이지만 잠금 화면 위젯 전체가 꺼져 있으면 만들지 않는다; 알약에 한 줄씩 가사를 띄우는 표시도 언급된다 | 잠금 화면 위젯 설정 켬; 가사 출처는 F015와 같음 | https://notchy.dev/mac-lock-screen-lyrics/ |
| F120 | 앱 관리·위젯·유지보수 | Desktop Widgets (데스크톱 위젯) | Apple 위젯 갤러리에 AI Usage·Activity·Timer WidgetKit 위젯을 추가한다(데스크톱 오른쪽 클릭 → Edit Widgets로 배치, 백그라운드 갱신); 설정 › Home › Desktop Widgets에서 Clock·World Clock·Now Playing·Weather·Sunrise & Sunset·Calendar·Batteries·System·Photo 위젯을 배경화면에 고정한다; 크기는 Small·Medium·Tall·Large·Extra Large; Now Playing 위젯은 AirPlay 출력 선택, Extra Large에서 가사, 커버 클릭 시 전체 화면 플레이어(Esc 닫기, Space 재생/정지, 화살표 넘기기)를 제공한다; 날씨 위젯은 시간별·주간 예보와 체감·강수·바람·습도·UV·대기질을 보여 준다; Photo 위젯은 최대 6개, 사진 하나 또는 폴더 순환; 유리·불투명 스타일, 투명도 줄이기·대비 증가를 따른다(1.0.79 도입) | WidgetKit 위젯은 데스크톱 배치에 macOS 14 Sonoma 이상(Ventura는 알림 센터에만); 배경화면 위젯은 macOS 13 이상 | https://notchy.dev/mac-desktop-widgets/ |
| F121 | 알림·통화·개인정보 | Custom Alert Sounds (알림 종류별 소리) | 에이전트 승인·AI 사용량 알림·통화·메시지·타이머·배터리·다운로드와 파일·업데이트·기타 9개 분류마다 소리를 따로 정한다; macOS 기본 알림음(Glass, Hero, Ping 등)이나 사용자 오디오 파일, 무음 중 고르고 고르는 즉시 미리 들려준다; 잠금·잠금 해제 알약에 별도 소리 한 쌍을 정한다; Focus·방해 금지 중에는 소리를 내지 않는다 | 없음 | https://notchy.dev/mac-custom-notification-sounds/ |
| F122 | AI·개발자 | AI Usage Tracker (AI 사용량 추적) | 설정에서 AI Usage 탭을 켜고 첫 실행 안내에서 읽을 대상을 허용한다; Claude Code·Codex·Cursor·Antigravity·Gemini CLI·Windsurf·Zed는 기존 로그인·로컬 파일에서 자동 감지하고, 에디터 Copilot 플러그인이 로그인돼 있으면 GitHub Copilot도 감지한다; Claude Code·Codex는 CLI 로그인으로 실제 계정 게이지를 읽고 실패 시 로컬 로그 추정치로 대체하며 갱신 시각을 표시한다; 5시간·주간 창, 오늘 토큰, 추정 비용, 진행 막대, 리셋 카운트다운, 오늘·7일·30일 지출, 잔액, 주 사용 모델을 보여 준다; Provider Accounts에 키·토큰·세션을 한 번 붙여넣으면 35개 이상 원격 제공자(OpenAI, DeepSeek, Mistral, OpenRouter, Groq, Kimi, Claude Admin API 등)의 할당량·지출·크레딧을 가져온다; 브라우저(Safari, Chrome, Arc, Firefox 등)에 로그인된 세션을 직접 읽어 확장 없이 연동한다(최선 노력); Limit Warnings(기본 켜짐)는 50%·80% 사용, 소진 속도상 한도 도달 예상(Claude Code·Codex), 세션 소진·복귀, 리셋 시점에 노치 알림을 띄운다; 접힌 아일랜드에 한도에 가장 가까운 제공자를 보여 준다; 탭을 메뉴 막대로 떼어 낸다; 1.0.178부터 최근 30일 Claude Code 기여 그래프와 연속 기록을 보여 준다; 표시할 제공자 섹션과 순서를 고른다(홈페이지 카드) | 로컬 에이전트: 해당 CLI 로그인·로그 파일; 원격 제공자: 각 서비스 API 키·토큰(키체인 저장, 해당 제공자 API로만 전송); 브라우저 세션 읽기는 전체 디스크 접근·키체인 허용이 필요할 수 있음; 인터넷 연결 | https://notchy.dev/mac-ai-usage-tracker/ |
| F123 | AI·개발자 | Claude Usage (Claude Code 사용량) | Claude Code 로그인으로 실제 게이지를, 로컬 세션 로그로 대체 추정치를 읽는다; 5시간 창·주간 사용량·오늘 토큰·추정 비용을 진행 막대와 리셋 카운트다운으로 보여 준다; Limit Warnings가 50%·80%, 세션 소진·복귀, 주간 리셋을 알린다; 노치·메뉴 막대 분리·데스크톱/알림 센터 위젯으로 본다; 선택적으로 Anthropic Admin API 키를 넣으면 별도 API 지출 화면(토큰, 일별 지출 차트)을 추가한다 | Claude Code 로그인(API 키 불필요); API 지출 보기는 Anthropic Admin API 키 | https://notchy.dev/claude-usage-tracker-mac/ |
| F124 | AI·개발자 | Codex Usage (Codex 사용량) | Codex CLI 로그인으로 5시간·주간 창 사용 비율, 요금제, 정확한 리셋 시각을 읽고 로컬 세션 로그로 대체 추정한다; 노치·메뉴 막대·데스크톱 위젯에 표시한다; Limit Warnings가 50%·80%, 한도 도달 예상, 세션 소진·복귀, 리셋을 알린다; Agent Permission Islands를 켜면 Codex가 권한·입력을 기다릴 때 아일랜드를 띄우고 터미널로 이동 버튼 또는 승인·거부 버튼을 준다 | Codex CLI 로그인(API 키 불필요) | https://notchy.dev/codex-usage-tracker-mac/ |
| F125 | AI·개발자 | Claude Limit Resets (Claude 한도 리셋 안내) | Claude Code 5시간·주간 한도와 리셋 방식, 한도 도달 시 선택지를 설명하는 안내 글이다; Notchy 쪽 동작은 F122·F123의 리셋 카운트다운과 Limit Warnings(소진 임박·소진·리셋 알림) | Claude Code 로그인 | https://notchy.dev/claude-code-usage-limit-reset/ |
| F126 | AI·개발자 | Codex Limit Resets (Codex 한도 리셋 안내) | Codex 5시간·주간 창과 리셋 확인 위치를 설명하는 안내 글이다; Notchy 쪽 동작은 F124의 창별 사용 비율·리셋 시각 표시와 Limit Warnings | Codex CLI 로그인 | https://notchy.dev/codex-usage-limit-reset/ |
| F127 | AI·개발자 | Claude Code Notifications (에이전트 권한 승인 아일랜드) | 기능을 켜면 작은 전달 스크립트를 설치하고 ~/.claude/settings.json에 Notchy 훅 그룹을 한 번 병합한다(다른 설정 보존, Claude Code가 없으면 쓰지 않음); Claude Code의 Notification 이벤트(실제 권한 대화상자)가 뜰 때만 Allow·Deny 아일랜드를 띄운다; 버튼을 누르면 훅으로 결정을 돌려보내 실행을 이어 간다; 터미널에서 먼저 답하면 PostToolUse를 보고 약 1초 안에 아일랜드를 지운다; Codex는 ~/.codex/hooks.json에 같은 훅을 등록하고 Codex가 한 번 신뢰 확인을 요청한다; 끄면 두 파일에서 훅 그룹을 제거한다; Cursor·Gemini CLI 승인은 지원하지 않는다; 홈페이지 카드 기준 설치된 훅이 턴·승인 요청·턴별 비용을 노치에 보고하는 Agent Activity가 있다 | Claude Code 또는 Codex CLI 설치; 사용자 홈의 설정 파일 쓰기 | https://notchy.dev/claude-code-notifications/ |
| F128 | AI·개발자 | Notch Terminal (노치 터미널) | 노치 탭에서 사용자의 로그인 셸(zsh·bash·fish)을 PTY로 띄우는 VT100/xterm 에뮬레이터를 연다; 색상·커서 키·탭 완성과 vim·htop·tmux 같은 TUI가 동작한다; 터미널 뷰를 한 번 만들어 재사용하므로 다른 탭으로 가도 셸·빌드·SSH가 계속 돈다; 단축키로 연다; SwiftTerm 기반 | 없음 | https://notchy.dev/mac-notch-terminal/ |
| F129 | AI·개발자 | Long Command Islands (긴 명령 완료 알림) | 기능을 켜면 ~/.zshrc에 표식으로 감싼 zsh 블록을 한 번 추가한다; 각 명령의 시작·종료를 로컬 Unix 소켓으로 Notchy에 보낸다; 10초 넘게 실행 중인 명령만 명령어와 경과 시간을 아일랜드에 띄운다; 끝나면 종료 코드를 ✓·✗와 걸린 시간으로 보여 준다; 끄면 블록을 깔끔하게 지운다; Notchy가 꺼져 있어도 셸이 깨지지 않게 의존성이 없으면 아무것도 하지 않는다; 터미널 앱과 무관하게 동작한다 | zsh 전용(bash·fish 미지원); ~/.zshrc 수정 | https://notchy.dev/mac-terminal-command-notifications/ |
| F130 | AI·개발자 | Homebrew GUI (홈브루 관리) | Packages 탭에서 brew search --desc로 설명과 함께 cask·formula를 검색한다(같은 이름은 행을 분리); 설치된 항목과 오래된 항목(자동 업데이트 cask 포함)을 보여 준다; 설치·업그레이드(개별·전체)·삭제를 클릭으로 실행한다; 모든 실행은 비대화식이라 비밀번호·확인이 필요한 cask는 brew 메시지와 함께 실패한다; Apple silicon·Intel의 표준 경로에서 brew를 찾는다; tap·services·캐시 정리는 지원하지 않는다(1.0.172 도입) | 사용자가 설치한 Homebrew 필수(없으면 brew.sh 안내); 인터넷 연결 | https://notchy.dev/homebrew-gui-mac/ |
| F131 | AI·개발자 | Listening Ports (사용 중인 포트 종료) | ⌘K 팔레트에 포트 번호를 입력하면 LISTEN 상태 TCP 포트·프로세스 이름·pid 목록을 보여 준다; 선택한 프로세스에 SIGTERM을 보낸다; 비특권 lsof를 실행해 파싱하고 IPv4·IPv6 바인딩을 모두 보여 주며 pid+포트로 중복을 없앤다; 처리량은 보여 주지 않는다 | root·헬퍼 불필요; macOS 13 이상 | https://notchy.dev/mac-kill-process-on-port/ |

## 홈페이지 카드 대응

홈페이지 "Everything you need" 구역의 카드 74개를 순서대로 적었다. "대응 가이드"는 그 카드의 동작을 설명하는 가이드 ID다. "부분"은 카드 내용 일부만 가이드에 있다는 뜻이다.

| # | 카드 이름 | 대응 가이드 | 비고 |
|---|---|---|---|
| 1 | Face Unlock | F117, F118 | |
| 2 | Now Playing | F014, F017, F027, F020 | 카드의 "Apple Music에서 한 번 눌러 Favorite"는 어느 가이드에도 없다 |
| 3 | AI Usage Tracker | F122, F123, F124 | 카드의 "제공자 섹션 표시 여부·순서 선택"은 가이드에 없다 |
| 4 | Sound Mixer | F020, F021 | |
| 5 | Search & Translate | F093, F094 | |
| 6 | Command Palette | F092, F089 | |
| 7 | Knock to Control | F087, F088 | 카드의 "한 번·두 번·세 번 탭마다 다른 동작, 타이핑 보호"는 가이드 본문에 자세히 없다 |
| 8 | Menu Bar Detach | 전용 가이드 없음 | F114, F122, F123, F124에서 탭을 메뉴 막대 팝오버로 떼어 낸다는 언급만 있다 |
| 9 | Clipboard History | F045 | |
| 10 | Zoom Teleprompter | F113 | |
| 11 | System HUDs | F023, F074, F078 | |
| 12 | AirPods Manager | F022 | |
| 13 | Pomodoro Timer | F028, F031 | |
| 14 | Menu Bar Calendar | F038, F039 | |
| 15 | Camera Mirror | F112 | |
| 16 | Hide the Notch | F006 | |
| 17 | 100% Native | 대응 기능 가이드 없음 | 제품 속성이다. 성능 수치는 roundup의 /notchy-cpu-battery-usage/, 아키텍처는 F012에 있다 |
| 18 | Liquid Glass UI | F009, F005(부분) | 카드의 "펼친 패널 폭·높이 조절과 실시간 미리보기"는 F005 도움말 항목에만 있다 |
| 19 | Quick Notes | F043 | |
| 20 | File Shelf | F049 | |
| 21 | Keep Awake | F037 | |
| 22 | Live Weather | F081 | |
| 23 | Focus Mode | F033 | |
| 24 | Battery HUD | F072, F071 | |
| 25 | Synced Lyrics | F015 | |
| 26 | Apple Reminders | F041 | |
| 27 | Image Converter | F055 | |
| 28 | Audio Switcher | F019 | |
| 29 | Device Battery | F073 | |
| 30 | Download Alerts | F060 | |
| 31 | Apple Shortcuts | F100 | |
| 32 | Zip & Unzip | F056 | |
| 33 | Screenshot Shelf | F051 | |
| 34 | Drive Eject | F061, F082 | |
| 35 | App Launcher | F090 | |
| 36 | Window Snapping | F096 | |
| 37 | Text Snippets | F098 | |
| 38 | OCR & Search | F048 | |
| 39 | Screen Capture | F051, F048 | |
| 40 | Color Eyedropper | F104 | |
| 41 | Mic Mute | F024, F111 | |
| 42 | Keystroke HUD | F101 | |
| 43 | Keyboard Cleaning Lock | F080 | |
| 44 | Menu Bar Icon Hiding | F114 | |
| 45 | System Stats | F064 | |
| 46 | Call Island | F108, F110 | |
| 47 | Stocks Ticker | F004 | |
| 48 | Notch Terminal | F128 | |
| 49 | Desktop Widgets | F120 | |
| 50 | Agent Approvals | F127, F124(부분) | |
| 51 | Privacy Indicator | F111 | 5절의 "카메라·마이크 아일랜드" 항목 참고 |
| 52 | Caps Lock HUD | F079 | |
| 53 | Full Charge Island | F072 | |
| 54 | Alt HUD Styles | 대응 가이드 없음 | 블로그(/blog/notchy-productivity-toolkit/)에만 설명이 있다 |
| 55 | Live Audio Spectrum | F018 | |
| 56 | Custom Idle Animation | 대응 가이드 없음 | 블로그와 가이드 공통 소개 목록에만 있다. 5절 참고 |
| 57 | Multiple Live Activities | F003(부분) | 카드의 "알약 폭이 늘어나고 놓치면 손해가 큰 순으로 배치"는 가이드에 없다 |
| 58 | Lock Screen Widgets | F116, F119 | |
| 59 | Message Island | F109 | |
| 60 | Notification Mirror | F106, F107 | |
| 61 | Agent Activity | F127(부분) | 훅이 턴·승인 요청·턴별 비용을 보고한다는 내용은 카드에만 있다 |
| 62 | Shell Activity | F129 | |
| 63 | Developer API | 대응 가이드 없음 | 도움말 https://notchy.dev/help/local-api/ 에 설명이 있다(부록 참고) |
| 64 | External Display Control | F075, F076, F077 | |
| 65 | Keyboard Backlight | F078 | |
| 66 | AirDrop from the Shelf | F050 | |
| 67 | Clipboard Smart Actions | F045(부분), F047 | 연속 복사 묶기·자동 붙여넣기는 카드에만 있다 |
| 68 | Peek on Hover | F014, F017 | |
| 69 | Drift-free Stopwatch | F031 | |
| 70 | Gestures & Hover Open | 전용 가이드 없음 | F017(스와이프로 곡 넘기기), F097(스와이프로 Space 전환), F002(호버로 열기)에 조각만 있다 |
| 71 | Hidden from Screen Capture | F113(부분) | F113 FAQ에만 언급된다. 세 가지 선택지는 도움말 https://notchy.dev/help/hide-during-screen-sharing/ 에 있다 |
| 72 | Pill on Any Mac | F007, F013, F012 | |
| 73 | Timer Mascots | 전용 가이드 없음 | F069에 "뽀모도로 마스코트 입양" 언급만 있다 |
| 74 | Automatic Updates | 대응 기능 가이드 없음 | 도움말 https://notchy.dev/help/update-notchy/ 에 업데이트 동작이 있다. F066은 다른 앱의 업데이트 기능이다 |

대응 가이드가 없는 카드는 8번 Menu Bar Detach, 17번 100% Native, 54번 Alt HUD Styles, 56번 Custom Idle Animation, 63번 Developer API, 70번 Gestures & Hover Open, 73번 Timer Mascots, 74번 Automatic Updates다. 이 중 8·70·73번은 다른 가이드에 언급이 조금 있고, 54·56번은 블로그에만, 63·74번은 도움말에만 있다. 61번 Agent Activity와 71번 Hidden from Screen Capture는 가이드에 일부만 있다.

반대로 위 표의 "대응 가이드" 칸에 한 번도 나오지 않는 가이드는 49개다. F001, F002, F008, F010, F011, F016, F025, F026, F029, F030, F032, F034, F035, F036, F040, F042, F044, F046, F052, F053, F054, F057, F058, F059, F062, F063, F065, F066, F067, F068, F069, F070, F083, F084, F085, F086, F091, F095, F097, F099, F102, F103, F105, F115, F121, F125, F126, F130, F131. 이 가운데 F001·F002·F032·F125·F126은 소개·설명 글이고, 나머지는 홈페이지 카드 없이 가이드에만 있는 기능이다.

## 중복·호환성 가이드

### 131개 가이드 중 독립 기능이 아닌 것

| ID | 성격 | 설명 |
|---|---|---|
| F001 | 제품 소개·설치 안내 | 노치 아일랜드 자체를 소개하는 대표 페이지다. 세부 동작은 다른 가이드와 겹친다 |
| F002 | 일반 소개 | 고유 동작이 거의 없고 위젯 종류는 다른 가이드에 있다 |
| F005 | 얇은 소개 | 크기·색·탭 배치 같은 실제 설정은 도움말 문서에만 있다 |
| F007, F012, F013 | 호환성 안내 | 외장 모니터, Intel 맥, 노치 없는 MacBook Neo에서 알약 모드로 동작한다는 내용이다. F007의 표시 디스플레이 선택만 고유 설정이다 |
| F008 | 제품 속성 | 다국어 지원이다. 사용자가 조작하는 기능은 없다 |
| F032 | 설명 글 | macOS 기본 Clock·Siri 타이머 사용법 안내이고 Notchy 동작은 F031과 같다 |
| F118 | 설명 글 | 맥에 Face ID가 없다는 안내이고 F117로 연결된다 |
| F123, F124 | 하위 랜딩 | F122의 Claude 전용·Codex 전용 페이지다. F123의 Admin API 지출 화면, F124의 Codex 승인 아일랜드만 추가 정보다 |
| F125, F126 | 설명 글 | Claude·Codex 한도 리셋 규칙 안내이고 Notchy 동작은 F122~F124와 같다 |
| F088 | 같은 페이지의 구역 | F087 페이지의 `#tap-to-control` 구역이다. 트리거 종류만 다르고 동작 목록은 같다 |
| F074 | 거의 중복 | F023과 같은 HUD 교체 기능을 밝기 기준으로 다시 쓴 페이지다 |
| F071 | 거의 중복 | 배터리 표시 소개이며 사이클·용량 같은 고유 수치는 F064·F072 쪽에 더 많다 |
| F003 | 개념 묶음 | 타이머·다운로드·통화 등 다른 기능이 노치에 표시되는 방식의 총칭이다 |

### 같은 화면이나 같은 장치를 나눠 쓰는 묶음

구현할 때 하나의 화면·모듈로 묶일 가능성이 높은 묶음이다. 각 가이드가 서로 다른 동작을 설명하므로 표에서는 행을 나눠 두었다.

- 시스템 카드: F064, F067, F082, F085, F086 (CPU·온도·디스크·GPU·USB가 같은 플라이아웃이나 Home 카드에 있다)
- 네트워크 카드: F065, F083, F084
- Packages 탭: F066, F068, F130
- 외장 모니터 패널: F075, F076, F077
- HUD 교체: F023, F074, F078, F079
- 배터리: F070, F071, F072, F073, F022
- 클립보드: F045, F046, F047, F048, F054, F098, F104
- 파일 선반: F049, F050, F055, F056, F057, F058, F059, F051
- 재생 중 컨트롤: F014, F015, F017, F018, F025, F026, F027, F119
- 앱별 오디오: F020, F021 (Sound Mixer 하나)
- 마이크 음소거: F024, F111 (같은 CoreAudio 음소거)
- 알림·통화: F106, F107, F108, F109, F110
- 잠금 화면: F116, F119, F117
- 런처: F090, F091 (같은 고정 앱 목록)
- 검색·계산: F093, F094, F103 (같은 검색 엔진·번역 경로)
- 타이머: F028, F029, F031, F032
- 캘린더: F038, F039, F040
- AI 사용량: F122, F123, F124, F125, F126, F120의 AI Usage 위젯

### /features/ 하단 "Guides and roundups" 23개

기능 가이드 수에 포함하지 않은 링크다. 기능 설명보다 비교·설치·호환성 안내가 목적이다.

| 링크 | 성격 |
|---|---|
| https://notchy.dev/demo/ | 브라우저 데모. "Ask AI" 탭이 데모에 있다(부록 참고) |
| https://notchy.dev/best-mac-notch-apps/ | 노치 앱 순위 비교 |
| https://notchy.dev/notchy-cpu-battery-usage/ | CPU·배터리 사용량 측정 |
| https://notchy.dev/blog/notchy-productivity-toolkit/ | 2026-07-20 블로그. 터미널·Camera Guard·Caps Lock HUD·Full Charge·Alt HUD·시각화·Liquid Glass 변형·사용자 대기 애니메이션 소개 |
| https://notchy.dev/how-to-get-dynamic-island-on-mac/ | 설치 안내 |
| https://notchy.dev/dynamic-island-macos-sequoia/ | macOS 15 호환성 안내 |
| https://notchy.dev/best-dynamic-island-apps-for-mac/ | 앱 순위 비교 |
| https://notchy.dev/macos-dynamic-island/ | 제품 소개 |
| https://notchy.dev/alcove-vs-boring-notch/ | 경쟁 앱 비교 |
| https://notchy.dev/must-have-mac-apps/ | 대체 가능한 앱 목록 |
| https://notchy.dev/uninstall-notchnook/ | 경쟁 앱 삭제 안내 |
| https://notchy.dev/uninstall-alcove/ | 경쟁 앱 삭제·구독 해지 안내 |
| https://notchy.dev/uninstall-mediamate/ | 경쟁 앱 삭제 안내 |
| https://notchy.dev/uninstall-boring-notch/ | 경쟁 앱 삭제 안내 |
| https://notchy.dev/is-boring-notch-safe/ | 경쟁 앱 안전성 설명 |
| https://notchy.dev/uninstall-dynamiclake/ | 경쟁 앱 삭제·구독 해지 안내 |
| https://notchy.dev/uninstall-sleeve/ | 경쟁 앱 삭제 안내 |
| https://notchy.dev/dynamic-island-macbook-air/ | 기종 호환성(MacBook Air M2~M5) |
| https://notchy.dev/dynamic-island-macbook-pro/ | 기종 호환성(MacBook Pro) |
| https://notchy.dev/dynamic-island-mac-mini/ | 기종 호환성(Mac mini·Studio·Pro, 알약 모드) |
| https://notchy.dev/iphone-dynamic-island-on-mac/ | 제품 소개 |
| https://notchy.dev/best-face-unlock-apps-for-mac/ | 얼굴 잠금 해제 앱 비교 |
| https://notchy.dev/dynamic-island-windows/ | Windows용 유사 프로젝트 안내(Notchy는 macOS 전용) |

## 현행 여부가 불분명한 항목

판단하지 않고 근거만 적었다. 체인지로그 확인은 다른 담당자가 한다.

| 항목 | 근거 | 확인할 점 |
|---|---|---|
| 사용자 Lottie 대기 애니메이션(Custom Idle Animation) | 홈페이지 카드 56번, 블로그(2026-07-20) 8번 항목, 가이드 페이지 공통 소개 목록에 있다. 전용 가이드는 없고 확인한 도움말 목록(85개)에도 없다 | 현재 앱에 남아 있는지 |
| GitHub PR 보기 | 홈페이지 "Building & shipping" 묶음에 "GitHub PRs"라는 이름과 "open PRs" 문구만 있다. 카드 74개, 가이드 131개, 도움말 어디에도 없다 | 기능이 있는지, 제거됐는지 |
| Google·Microsoft 직접 로그인 | F039는 Notchy 안에서 Google이나 Microsoft에 로그인하지 않고 macOS 인터넷 계정을 거친다고 명시한다. 직접 로그인 기능의 근거는 사이트에 없다 | 예전에 있다가 빠졌는지 |
| Microsoft To Do | F039 FAQ가 지원하지 않는다고 명시한다. 대신 Todoist 연동(토큰)이 있다 | 예전 지원 여부 |
| Liquid Glass 변형 개수 | 블로그는 Appearance에서 20개 변형을 고르는 선택기를 소개한다. F009는 6개(Smoke~Crystal)만 제공하며 Apple이 제공하는 20개 중 골랐다고 설명한다 | 블로그가 이전 버전 설명인지 |
| Face Unlock 생체 확인 방식 | F117은 깜빡임·고개 돌림 단서를 보고 Strict 모드는 깜빡임이나 실제 고개 움직임을 요구한다고 쓴다. 도움말(2026-10-11)은 1.0.207부터 요청형 회전·깜빡임 대신 수동적 생체 증거를 쓰고, 재생한 영상은 통과할 수 있다고 쓴다 (https://notchy.dev/help/is-face-unlock-secure/) | 현재 방식과 Light·Strict 모드 존재 여부 |
| 카메라·마이크 사용 알림 아일랜드 | 홈페이지 카드 51번은 카메라나 마이크가 켜지는 순간 알약이 켜진다고 쓴다. F111은 1.0.166부터 카메라·마이크 시작 때마다 아일랜드를 띄우지 않고 헤더 버튼 색과 Camera Guard로 대신한다고 쓴다 | 카드가 이전 동작인지 |
| 사용 통계 전송 끄기 | F045·F112 FAQ는 익명 설치 수 집계를 About → Privacy에서 끌 수 있다고 쓴다. 도움말은 하루 한 번 보내는 핑을 끌 수 없다고 쓴다 (https://notchy.dev/help/what-notchy-sends/) | 현재 설정 존재 여부 |
| 날씨 데이터 출처 | F081 소제목은 "Native WeatherKit"이고 본문은 Open-Meteo와 "Apple's APIs"를 함께 쓴다. 도움말은 Open-Meteo라고 쓴다 | WeatherKit 사용 흔적이 남은 이전 문구인지 |
| Fan Control (Beta) | 도움말에만 있고 "Beta"라고 표기되어 있다. 관리자 비밀번호로 백그라운드 헬퍼 설치, 팬별 Auto·Manual·Curve, 95°C에서 펌웨어로 반환 (https://notchy.dev/help/fan-control/). 카드·가이드에는 없다 | 정식 기능인지 |
| 자동 업데이트 베타 채널 | 홈페이지 카드 74번은 선택적 베타 채널을 언급한다. 도움말 업데이트 문서에는 베타 채널 언급이 없다 | 베타 채널 존재 여부 |
| Ask AI 탭 | /demo/와 도움말(https://notchy.dev/help/ask-ai-api-key/, features-off-after-install)에만 있다. 사용자 본인의 Anthropic API 키가 필요하다. 카드·가이드에는 없다 | 정식 기능인지 |
| Apple Music Favorite | 홈페이지 카드 2번은 Apple Music에서 한 번 눌러 Favorite한다고 쓴다. 가이드에는 Spotify ♥(F017)와 YouTube Music 👍(F025)만 있다 | 기능 존재 여부 |
| Now Playing 데스크톱 위젯 | F014는 데스크톱·알림 센터용 Now Playing 위젯이 없다고 쓴다. F120은 배경화면에 고정하는 Now Playing 위젯(AirPlay, 가사, 전체 화면 플레이어)을 설명하고, 도움말은 Floating Player를 설명한다 | F014 문구가 이전 버전 기준인지 |
| 언어 수 | F008 페이지 안에서 133개와 134개가 함께 나온다. 홈페이지는 134개다 | 정확한 수 |
| 기능 수 표기 | 홈페이지 74개, /features/ 131개 가이드, 가이드 공통 소개 목록 "Show all 51", 다른 페이지 "50+"·"40+"가 섞여 있다 | 수치 기준이 다른 것인지 |
| 명령 팔레트 단축키 | F092 본문은 ⌘K, 홈페이지와 F089는 ⌃⌥K라고 쓴다. 도움말은 전역 ⌃⌥K, 패널 안에서 ⌘K라고 정리한다 (https://notchy.dev/help/command-palette-find-files/) | 도움말 설명으로 해소된 것으로 보인다 |
| 설정 메뉴 이름 | 가이드와 도움말의 설정 경로 이름이 조금씩 다르다. 예: 설정 → Capture(F030·F099)와 Capture & Files(도움말), Provider Accounts(F122)와 Accounts & Credentials(도움말) | 현재 메뉴 이름 |

## 부록: 카드·가이드에 없고 도움말·데모에서만 확인한 기능

1~5절 범위 밖이지만 기능 맞추기에 필요할 수 있어 적는다. 도움말은 일부만 확인했다.

| 기능 | 내용 | 근거 |
|---|---|---|
| Ask AI 탭 | 노치에서 Claude에게 질문한다. 사용자 Anthropic API 키(키체인 저장), 대화는 메모리에만 보관 | https://notchy.dev/help/ask-ai-api-key/ , https://notchy.dev/demo/ |
| Local API | 설정 → About → Developer에서 켜면 `127.0.0.1:9999`에서 토큰이 붙은 줄 단위 JSON(TCP, HTTP 아님)을 받는다. 명령 없이 보내면 제목·부제·진행률 아일랜드를 띄운다. 토큰 재발급, 기본 꺼짐 | https://notchy.dev/help/local-api/ |
| Fan Control (Beta) | 5절 참고 | https://notchy.dev/help/fan-control/ |
| Floating Player | 창 위에 떠 있는 Now Playing 플레이어. ⌘1~4로 미니·기본·가사·아트워크 크기 전환 | https://notchy.dev/help/floating-player/ |
| 뽀모도로 앱 차단 | 집중 중 지정 앱이 앞으로 나오면 숨긴다(종료하지 않음) | https://notchy.dev/help/pomodoro-block-apps/ |
| 명령 팔레트 파일 검색 | 홈 폴더 파일·폴더와 클립보드 텍스트를 함께 검색한다 | https://notchy.dev/help/command-palette-find-files/ |
| 햅틱 피드백 | 설정 → Appearance → Motion의 Haptic Feedback, 타이머 종료는 두 번 진동 | https://notchy.dev/help/double-haptic-click/ |
| 설정 백업·동기화 | `.notchysettings` 내보내기·가져오기, iCloud 설정 동기화(기본 꺼짐) | https://notchy.dev/help/backup-settings/ |
| 전체 화면에서 숨기기 | Hide in Full Screen, 상단 가운데를 건드리면 다시 보이기, Notifications-Only Mode | https://notchy.dev/help/hidden-in-full-screen/ |
| 화면 공유 시 숨기기 | Hidden from Captures·Hidden Everywhere·Hide While Mirroring, ⌥Space로 즉시 숨기기 | https://notchy.dev/help/hide-during-screen-sharing/ |
| Minimal Layout | 고른 탭·헤더 버튼만 남기고 알약·패널을 작게 그린다. Favorite Tabs | https://notchy.dev/help/minimal-layout/ |
| Tabs Beside the Notch | 노치 왼쪽에 탭, 오른쪽에 헤더 버튼 배치(노치 필요) | https://notchy.dev/help/tabs-beside-notch/ |
| 앱 자체 업데이트 | 약 1시간마다 확인, 백그라운드 다운로드, 종료 시 설치, 너무 오래된 버전은 Update Required 창 | https://notchy.dev/help/update-notchy/ , https://notchy.dev/help/update-required-window/ |
| 내장 삭제 도구 | 설정 → About → App → Uninstall Notchy가 설정·권한 기록·키체인 항목·셸·에이전트 훅·충전 헬퍼를 지우고 앱을 휴지통으로 옮긴다 | https://notchy.dev/uninstall/ |
