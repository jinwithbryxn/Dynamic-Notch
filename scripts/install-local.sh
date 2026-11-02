#!/bin/bash
# 개인 빌드를 /Applications 에 설치·복원한다. 설치 전 지금 앱과 설정을 백업하고, 기존 앱은 지우지 않고 백업 폴더로 옮긴다.
# Install or restore the personal build. The current app and settings are backed up first; the old app is moved, never deleted.
#
# 사용법 / Usage: scripts/install-local.sh <build|install|restore <백업 폴더>|backups>
#   build     ~/Developer/Dynamic-Notch-build/install/ 에 설치용 앱을 만든다 (번들 ID com.dynamicnotch.app)
#   install   build 후 백업 → 앱 종료 → 교체 → 다시 실행
#   restore   백업 폴더의 앱(과 settings.plist)으로 되돌린다
#   backups   백업 목록
#
# 설정(UserDefaults)·권한(TCC)·키체인 항목은 번들 ID와 서명 요구사항(식별자 고정)이 같아 그대로 이어진다.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Dynamic Notch"
EXE="DynamicNotch"
BUNDLE_ID="com.dynamicnotch.app"
MIN_OS="14.0"
OUT="$HOME/Developer/Dynamic-Notch-build/install"
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
  codesign --force --deep --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$BUILT"
  codesign --verify --deep --strict "$BUILT"
  echo "built: $BUILT ($(git rev-parse --short HEAD))"
}

running() { pgrep -f "/$NAME.app/Contents/MacOS/$EXE" >/dev/null; }

# 설정·권한 창은 같은 번들 ID의 도우미 프로세스라 종료 요청이 도우미에 먼저 갈 수 있다.
# 본 앱과 도우미가 모두 끝날 때까지 2초마다 다시 요청한다 (최대 15초).
quit_app() {
  for i in $(seq 0 59); do
    running || return 0
    [ $((i % 8)) -eq 0 ] && { osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true; }
    sleep 0.25
  done
  echo "error: $NAME did not quit; nothing was replaced" >&2
  exit 1
}

launch() {
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET" || true
  for _ in 1 2 3 4 5; do
    open -b "$BUNDLE_ID" && sleep 2 && running && { echo "running: $TARGET"; return 0; }
    sleep 1
  done
  echo "warning: $NAME did not start; run: open -b $BUNDLE_ID" >&2
}

install() {
  build
  local stamp dir
  stamp=$(date +%Y%m%d-%H%M%S)
  dir="$BACKUP_ROOT/$stamp"
  mkdir -p "$dir"
  defaults export "$BUNDLE_ID" "$dir/settings.plist"
  git rev-parse HEAD > "$dir/installed-commit.txt"
  quit_app
  if [ -d "$TARGET" ]; then
    # 기존 앱은 지우지 않고 백업 폴더로 옮긴다 (되돌리기용)
    mv "$TARGET" "$dir/$NAME.app"
  fi
  ditto "$BUILT" "$TARGET"
  codesign --verify --deep --strict "$TARGET"
  echo "backup: $dir"
  launch
}

restore() {
  local dir="${1:?usage: scripts/install-local.sh restore <backup folder>}"
  [ -d "$dir/$NAME.app" ] || { echo "error: no app in $dir" >&2; exit 1; }
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$BACKUP_ROOT/replaced-$stamp"
  quit_app
  [ -d "$TARGET" ] && mv "$TARGET" "$BACKUP_ROOT/replaced-$stamp/$NAME.app"
  ditto "$dir/$NAME.app" "$TARGET"
  if [ -f "$dir/settings.plist" ]; then
    defaults export "$BUNDLE_ID" "$BACKUP_ROOT/replaced-$stamp/settings.plist"
    defaults import "$BUNDLE_ID" "$dir/settings.plist"
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
