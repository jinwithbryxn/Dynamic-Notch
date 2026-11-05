#!/bin/bash
# 개인 빌드를 /Applications 에 설치·복원한다. 설치 전 지금 앱과 설정을 백업하고, 기존 앱은 지우지 않고 백업 폴더로 옮긴다.
# Install or restore the personal build. The current app and settings are backed up first; the old app is moved, never deleted.
#
# 사용법 / Usage: scripts/install-local.sh <build|install|restore <백업 폴더>|backups>
#   build     build/install/ 에 설치용 앱을 만든다 (INSTALL_OUT으로 바꿀 수 있음) (번들 ID com.dynamicnotch.app)
#   install   build 후 백업 → 앱 종료 → 교체 → 다시 실행
#   restore   백업 폴더의 앱(과 settings.plist)으로 되돌린다
#   backups   백업 목록
#
# 설정(UserDefaults)·권한(TCC)·키체인 항목은 번들 ID와 서명 요구사항(번들 ID, 인증서가 있으면 번들 ID + 인증서)이 같아 그대로 이어진다 (scripts/sign.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sign.sh

NAME="Dynamic Notch"
EXE="DynamicNotch"
BUNDLE_ID="com.dynamicnotch.app"
MIN_OS="14.0"
OUT="${INSTALL_OUT:-$PWD/build/install}"
BUILT="$OUT/$NAME.app"
TARGET="/Applications/$NAME.app"
BACKUP_ROOT="$HOME/.local/share/dynamic-notch-agent/backups"

build() {
  mkdir -p "$OUT/obj"
  local src="$PWD"
  swiftc -O -wmo -target arm64-apple-macosx$MIN_OS -swift-version 5 -module-name "$EXE" \
    -file-prefix-map "$src=." -debug-prefix-map "$src=." \
    $(find Sources/DynamicNotch -name '*.swift' | sort) -o "$OUT/obj/$EXE"
  rm -rf "$BUILT"
  mkdir -p "$BUILT/Contents/MacOS" "$BUILT/Contents/Resources"
  cp "$OUT/obj/$EXE" "$BUILT/Contents/MacOS/$EXE"
  strip -x "$BUILT/Contents/MacOS/$EXE"
  cp Resources/Info.plist "$BUILT/Contents/Info.plist"
  cp Resources/AppIcon.icns "$BUILT/Contents/Resources/AppIcon.icns"
  cp -R Resources/en.lproj Resources/ko.lproj "$BUILT/Contents/Resources/"
  clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min="$MIN_OS" -framework Foundation \
    -install_name @rpath/libMRAdapter.dylib \
    -o "$BUILT/Contents/Resources/libMRAdapter.dylib" Sources/MediaRemoteAdapter/adapter.m
  cp Sources/MediaRemoteAdapter/run.pl "$BUILT/Contents/Resources/mr_run.pl"
  sign_app "$BUILT" "$BUNDLE_ID"
  echo "built: $BUILT ($(git rev-parse --short HEAD))"
}

# 앱 번들의 Info.plist 값 (번들 ID·실행 파일 이름이 이 빌드와 다른 예전 앱·백업도 그 앱의 값으로 다룬다)
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

# 설정·권한 창은 같은 번들 ID의 도우미 프로세스라 종료 요청이 도우미에 먼저 갈 수 있다.
# 본 앱과 도우미가 모두 끝날 때까지 2초마다 다시 요청한다 (최대 15초).
quit_app() {
  local id="$1" exe="$2"
  for i in $(seq 0 59); do
    pgrep -f "/$NAME\.app/Contents/MacOS/$exe" >/dev/null || return 0
    [ $((i % 8)) -eq 0 ] && { osascript -e "tell application id \"$id\" to quit" >/dev/null 2>&1 || true; }
    sleep 0.25
  done
  echo "error: $NAME did not quit; nothing was replaced" >&2
  exit 1
}

# 지금 설치된 앱을 끈다. 번들 ID가 이 빌드와 다르면 그 앱의 ID와 실행 파일 이름으로 끈다
quit_installed() {
  if [ -d "$TARGET" ]; then
    quit_app "$(plist "$TARGET" CFBundleIdentifier)" "$(plist "$TARGET" CFBundleExecutable)"
  fi
  quit_app "$BUNDLE_ID" "$EXE"
}

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# 백업 폴더로 옮긴 앱도 같은 번들 ID로 등록돼 있어, 'open -b'가 그쪽을 띄울 수 있다 (2026-11-04).
# 옮긴 앱은 등록을 지우고, 설치한 경로를 직접 연 뒤 그 경로의 프로세스인지 확인한다.
launch() {
  "$LSREGISTER" -f "$TARGET" || true
  for _ in 1 2 3 4 5; do
    open "$TARGET" && sleep 2 && pgrep -f "^$TARGET/Contents/MacOS/$EXE" >/dev/null && { echo "running: $TARGET"; return 0; }
    sleep 1
  done
  echo "warning: $NAME did not start; run: open \"$TARGET\"" >&2
}

install() {
  build
  local stamp dir
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="$BACKUP_ROOT/$stamp"
  mkdir -p "$dir"
  # 설정은 지금 설치된 앱의 번들 ID로 백업한다 (restore가 같은 ID로 되돌린다)
  local old_id="$BUNDLE_ID"
  [ -d "$TARGET" ] && old_id="$(plist "$TARGET" CFBundleIdentifier)"
  defaults export "$old_id" "$dir/settings.plist" 2>/dev/null || true
  git rev-parse HEAD > "$dir/installed-commit.txt"
  quit_installed
  if [ -d "$TARGET" ]; then
    # 기존 앱은 지우지 않고 백업 폴더로 옮긴다 (되돌리기용)
    mv "$TARGET" "$dir/$NAME.app"
    "$LSREGISTER" -u "$dir/$NAME.app" 2>/dev/null || true
  fi
  if [ "$old_id" != "$BUNDLE_ID" ]; then
    echo "note: the installed app had bundle ID $old_id; this build is $BUNDLE_ID, so macOS treats it as a new app (permissions and the login item start fresh; settings are not copied)"
  fi
  ditto "$BUILT" "$TARGET"
  codesign --verify --deep --strict "$TARGET"
  # 빌드 폴더의 사본이 같은 번들 ID로 등록돼 있으면 'open -b'·시스템 설정이 그쪽을 가리킬 수 있어 등록을 지운다
  "$LSREGISTER" -u "$BUILT" 2>/dev/null || true
  echo "backup: $dir"
  launch
}

restore() {
  local dir="${1:?usage: scripts/install-local.sh restore <backup folder>}"
  # 백업 폴더의 앱 이름·번들 ID·실행 파일 이름이 이 빌드와 달라도 그 앱의 값 그대로 되돌린다
  local app
  app="$(find "$dir" -maxdepth 1 -name '*.app' | head -1)"
  [ -n "$app" ] || { echo "error: no app in $dir" >&2; exit 1; }
  local id exe stamp
  id="$(plist "$app" CFBundleIdentifier)"
  exe="$(plist "$app" CFBundleExecutable)"
  stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_ROOT/replaced-$stamp"
  quit_installed
  if [ -d "$TARGET" ]; then
    mv "$TARGET" "$BACKUP_ROOT/replaced-$stamp/$NAME.app"
    "$LSREGISTER" -u "$BACKUP_ROOT/replaced-$stamp/$NAME.app" 2>/dev/null || true
  fi
  TARGET="/Applications/$(basename "$app")"
  EXE="$exe"
  ditto "$app" "$TARGET"
  if [ -f "$dir/settings.plist" ]; then
    defaults export "$id" "$BACKUP_ROOT/replaced-$stamp/settings.plist" 2>/dev/null || true
    defaults import "$id" "$dir/settings.plist"
  fi
  echo "restored from: $dir (replaced app kept in $BACKUP_ROOT/replaced-$stamp)"
  launch
}

case "${1:-}" in
  build) build ;;
  install) install ;;
  restore) restore "${2:-}" ;;
  backups) ls -1 "$BACKUP_ROOT" 2>/dev/null || echo "(no backups)" ;;
  *) echo "usage: scripts/install-local.sh <build|install|restore <dir>|backups>" >&2; exit 1 ;;
esac
