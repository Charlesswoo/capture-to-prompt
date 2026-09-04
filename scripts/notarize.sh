#!/bin/bash
# Developer ID 서명 + 공증 + 스테이플 → 배포용 zip 생성.
#
# 사전 준비 (1회):
#   1. 이 Mac에 "Developer ID Application" 인증서 + 개인키 설치
#      (Xcode → Settings → Accounts → 팀 로그인 후 발급, 또는 팀 관리자에게 .p12 받아 더블클릭)
#   2. 공증 자격증명 저장:
#      xcrun notarytool store-credentials c2p-notary \
#        --apple-id <애플ID 이메일> --team-id <팀ID> --password <앱 암호>
#      (앱 암호는 appleid.apple.com → 로그인 및 보안 → 앱 암호에서 생성.
#       또는 App Store Connect API 키를 쓰려면 --key/--key-id/--issuer 사용)
#
# 사용법:
#   ./scripts/notarize.sh "Developer ID Application: SpoonLabs Inc. (XXXXXXXXXX)"
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${1:?사용법: notarize.sh \"Developer ID Application: 이름 (팀ID)\"}"
PROFILE="${2:-c2p-notary}"
APP=dist/CaptureToPrompt.app
ZIP=dist/CaptureToPrompt.zip

# 1. 빌드 (서명은 여기서 다시 하므로 make_app의 서명은 덮어씀)
./scripts/make_app.sh

# 2. Developer ID + hardened runtime 서명 (공증 필수 조건)
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "✅ Developer ID 서명 완료"

# 3. 공증 제출 (--wait: 완료까지 대기, 보통 수 분)
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# 4. 공증 티켓 부착 (오프라인에서도 Gatekeeper 통과)
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 5. 배포용 zip 재생성 (스테이플된 앱 기준)
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✅ 배포 준비 완료: $ZIP — 아무 Mac에서나 더블클릭 실행 가능"
