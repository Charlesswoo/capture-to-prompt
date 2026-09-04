#!/bin/bash
# 릴리스 빌드 → dist/CaptureToPrompt.app 번들 생성 → 코드서명
# --install: 빌드 후 /Applications 에 복사 (Spotlight/Alfred 검색은 표준 위치만 봄)
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

swift build -c release

APP=dist/CaptureToPrompt.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/CaptureToPrompt "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# 지역화 리소스 (ko 기본 + en) — 시스템 메뉴·UI 문자열이 시스템 언어를 따른다
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# 자체 서명 인증서가 있으면 그걸로 서명 (재빌드해도 TCC 권한 유지),
# 없으면 ad-hoc 폴백 (빌드마다 권한 재요청됨 — scripts/setup_signing.sh 참고)
IDENTITY="CaptureToPrompt Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "서명: $IDENTITY (권한 유지됨)"
else
    codesign --force --sign - "$APP"
    echo "⚠️  ad-hoc 서명 — 재빌드 시 화면 기록 권한이 초기화됩니다. scripts/setup_signing.sh를 실행하세요."
fi

echo "✅ 생성 완료: $APP"

if [[ "$INSTALL" == "1" ]]; then
    DEST=/Applications/CaptureToPrompt.app
    # 실행 중이면 교체 후 안내 (파일 교체 자체는 가능)
    RUNNING=$(pgrep -x CaptureToPrompt || true)
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # LaunchServices에 즉시 등록 (Spotlight/Alfred 반영)
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
    echo "✅ 설치 완료: $DEST"
    [[ -n "$RUNNING" ]] && echo "⚠️  실행 중인 앱(pid $RUNNING)은 종료 후 다시 열어야 새 버전이 적용됩니다."
else
    echo "   실행: open $APP"
    echo "   설치: $0 --install  (/Applications 복사 — Spotlight/Alfred 검색 가능)"
fi
