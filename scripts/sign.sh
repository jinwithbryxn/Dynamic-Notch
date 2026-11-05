# shellcheck shell=bash
# 앱 서명 (build.sh, install-local.sh, review.sh가 불러 쓴다)
# Signs the app bundle (sourced by build.sh, install-local.sh and review.sh).
#
# 실행 보호(hardened runtime)를 켜고 Resources/DynamicNotch.entitlements에 적은 허가만 준다.
# 다른 프로그램이 DYLD 환경 변수 등으로 이 앱에 코드를 끼워 넣어 앱의 권한을 빌려 쓰지 못한다.
# 허가 목록: 카메라, 마이크, 위치, 캘린더·미리 알림, Apple Events(Music·Spotify 제어). 실행 보호에서는 이 다섯이
# 허가 없이 막히고, 나머지 권한(손쉬운 사용, 화면 녹화, 입력 모니터링, 블루투스 등)은 macOS 권한(TCC)만 본다.
# Turns on the hardened runtime with only the entitlements in Resources/DynamicNotch.entitlements, so other
# programs cannot inject code (DYLD variables and the like) and borrow the app's permissions. Camera, microphone,
# location, calendars/reminders and Apple Events need an entitlement under the hardened runtime; the other
# permissions only go through TCC.
#
# 서명 신원: DMN_SIGN_IDENTITY(인증서 이름이나 SHA-1) > 키체인의 "Dynamic Notch Local Signing"
# (scripts/make-signing-cert.sh로 만든다) > 애드혹.
# 인증서로 서명하면 지정 요구사항이 '번들 ID + 인증서 지문'이 되어, 같은 번들 ID를 단 다른 앱은 새로 허용한
# 권한을 이어받지 못한다. 애드혹이면 지금처럼 번들 ID만으로 고정해 업데이트해도 권한이 유지된다.
# Identity: DMN_SIGN_IDENTITY (name or SHA-1) > the "Dynamic Notch Local Signing" certificate in the keychain
# (made by scripts/make-signing-cert.sh) > ad hoc. With a certificate the designated requirement is the bundle ID
# plus the certificate hash, so another app with the same bundle ID cannot inherit newly granted permissions;
# ad hoc keeps the bundle-ID-only requirement so permissions survive updates.

DMN_LOCAL_CERT_NAME="Dynamic Notch Local Signing"
DMN_ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Resources/DynamicNotch.entitlements"

# 쓸 서명 신원 (없으면 빈 값). 신뢰 설정을 바꾸지 않은 자체 서명 인증서는 '유효한 신원'으로 잡히지 않으므로
# -v 없이 찾고, 이름이 겹쳐도 하나로 정해지게 SHA-1 지문을 돌려준다.
# The identity to use, or empty. A self-signed certificate without trust settings is not a "valid" identity,
# so search without -v and return its SHA-1 so a duplicate name cannot make it ambiguous.
dmn_sign_identity() {
  if [ -n "${DMN_SIGN_IDENTITY:-}" ]; then echo "$DMN_SIGN_IDENTITY"; return; fi
  security find-identity -p codesigning 2>/dev/null \
    | awk -v n="\"$DMN_LOCAL_CERT_NAME\"" 'index($0, n) { print $2; exit }'
}

# sign_app <앱 경로> <번들 ID>
sign_app() {
  local app="$1" id="$2" who
  who="$(dmn_sign_identity)"
  if [ -n "$who" ]; then
    codesign --force --sign "$who" --timestamp=none "$app/Contents/Resources/libMRAdapter.dylib"
    codesign --force --sign "$who" --timestamp=none --options runtime --entitlements "$DMN_ENTITLEMENTS" "$app"
  else
    codesign --force --sign - "$app/Contents/Resources/libMRAdapter.dylib"
    codesign --force --sign - --options runtime --entitlements "$DMN_ENTITLEMENTS" \
      --requirements "=designated => identifier \"$id\"" "$app"
  fi
  codesign --verify --deep --strict "$app"
  local details
  details="$(codesign -dv "$app" 2>&1)"
  grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$details" \
    || { echo "error: hardened runtime is off: $app" >&2; return 1; }
  if [ -n "$who" ]; then echo "signed: $app (certificate $who, hardened runtime)"
  else echo "signed: $app (ad hoc, hardened runtime)"; fi
}
