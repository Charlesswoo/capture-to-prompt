# CaptureToPrompt

이미지 → AI 이미지 생성 프롬프트 변환 macOS 앱.
크롬 확장 [PromptCard - Image to Prompt](https://chromewebstore.google.com/detail/promptcard-image-to-promp/pdiegjclbkenbildadfjggoidpkplbmd)의 데스크톱 버전으로,
화면 캡처·클립보드·파일 이미지를 Claude vision으로 분석해 주제·구성·스타일·조명·색감·분위기를
담은 생성용 프롬프트를 **한국어/영어/일본어 + JSON**으로 만들어 준다.

## 기능

- **전역 단축키 캡처 (기본 ⌥⇧C)** — 어느 앱에 있든 키를 누르면 **마우스 커서 아래 창을
  자동 인식**해 그 창만 캡처·분석 (클릭·드래그 불필요). 설정에서 ⌘⇧2 / ⌃⇧S로 변경 가능
- **창 선택 캡처** — 카메라 커서로 원하는 창을 클릭해 그 창만 캡처·분석 (`screencapture -W`)
- **영역 선택 캡처** — 메뉴바 아이콘 또는 툴바 버튼으로 화면 영역을 직접 선택해 분석
- **클립보드 / 드래그 앤 드롭 / 파일 열기** 로 이미지 입력
- 결과 탭: 한국어 · English · 日本語 · JSON (+ 주제/스타일/조명 등 breakdown, 태그)
- **원클릭 복사**
- **로컬 히스토리** — `~/Library/Application Support/CaptureToPrompt/` 에 저장
- 설정에서 API 키·모델(opus/sonnet/haiku) 선택

## 요구 사항

- macOS 26 (Tahoe) 이상, Xcode 26 / Swift 6 툴체인 — Liquid Glass 디자인 API 사용
- 분석 백엔드 (설정에서 선택, 둘 중 하나):
  - **Claude Code CLI** (기본값) — 로컬에 로그인된 `claude` CLI를 호출. **API 키 불필요**, 구독 사용량 사용
  - **Anthropic API 키** — 설정 창에 입력하거나 `ANTHROPIC_API_KEY` 환경변수

## 빌드 & 실행

```bash
# 개발 실행
swift run

# 테스트
swift test

# 앱 번들 생성 (dist/CaptureToPrompt.app)
./scripts/make_app.sh
open dist/CaptureToPrompt.app
```

## 트러블슈팅

- **캡처가 검게 나오거나 선택 UI가 안 뜸** — 시스템 설정 → 개인정보 보호 및 보안 →
  화면 기록에서 CaptureToPrompt 허용 후 앱 재시작.
- **권한을 허용해도 계속 다시 요청함** — ad-hoc 서명은 빌드마다 정체성이 바뀌어 생기는
  문제. `bash scripts/setup_signing.sh`로 자체 서명 인증서를 1회 등록하면
  `make_app.sh`가 그걸로 서명해 재빌드에도 권한이 유지된다. 꼬인 기록은
  `tccutil reset ScreenCapture com.charles.capture-to-prompt`로 초기화.
- **"claude CLI를 찾을 수 없습니다"** — Claude Code 설치 여부 확인. 앱은
  `~/.local/bin`, `~/.claude/local`, `/usr/local/bin`, `/opt/homebrew/bin`에서 찾는다.
- **"API 키가 없습니다"** (API 키 백엔드일 때) — 앱 메뉴 → Settings에서 키 입력.
  `.app`으로 실행하면 셸의 환경변수가 전달되지 않으므로 설정 입력을 권장.
- **API 오류 401** — 키가 유효한지, 워크스페이스 권한이 있는지 확인.
- CLI 백엔드는 요청당 30~60초 정도 걸린다 (헤드리스 Claude Code 세션 구동 비용).

## 구조

```
Sources/CaptureToPrompt/
  PromptAnalyzer.swift     # Anthropic Messages API 호출 (raw HTTP + json_schema 구조화 출력)
  ClaudeCLIAnalyzer.swift  # claude CLI 헤드리스 호출 백엔드 (키 불필요, 기본값)
  ImageProcessor.swift   # 장변 1568px 다운스케일 + JPEG 재인코딩 (토큰 절약)
  ScreenCapture.swift      # screencapture 래퍼 (-i 영역 선택 / -l 특정 창)
  WindowPicker.swift       # 마우스 아래 창 인식 (CGWindowList, 앞→뒤 첫 매칭)
  HotKeyManager.swift      # 전역 단축키 (Carbon RegisterEventHotKey, 권한 불필요)
  HistoryStore.swift     # history.json + images/ 로컬 저장
  AppState.swift         # 전역 상태 (캡처→분석→히스토리 파이프라인)
  Views/                 # SwiftUI (메인/결과/히스토리/설정)
```
