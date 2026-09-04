#!/bin/bash
# 로컬 전용 자체 서명 코드사이닝 인증서 생성 + 키체인 등록 (1회만 실행).
# 이후 make_app.sh가 이 인증서로 서명하면 재빌드해도 화면 기록 권한이 유지된다.
set -euo pipefail

NAME="CaptureToPrompt Dev"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "1) 인증서 생성..."
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -subj "/CN=$NAME" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "keyUsage=digitalSignature" \
  -addext "basicConstraints=critical,CA:FALSE" 2>/dev/null

# OpenSSL 3의 기본 p12 암호화는 macOS 키체인이 못 읽으므로 -legacy 필요
# (LibreSSL 등 -legacy 미지원 openssl은 기본값이 이미 호환되므로 폴백)
if ! openssl pkcs12 -export -legacy -out "$TMP/dev.p12" -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" -password pass:c2ptemp 2>/dev/null; then
  openssl pkcs12 -export -out "$TMP/dev.p12" -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" -password pass:c2ptemp
fi

echo "2) 로그인 키체인에 등록 (암호 입력 창이 뜰 수 있음)..."
security import "$TMP/dev.p12" -k ~/Library/Keychains/login.keychain-db \
  -P c2ptemp -T /usr/bin/codesign

echo "3) 인증서 신뢰 설정 (관리자 암호 창이 뜰 수 있음)..."
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMP/cert.pem"

echo "4) 확인:"
security find-identity -v -p codesigning | grep "$NAME" && echo "✅ 등록 완료"
