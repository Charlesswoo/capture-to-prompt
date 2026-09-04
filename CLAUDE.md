# CaptureToPrompt — LLM 진입점

이미지 → AI 이미지 생성 프롬프트(한/영/일 + JSON) 변환 macOS 앱.
PromptCard 크롬 확장의 데스크톱 대체품. SwiftUI + SwiftPM, macOS 14+.

## 문서 지도

| 문서 | 언제 읽나 |
|---|---|
| `README.md` | 빌드/실행/트러블슈팅, 소스 구조 |
| `TODO.md` | 작업 상태·다음 단계 |

## 프로젝트 규칙

- 분석 백엔드는 2개: `ClaudeCLIAnalyzer`(claude CLI 헤드리스, 키 불필요, **기본값**) /
  `PromptAnalyzer`(Anthropic API 키). 설정 `backend`(cli|api)로 전환.
- 실 E2E 검증: `RUN_CLI_E2E=1 swift test --filter CLIIntegrationTests` (구독 사용량 소모 주의).

- Swift는 Anthropic 공식 SDK가 없다 → `PromptAnalyzer.swift`에서 raw HTTP
  (`POST /v1/messages`, `x-api-key` + `anthropic-version: 2023-06-01`)를 유지한다.
- 구조화 출력은 `output_config.format`(json_schema) 사용 — assistant prefill 금지
  (Opus 4.6+에서 400).
- 모델 기본값은 `claude-opus-4-8`. 사용자가 지정하지 않는 한 다운그레이드 금지.
- 이미지는 API 전송 전 반드시 `ImageProcessor.normalize`로 장변 1568px 제한(토큰 비용).
- 검증 명령: `swift build && swift test`, 앱 번들은 `./scripts/make_app.sh`.
