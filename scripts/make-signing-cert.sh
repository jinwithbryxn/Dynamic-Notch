#!/bin/bash
# 이 Mac에서만 쓰는 코드 서명 인증서("Dynamic Notch Local Signing")를 로그인 키체인에 만든다. 한 번만 하면 된다.
# Creates a code signing certificate for this Mac ("Dynamic Notch Local Signing") in the login keychain. Run once.
#
# 사용법 / Usage: scripts/make-signing-cert.sh
#
# - 개인 키는 키체인 안에만 남는다. 만드는 동안의 임시 파일은 끝나면 지운다.
#   The private key stays in the keychain; the temporary files are removed when the script ends.
# - 키는 codesign만 묻지 않고 쓸 수 있게 넣는다. 인증서 신뢰 설정은 바꾸지 않는다(서명에는 필요 없다).
#   Only codesign may use the key without asking. Certificate trust settings are left alone (signing does not need them).
# - 이후 build.sh·install-local.sh·review.sh가 이 인증서로 서명한다(scripts/sign.sh).
#   build.sh, install-local.sh and review.sh then sign with it (scripts/sign.sh).
# - 애드혹 앱에서 처음 바꿀 때 macOS 권한은 그대로 이어진다. 다만 시스템이 저장해 둔 요구사항은 예전 것(번들 ID만)이라,
#   보호가 실제로 걸리려면 권한을 한 번 지우고 다시 허용해야 한다(README의 '서명' 참고).
#   Permissions carry over from the ad hoc app, but the stored requirement is still the old bundle-ID-only one;
#   remove and allow the permissions once for the protection to apply (see "Signing" in the README).
# - 인증서를 지우거나 키체인을 새로 만들면 새 인증서로 서명한 앱은 권한을 다시 허용해야 한다.
#   If the certificate is deleted or the keychain is reset, an app signed with a new certificate needs the permissions again.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sign.sh

KEYCHAIN="${DMN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
existing="$(DMN_SIGN_IDENTITY="" dmn_sign_identity)"
if [ -n "$existing" ]; then
  echo "already in the keychain: $DMN_LOCAL_CERT_NAME ($existing)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# macOS의 LibreSSL은 키체인이 읽을 수 있는 PKCS#12 형식(3DES·SHA-1 MAC)을 기본으로 만든다.
# macOS LibreSSL writes PKCS#12 in the format the keychain can read (3DES, SHA-1 MAC) by default.
OPENSSL=/usr/bin/openssl
cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $DMN_LOCAL_CERT_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/req.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"   # 임시 파일을 감싸는 일회용 암호 / one-time password for the temporary file
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$DMN_LOCAL_CERT_NAME" \
  -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "created: $DMN_LOCAL_CERT_NAME ($(security find-certificate -c "$DMN_LOCAL_CERT_NAME" -Z "$KEYCHAIN" | awk '/SHA-1/ { print $3; exit }'))"
