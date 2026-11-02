#!/bin/bash
# 검토용 "Dynamic Notch Review.app" 빌드·실행 (설치된 /Applications/Dynamic Notch.app 은 건드리지 않는다)
# Build and run a side-by-side review copy without touching the installed app.
#
# 사용법 / Usage: scripts/review.sh <build|start|stop|status>
#   build   ~/Developer/Dynamic-Notch-build/review/ 에 검토용 앱을 만든다
#   start   설치된 앱을 정상 종료하고 검토용 앱을 띄운다 (두 앱이 같은 노치에 겹쳐 그리지 않게)
#   stop    검토용 앱을 끝내고 설치된 앱을 다시 띄운다
#   status  어느 쪽이 실행 중인지 보여 준다
#
# 검토용 앱은 번들 ID·실행 파일 이름·앱 이름이 모두 달라서 설정(UserDefaults)·권한(TCC)·프로세스가 설치본과 섞이지 않는다.
# 다만 분산 알림 채널(com.dynamicnotch.app.command 등)은 같으므로 두 앱을 동시에 켜 두지 않는다.
# SwiftPM 매니페스트 링크가 깨진 Mac에서도 되도록 swiftc로 직접 빌드한다.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Dynamic Notch Review"
EXE="DynamicNotchReview"
BUNDLE_ID="com.dynamicnotch.app.review"
INSTALLED_ID="com.dynamicnotch.app"
MIN_OS="14.0"
# REVIEW_OUT으로 출력 폴더를 바꿀 수 있다 (여러 작업 폴더에서 동시에 빌드할 때)
OUT="${REVIEW_OUT:-$HOME/Developer/Dynamic-Notch-build/review}"
APP="$OUT/$NAME.app"

build() {
  mkdir -p "$OUT/obj"
  local src="$PWD"
  swiftc -O -wmo -target arm64-apple-macosx$MIN_OS -swift-version 5 -module-name DynamicNotch \
    -file-prefix-map "$src=." -debug-prefix-map "$src=." \
    $(find Sources/DynamicNotch -name '*.swift' | sort) -o "$OUT/obj/$EXE"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$OUT/obj/$EXE" "$APP/Contents/MacOS/$EXE"
  strip -x "$APP/Contents/MacOS/$EXE"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" \
    -c "Set :CFBundleExecutable $EXE" -c "Set :CFBundleName $NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $NAME" "$APP/Contents/Info.plist"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"
  # 언어별 표시 이름도 바꿔 시스템 설정(로그인 항목·개인정보 목록)에서 설치 앱과 구별되게 한다
  sed -i '' "s/\"CFBundleDisplayName\" = \"[^\"]*\";/\"CFBundleDisplayName\" = \"$NAME\";/" \
    "$APP/Contents/Resources/en.lproj/InfoPlist.strings" "$APP/Contents/Resources/ko.lproj/InfoPlist.strings"
  # 설치 이름을 고정해 빌드 위치가 바뀌어도 같은 바이너리가 나오게 한다
  clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min="$MIN_OS" -framework Foundation \
    -install_name @rpath/libMRAdapter.dylib \
    -o "$APP/Contents/Resources/libMRAdapter.dylib" Sources/MediaRemoteAdapter/adapter.m
  cp Sources/MediaRemoteAdapter/run.pl "$APP/Contents/Resources/mr_run.pl"
  codesign --force --deep --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
  codesign --verify --deep --strict "$APP"
  echo "built: $APP"
}

running() { pgrep -f "$1.app/Contents/MacOS/" >/dev/null; }

# 설정·권한 창 도우미도 같은 번들 ID라 종료 요청이 그쪽에 먼저 갈 수 있다. 모두 끝날 때까지 2초마다 다시 요청한다.
quit_app() {
  for i in $(seq 0 59); do
    running "$2" || return 0
    [ $((i % 8)) -eq 0 ] && { osascript -e "tell application id \"$1\" to quit" >/dev/null 2>&1 || true; }
    sleep 0.25
  done
  echo "warning: $2 did not quit" >&2
}

case "${1:-}" in
  build) build ;;
  start)
    [ -d "$APP" ] || build
    # 검토용 앱에서는 첫 안내(권한 요청·로그인 시 열기)를 띄우지 않는다. 설치 앱과 이름이 같은 항목이 시스템 설정에 생기지 않게.
    defaults write "$BUNDLE_ID" onboardingDone -bool true
    quit_app "$INSTALLED_ID" "Dynamic Notch"
    open "$APP"
    ;;
  stop)
    quit_app "$BUNDLE_ID" "$NAME"
    open -b "$INSTALLED_ID"
    ;;
  status)
    running "Dynamic Notch" && echo "installed: running" || echo "installed: not running"
    running "$NAME" && echo "review: running" || echo "review: not running"
    ;;
  *) echo "usage: scripts/review.sh <build|start|stop|status>" >&2; exit 1 ;;
esac
