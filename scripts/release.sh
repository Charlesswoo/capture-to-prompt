#!/bin/bash
# 로컬에서 빌드해 GitHub Release로 배포한다.
#   ./scripts/release.sh 0.2.0 "릴리스 노트"
#
# 하는 일: Info.plist 버전 갱신 → 앱 빌드·서명 → zip → 태그 → gh release create
# 앱은 이 릴리스의 zip을 내려받아 자기 자신을 교체한다 (UpdateChecker/UpdateInstaller).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES="${2:-}"
if [[ -z "$VERSION" ]]; then
  echo "사용법: ./scripts/release.sh <버전> [릴리스 노트]"
  echo "예:    ./scripts/release.sh 0.2.0 \"포즈 추출·병렬 분석 추가\""
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "❌ 버전 형식이 올바르지 않습니다: $VERSION (예: 0.2.0)"
  exit 1
fi

# 커밋되지 않은 변경이 있으면 어떤 소스로 빌드됐는지 추적할 수 없다
if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ 커밋되지 않은 변경이 있습니다. 커밋 후 다시 실행하세요."
  git status --short
  exit 1
fi

echo "▶︎ 버전 $VERSION 로 Info.plist 갱신"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD_NUMBER=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Resources/Info.plist

echo "▶︎ 테스트"
swift test 2>&1 | tail -3

echo "▶︎ 앱 빌드·서명"
./scripts/make_app.sh >/dev/null

ZIP="dist/CaptureToPrompt.zip"
rm -f "$ZIP"
echo "▶︎ zip 생성 (ditto — 서명·심볼릭 링크 보존)"
ditto -c -k --keepParent dist/CaptureToPrompt.app "$ZIP"
echo "   $(du -h "$ZIP" | cut -f1)"

echo "▶︎ 버전 커밋 & 태그"
git add Resources/Info.plist
git commit -q -m "build: $VERSION"
git tag "v$VERSION"
git push -q origin main --tags

echo "▶︎ GitHub Release 발행"
if [[ -n "$NOTES" ]]; then
  gh release create "v$VERSION" "$ZIP" --title "$VERSION" --notes "$NOTES"
else
  gh release create "v$VERSION" "$ZIP" --title "$VERSION" --generate-notes
fi

echo "✅ 배포 완료 — 앱에서 '업데이트 확인'을 누르면 이 버전이 잡힙니다."
