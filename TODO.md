# TODO

## 프롬프트 수정 + 캡처 자동 분석 옵션 (2026-07-28)

- [x] **프롬프트 수정** — 결과 화면 프롬프트 카드에 연필 버튼(한/영/일 탭, JSON 탭은
  파생 뷰라 제외) → TextEditor 편집 → 저장 시 현재 분석·이미지 생성·**히스토리까지 반영**
  (`HistoryStore.update`, `AppState.applyEditedPrompt`, `currentHistoryID` 추적).
  탭 전환·새 분석 도착 시 편집 중이던 내용은 폐기
- [x] **캡처 후 자동 분석 on/off** — 설정 토글 `autoAnalyzeOnCapture`(기본 **off**,
  2026-07-28 사용자 지시로 변경).
  끄면 캡처 3종(⌘1/2/3·전역 단축키)은 이미지만 띄우고 "분석 시작" 버튼(⌘↩) 대기.
  파일 열기·클립보드·드롭은 사용자가 이미 본 이미지라 항상 즉시 분석
- [x] 테스트 61개(게이트 E2E 5개 스킵) 전부 통과, `/Applications` 설치 + zip 재생성
- [x] **메타 기본 접힘** (2026-07-28) — 결과 화면을 프롬프트 중심으로: breakdown은
  "메타 ›" 클릭 시에만 펼침, 펼침 상태는 `showBreakdown`(AppStorage)로 기억
- [x] **사이드바 폭 축소** (2026-07-28) — min 150 / ideal 180 / max 220 (기존 200/230/280)
- [x] **이미지 생성 UX 재배치** (2026-07-28) — 스크롤 맨 아래 카드 → 결과 컬럼 **하단
  고정 액션 바**(항상 보임, 생성 후 복사/저장 버튼 동반). 생성된 이미지는 오른쪽 좁은
  카드 대신 **왼쪽 이미지 패널에서 원본/생성 세그먼트 전환**으로 크게 표시, 생성 완료
  시 자동으로 생성본 탭 전환. 실캡처로 하단 바 확인(생성본 전환은 실생성 시 확인)
- [x] **결과 패널 최대 폭 640** (2026-07-28) — 초광폭 창에서 프롬프트 한 줄이 무한정
  길어지던 문제. 남는 공간은 이미지 패널이 흡수. 실캡처 확인(2040px 창)
- [x] **분석 중 히스토리 선택 시 프롬프트 안 보임 수정** (2026-07-29 사용자 보고) —
  ResultPane이 "분석 중이면 무조건 스피너"였음 → 보여줄 analysis가 있으면 그걸 우선,
  대신 상단에 "새 분석 진행 중…" 배너로 백그라운드 분석 표시. 분석 완료 시 화면이
  새 결과로 전환되는 동작은 유지
- [x] **패널 비율 1:5:2 + 최소 창 크기 강제** (2026-07-29) — 결과 패널을 HSplitView에서
  `.inspector`로 교체 (HSplitView는 idealWidth를 무시하고 반반 분할 — 실측 확인, 위키
  승격 후보). 기본 폭 ~1300 기준 164:820:330, `windowResizability(.contentMinSize)`로
  800×480 미만 축소 금지. 잔여: 사이드바 저장 폭(228)이 ideal(164)보다 우선 적용됨 —
  NSSplitView 자동저장 삭제로도 안 지워져 드래그로 줄이면 유지되는 수준으로 타협
- [x] **이미지 생성 스피너** (2026-07-29) — 생성 중(약 1분) 왼쪽 이미지 패널에
  큰 스피너 오버레이(경과 초 표시, 분석 중 화면과 동일 스타일). 하단 버튼의 작은
  스피너만으로는 진행감이 부족했던 문제
- [x] **"새 캡처" 진입점** (2026-07-29) — 히스토리 열람 중 새로 시작할 방법이 안 보이는
  문제(사용자 지적). 툴바 맨 앞 "+ 새 캡처" 버튼 + 파일 메뉴 ⌘N → 결과·선택을 닫고
  시작 화면(퀵 액션)으로 복귀. 히스토리 항목은 유지
- [x] **프롬프트 편집 = 전체 패널 편집기** (2026-07-28) — 인라인 카드 편집(작은 상자,
  글 잘림)을 두 차례 지적받고 구조 변경: 연필 → 결과 패널 전체가 편집기로 전환
  (상단 저장 ⌘S / 취소 Esc, TextEditor가 패널 높이 전부 사용). 사용자 화면 확인 대기
- [x] **생성 이미지 히스토리 보관** (2026-09-03 사용자 보고) — 생성한 이미지가 사이드바
  전환·화면 갱신만으로 사라져 다시 생성해야 했던 문제. `AppState.generatedImage`가
  인메모리 단일 값이고 `show/analyze/handleCaptured/startNewCapture`에서 전부 nil로
  지워졌던 게 원인. → `HistoryItem.generatedImageFileNames`(구버전 JSON은 빈 배열로
  디코딩) + `<히스토리>/generated/` 파일 저장으로 **항목별 여러 장 누적 보관**,
  항목을 다시 열면 복원되고 앱 재시작에도 남는다. 왼쪽 패널 세그먼트는
  원본 / 생성 1 / 생성 2 … 로 확장하고, 선택 상태를 뷰 `@State` → `AppState`로 올려
  화면이 다시 그려져도 유지. 하단 바에 삭제 버튼 추가(디스크·목록 동시 정리),
  히스토리 항목 삭제 시 생성본도 함께 삭제, 사이드바에 보관 장수 배지.
  부수 수정 2건: ① 생성(약 1분) 중 다른 항목으로 옮겨가도 결과가 **원래 항목에**
  저장된다(대상 id 고정) ② `show(_:)`가 넘겨받은 값 타입 스냅샷 대신 저장소의 최신
  항목을 읽는다. 테스트 71개 통과(E2E 5개 스킵). **실 생성 왕복은 사용자 확인 대기**
- [x] **탭별 이미지 생성 확장** (2026-09-03) — 6가지를 한 번에:
  ① **항목별 동시 생성** — 전역 `isGeneratingImage` 플래그를 `generatingHistoryIDs: Set<UUID>`로
     바꿔 히스토리 항목마다 따로 생성을 걸 수 있다. 시작 시각도 항목별이라 생성 중인 항목으로
     돌아오면 경과 시간이 이어지고, 사이드바에 항목별 진행 스피너 표시
  ② **보는 언어 탭 프롬프트로 생성** — 항상 영문이던 것을 결과 패널의 현재 탭(한국어/English/
     日本語)으로. JSON 탭은 파생 뷰라 영문 사용. 메뉴에 사용할 언어를 표시
  ③ **보고 있는 이미지 기반 변형(img2img)** — codex는 `exec -i/--image`(로컬 `--help`로 확인),
     API는 `POST /v1/images/edits` multipart `image[]`(공식 문서 확인). 참조본을 결과로
     오인하지 않도록 codex 작업 폴더의 하위 `reference/`에 둔다
  ④ **탭 자리 교체 생성** — 목록 끝 추가 대신 그 자리를 교체. 인덱스가 아니라 **파일명**으로
     찾으므로 다른 항목이 동시에 생성돼도 어긋나지 않는다. 대상이 사라졌으면 새 장으로 추가
  ⑤ **원본·생성본 나란히 보기** — 세그먼트 옆 "원본과 비교" 토글 (생성본 탭일 때만)
  ⑥ **생성본으로 프롬프트 추출** — 생성 이미지를 새 입력으로 분석해 별도 히스토리 항목 생성
  하단 액션 바는 주 버튼(새로 생성) + 메뉴(변형·자리 교체·프롬프트 추출) 구조로 정리.
  테스트 83개 통과(E2E 5개 스킵). 격리 홈(`HOME=<scratch>/fakehome`)에 샘플 히스토리를 심어
  실행 — 크래시 없이 생성본 2장 항목을 로드하는 것까지 확인. **화면 잠금으로 GUI 육안 확인은
  대기** (세그먼트·비교 토글·생성 메뉴·사이드바 진행 표시)
- [x] **생성 실패 처리 개선** (2026-09-03 사용자 질문 "정책 위반이면 어떻게 되나") — 3건:
  ① **오류를 항목별로** — `errorMessage` 전역 단일 값이라 항목 A의 생성 실패가 B 화면에 뜨고
     동시 실패 시 서로 덮어썼다(동시 생성 도입으로 드러난 구멍). `generationErrors: [UUID: String]`
     + `visibleErrorMessage`(전역 오류 우선, 없으면 보고 있는 항목의 생성 오류) +
     `dismissVisibleError`(보이는 것 하나만 닫기). 사이드바에 항목별 실패 경고 아이콘
  ② **정책 거부 한국어 안내** — `AnalyzerError.contentPolicy` 추가. OpenAI는 code
     `moderation_blocked`(gpt-image) / `content_policy_violation`(DALL·E) / 문구 "safety system"
     으로 판별(공식·커뮤니티 문서 확인), codex는 코드가 없어 거부 문구로 판별.
     **같은 프롬프트로 재시도해도 결과가 같다**는 사실을 안내에 넣어 프롬프트 수정을 유도하고
     원문을 병기. 정책과 무관한 오류는 기존 `apiError` 유지
  ③ **codex 실패 문구 개선** — 정책 거부를 "codex가 이미지 파일을 저장하지 않았습니다"로
     보여주던 것을 실제 원인에 맞게 교체하고, 사유 200자 잘림 제거
  테스트 96개 통과(E2E 5개 스킵). **실 정책 거부 응답은 미실측 — 코드 경로 기반**
- [x] **정책 거부 원인 진단 + 프롬프트 개선 제안** (2026-09-03) — 거부됐을 때 "왜"와
  "어떻게 고칠지"를 알려준다. 새 `PromptRevisionAdvisor`(요청문·JSON 스키마·파싱) +
  `PromptRevision` 모델(summary / issues[phrase·reason·suggestion] / revised_prompt).
  진단은 **분석 백엔드를 그대로 재사용** — 4개 백엔드 전부에 이미지 없는 텍스트 요청
  경로를 추가(`complete`): claude CLI `-p … --output-format json`, codex `exec
  --output-schema`(이미지 플래그 없음), Anthropic API `output_config.format`,
  llm-router `response_format`. 거부 시점의 프롬프트·사유·**언어**를 `policyRejections`에
  남겨(항목별) 나중에 눌러도 진단 가능. 오류 배너의 "개선점 보기" → 시트(문제 구절 하이라이트
  + 이유 + 대체 표현 + 수정본) → "프롬프트 교체" / "교체하고 다시 생성".
  적용은 거부됐던 **그 언어 탭**에 반영되고 히스토리까지 갱신
  **실측 완료**: `RUN_REVISION_E2E=1 swift test --filter PromptRevisionIntegrationTests`
  (claude CLI 왕복 29.5초). "Emma Watson / holding a gun / in the style of Greg Rutkowski"
  3구절을 정확히 짚고 구도·조명·분위기를 유지한 수정본 생성. 테스트 120개 통과(게이트 6개 스킵)
- [x] **그림체(화풍) 추출 강화** (2026-09-03 사용자 요청) — 기존 `style`·`medium`을
  더 구체적으로 + 생성 모델이 알아듣기 쉬운 형태로. **작가·작품명 추출은 하지 않는다**
  (정책 거부 트리거). 새 `PromptGuidelines.styleRules`를 4개 백엔드가 공유:
  ① style은 다섯 축 라벨 고정 — `Line work:` `Shading:` `Color:` `Rendering:` `Finish:`,
     **영어 고정**(기존 히스토리는 항목마다 한국어/영어가 섞여 있었다), 700자 이내
  ② 생성 프롬프트 본문이 **화풍 구절(15~25단어)로 시작**하도록 — 이미지 생성 모델이
     앞쪽 구절에 크게 반응하므로. 3개 언어 모두 적용
  ③ "피사체 묘사를 줄이지 말 것" 균형 지시 (앞머리 지시만 주면 본문이 짧아졌다)
  구조화 출력 스키마(API·codex·router)의 style/medium description도 같은 규칙으로 갱신.
  기존 히스토리와 **완전 호환**(필드 추가 없음)
  **PoC 근거**(scratchpad/poc, claude CLI 실측 4안 비교): 현행은 style 58자
  "동양 무협 판타지 키 비주얼" 수준의 장르 이름에 그쳤고, 축 지시만으로는 본문 앞머리에
  화풍이 안 실렸다. 채택안은 style 695자·본문 3개 언어 모두 화풍으로 시작
  **E2E 실측**: `RUN_CLI_E2E=1 E2E_IMAGE=<이미지> swift test --filter CLIIntegrationTests`
  (67초) — 다섯 축 라벨 검증 assertion 추가. 테스트 123개 통과(게이트 6개 스킵)
- [x] **분석 거절 메시지 · claude CLI 3초 지연 수정** (2026-09-03, 화풍 작업 중 발견) —
  ① 모델이 분석을 거절하면(JSON 대신 산문 반환) "결과 JSON 해석 실패: {…"라는 엉뚱한
     메시지가 났다. `AnalyzerError.fromNonJSONResponse`로 판별 — `{`로 시작하지 않으면
     `refusal`(모델이 말한 이유를 그대로 전달), JSON인데 깨졌으면 기존 해석 실패 유지.
     claude CLI·codex CLI·llm-router 세 경로에 적용
  ② `claude -p` 호출 시 stdin을 안 닫아 매번 "no stdin data received in 3s"로 3초를
     버렸다(codex는 이미 `FileHandle.nullDevice`로 닫고 있었다). analyze·complete 양쪽에 적용.
     **실측**: 같은 프롬프트로 9초 → 6초, 경고 사라짐
  테스트 127개 통과(게이트 6개 스킵), /Applications 설치·재실행 완료
- [x] **수정한 프롬프트가 사라지는 버그 수정 + 원본 재분석** (2026-09-03 사용자 보고
  "분명히 저장했는데 수정 내용이 사라졌다") — **근본 원인**: `show(_:)`가 사이드바에서
  넘겨받은 **값 타입 스냅샷의 analysis**를 그대로 화면에 올렸다. 셀이 리렌더되지 않으면
  수정 전 HistoryItem이 넘어오고, 그 낡은 analysis를 기준으로 `applyEditedPrompt`가
  히스토리를 **통째로 덮어써** 앞서 저장한 다른 언어의 수정이 원본으로 되돌아갔다.
  (테스트 2개로 재현 확인 후 수정 — `testShowUsesLatestAnalysisNotStaleSnapshot`,
  `testEditAfterReopenDoesNotRevertEarlierEdit`)
  → ① `show(_:)`는 저장소의 최신 항목을 진실로 삼는다 ② `applyEditedPrompt`는 저장소의
  최신 분석을 기준으로 **해당 언어만** 갈아끼운다(화면이 낡아도 다른 언어를 뭉개지 않음)
- [x] **원본 재분석** (2026-09-03) — 히스토리 항목의 원본 캡처로 프롬프트를 다시 뽑는
  기능이 아예 없었다. `reanalyze(_:)` / `reanalyzeCurrent()`(⌘R) + 사이드바 컨텍스트 메뉴
  "원본으로 다시 분석". 결과는 **새 항목** — 기존 분석과 사용자가 수정한 프롬프트는 남는다
- [x] **개선안 시트 오조작 방지** (2026-09-03) — 시트가 자동으로 뜨는데 "교체하고 다시
  생성"이 Return 기본 버튼이라, 무심코 누른 Return이 프롬프트를 갈아치웠다. Return 바인딩
  제거(Esc=닫기만 유지). 테스트 132개 통과(게이트 6개 스킵)
- [x] **인물 포즈 추출** (2026-09-04 사용자 요청 "인물이 있는 경우 포즈도 자세히") —
  `breakdown.pose` 전용 필드 신설. 프레이밍 / 카메라 대비 몸 방향 / 머리·시선 / 몸통·무게중심
  / 좌우 팔·손 / 다리·발 / 표정 / 동작 여부를 영어로 서술하고, **인물이 없으면 빈 문자열**.
  결과 화면 메타에는 pose가 있을 때만 "포즈" 행을 보여준다(복사용 metaText도 동일).
  구버전 history.json 호환 — `decodeIfPresent`로 없으면 "" (`Breakdown`에 커스텀 디코딩 추가)
  **PoC 근거**(scratchpad/pose, 2안 비교): subject에 포즈를 몰아넣는 안은 subject가 1280자로
  부풀어 인물 외형 묘사가 밀렸고, subject를 목록 제목으로 쓰는 **사이드바 가독성이 깨졌다**.
  전용 필드 안은 subject 200자 + pose 1072자로 역할이 분리됨 → 후자 채택
  **E2E 실측 2회**: 인물 이미지(89초) — 프레이밍·3/4 각도·좌우 팔·표정·"발사 직전 정지"까지
  구체적으로 추출 / 풍경 이미지(70초) — pose 빈 문자열 확인.
  테스트 137개 통과(게이트 6개 스킵)
- [x] **생성 이미지 일괄 삭제** (2026-09-04 사용자 요청) — 기존에는 보고 있는 1장만 지울 수
  있었다. `HistoryStore.removeAllGeneratedImages(id:)` + `generatedImagesByteSize(id:)`.
  하단 바 휴지통을 메뉴로 확장("이 생성본 삭제" / "생성본 N장 모두 삭제"),
  사이드바 컨텍스트 메뉴에도 추가(보고 있지 않은 항목도 정리 가능).
  전체 삭제는 되돌릴 수 없으므로 **장수·용량을 보여주는 확인 다이얼로그**를 거친다.
  분석 결과와 원본 캡처 이미지는 남는다
- [x] **분석 병렬 실행** (2026-09-04 사용자 지적 "재추출이 전역으로 잠긴다") —
  이미지 생성만 항목별로 풀어놓고 분석은 `isAnalyzing` 전역 Bool 그대로였다.
  `runningAnalyses: [UUID: AnalysisJob]`로 교체 — job마다 `sourceHistoryID`(재분석 출처)와
  `takesOverScreen`(화면 점유 여부)을 갖는다.
  ① **재분석은 백그라운드** — 보고 있던 프롬프트를 스피너로 덮지 않는다
  ② 완료 시 `shouldPresentResult` 판정 — 그 사이 다른 항목으로 옮겨갔으면 화면을 가로채지
     않고 히스토리에만 추가(사이드바에서 열면 된다)
  ③ 툴바 재분석 버튼은 **같은 항목이 도는 중일 때만** 잠긴다 (다른 이미지는 동시에 가능)
  ④ 사이드바·결과 패널에 항목별 재분석 진행 표시
  **실측**: 2건 동시 분석 96.8초 (한 건 70~90초 → 순차면 150초+). 테스트 148개 통과
- [x] **CLI 실패 메시지 정리** (2026-09-04) — "API 오류 (15): codex 이미지 생성 실패:
  hook: PostToolUse Completed" 같은 무의미한 오류가 나왔다. 원인 둘: ① 신호로 종료된 경우
  (SIGTERM=15)를 "실패"로 표시 ② stderr 뒤 300자를 그대로 실어, codex가 뱉는 프롬프트 조각·
  hook 로그가 원인 자리에 노출. 새 `CLIProcessFailure` — 신호 종료는 "중단되었습니다"로,
  stderr는 error/failed/cannot 등이 든 줄만 추려서 표시. codex 생성·codex 분석·claude 분석
  세 경로에 적용
- [x] **포즈 검증·수정** (2026-09-04 사용자 지적 "모델이 포즈를 다르게 적어도 알 방법이 없다") —
  구멍 둘이었다: ① pose가 기본 접힘인 메타(`showBreakdown`) 안에만 있어 펼치지 않으면 안 보임
  ② breakdown은 읽기 전용이라 틀린 걸 발견해도 고칠 수 없음.
  → pose를 **항상 보이는 카드**로 꺼내 왼쪽 원본 이미지와 눈으로 대조하게 하고(메타의 중복 행
  제거), 연필로 **전체 패널 편집기**에서 수정 가능하게 했다(`applyEditedPose` — 프롬프트 편집과
  같은 방어로 저장소 최신 기준 pose만 교체). 포즈 편집 중에는 언어 탭을 바꿔도 편집이 유지된다.
  테스트 156개 통과(게이트 7개 스킵)
- [x] **자동 업데이트** (2026-09-04) — GitHub 공개 저장소 릴리스 기반, **확인 자동 / 설치 수동**.
  저장소: https://github.com/Charlesswoo/capture-to-prompt (커밋 신원은 noreply 주소로 설정 —
  회사 이메일이 공개 히스토리에 남지 않게)
  - `AppVersion` — "v1.2", "1.2.3" 등을 숫자로 비교(사전순 버그 방지: 0.1.10 > 0.1.9)
  - `UpdateChecker` — `releases/latest` 조회(공개라 토큰 불필요), zip 자산이 있어야 유효,
    릴리스가 없으면 404를 "새 버전 없음"으로 처리
  - `UpdateInstaller` — zip 다운로드 → `ditto -x -k` 해제 → 교체 스크립트 실행 후 앱 종료.
    실행 중 자기 자신은 못 덮으므로 스크립트가 **종료를 기다렸다가**(최대 30초) 교체하고,
    새 번들이 실제로 있을 때만 기존 것을 지운다(중간 실패로 앱이 사라지지 않게).
    `xattr -dr com.apple.quarantine`으로 첫 실행 차단 방지
  - UI: 화면 아래 파란 배너(버전·노트·용량 + "설치하고 다시 열기"), 앱 메뉴 "업데이트 확인…",
    설정에 "시작할 때 새 버전 확인" 토글·현재 버전·지금 확인
  - `scripts/release.sh <버전> [노트]` — Info.plist 갱신 → 테스트 → 빌드·서명 → zip(ditto,
    서명 보존) → 태그·푸시 → `gh release create`. 커밋 안 된 변경이 있으면 중단
  테스트 160개 통과(게이트 7개 스킵). **첫 릴리스 발행 후 실제 업데이트 왕복 검증 필요**
- [x] **llm-router 백엔드 제거** (2026-09-04 사용자 요청) — `LLMRouterAnalyzer.swift`와
  테스트 2개 파일 삭제, `Backend.router`·`routerBaseURL/APIKey/Model`·`resolvedRouterKey`·
  `AnalyzerError.missingRouterKey`·설정 화면 섹션·문서(guide.html) 정리.
  `OpenAIErrorEnvelope`/`ChatCompletionResponse`는 이 파일에만 있고 다른 곳에서 안 써서
  함께 삭제(ImageGenerator는 자체 `ImageErrorEnvelope` 사용). 남은 백엔드 3개:
  Claude CLI(기본) / Codex CLI / Anthropic API. 테스트 148개 통과
- [x] **업데이트 배너 실동작 확인** (2026-09-04) — v0.3.0 발행 후 앱(0.2.0) 재시작하니
  "새 버전 0.3.0이 있습니다 (현재 0.2.0)" 배너가 노트와 함께 표시됨. 조회·비교·다운로드·
  서명 보존·교체·재실행까지 전 구간 검증 완료. 좁은 창에서 버튼 텍스트가 잘려
  "설치하고 다시 열기" → "설치"로 줄이고 `fixedSize()` 적용
- [x] **삭제한 항목이 화면에 남는 버그** (2026-09-04 사용자 리포트) — 사이드바에서 지워도
  가운데 이미지 뷰어와 결과 패널에 그대로 남았다. 원인: 사이드바가 `history.delete(item)`을
  직접 불러 **저장소만 지우고 AppState 화면 상태는 손대지 않았다**.
  → `AppState.deleteHistoryItem(_:)` 신설 — 보고 있던 항목이면 화면을 비우고(`startNewCapture`),
  그 항목에 매달린 오류·정책 거부 기록·개선안·생성 진행 표시도 함께 정리. 다른 항목을 보는
  중이면 화면은 그대로. 사이드바 두 진입점(휴지통 버튼·컨텍스트 메뉴) 모두 이 경로로 변경
- [x] **항목 삭제 확인 단계** (2026-09-04 사용자 요청) — 생성 이미지 일괄 삭제만 확인을 거치고
  정작 항목 자체(원본·프롬프트·생성본 전부)는 휴지통을 누르는 즉시 사라졌다. 사이드바 두
  진입점(휴지통·컨텍스트 메뉴)을 확인 다이얼로그 경유로 바꾸고, 무엇이 사라지는지
  (항목 제목 / 생성본 장수·용량 / "되돌릴 수 없습니다")를 함께 보여준다
- [x] **업데이트 자동 확인 주기화** (2026-09-04 사용자 지적 "업데이트 체크를 해서 자동으로
  뜨게 해줘야지") — 시작할 때 1회만 확인해서, 앱을 켜둔 채로는 새 릴리스가 나와도 몰랐다.
  → `startPeriodicUpdateChecks()` — 시작 시 1회 + **1시간마다** + **창이 다시 활성화될 때**.
  `UpdateChecker.shouldCheck(lastCheck:now:interval:)`로 간격을 지키고(활성화마다 조회 금지),
  시계가 뒤로 간 경우도 멈추지 않게 처리. 이미 배너가 떠 있으면 재조회하지 않는다
- [x] **"최신 버전입니다"가 빨간 오류 배너로 뜨던 문제** — 오류가 아닌 소식이므로
  `updateNotice`로 분리해 초록 체크 안내 배너로 3초간 표시
- [x] **항목을 열면 생성본과 바로 비교** (2026-09-04 사용자 제안) — 히스토리 항목을 다시
  여는 이유는 대개 결과를 원본과 견주기 위해서인데, 늘 원본 보기로 시작해 매번 세그먼트와
  비교 토글을 눌러야 했다. `loadGeneratedImages`가 생성본이 있으면 **가장 최근 것을 골라
  비교 모드로** 연다. 생성본이 없으면 종전대로 원본만. (기존 테스트 1건의 기대값도 갱신)
- [x] **생성 이미지 색감이 전혀 다르게 나오던 문제** (2026-09-04 사용자 리포트, 사례 2건) —
  **원인: 프롬프트 언어**. "보는 언어 탭 프롬프트로 생성"(2026-09-03 추가) 때문에 한국어 탭에서
  생성하면 한국어 프롬프트가 그대로 gpt-image에 갔고, 모델이 색감·구도 지시를 놓쳤다.
  **실측 근거**: 같은 항목의 prompt_en으로 codex CLI를 직접 돌리니 원본 톤을 그대로 재현
  (창백한 화이트·실버 그레이, 넥타이 빨강만 채도 포인트). codex 로그 확인 결과 프롬프트는
  손실 없이 전달됨 — 전달 문제가 아니라 언어 문제.
  → 생성은 **영어 프롬프트 고정**(`defaultGenerationLanguage`). 보고 있는 탭이 영어가 아니면
  메뉴에 "<탭> 프롬프트로 생성"을 대안으로 남기고, 메뉴 하단에 이유를 표기.
  (부수 관찰: 한국어 생성 시 모델이 색감 서술을 무드보드 키워드로 오해해 이미지에 간판 글자를
  그려 넣기도 했다)
- [x] **한국어로 고친 프롬프트가 생성에 반영되지 않던 문제** (2026-09-04 사용자 질문
  "한글로 수정하고 싶을 때는 어떻게 해?") — 생성을 영어 고정으로 바꾸면서, 한국어 탭에서
  연필로 고쳐도 `prompt_en`은 그대로라 **수정이 무시됐다**(포즈 편집에서 없앤 함정이 재발).
  → 새 `PromptSync` — 저장하면 나머지 두 언어를 같은 내용으로 다시 쓴다.
  고친 언어는 사용자가 쓴 문장 그대로 두고, 대상 언어가 응답에 없으면 실패로 처리.
  저장소 최신과 편집 내용이 어긋나면(그 사이 또 고쳤으면) 반영하지 않는다.
  동기화 중에는 생성 버튼을 잠가 옛 영어 프롬프트로 생성되는 것을 막고, 프롬프트 카드에
  "다른 언어 맞추는 중…" 표시.
  **실측**: `RUN_REVISION_E2E=1 swift test --filter testRealPromptSyncThroughClaudeCLI` (9.2초)
  — 한국어에만 있던 "낡은 목조 등대·빨간 코트·회청색 팔레트"가 영어·일본어에 그대로 반영됨
- [x] **세 언어 프롬프트를 번역 방식으로** (2026-09-07) — `PromptGuidelines.languageRules` 추가:
  영어를 정본으로 먼저 쓰고 한국어·일본어는 **같은 내용**을 각 언어답게 옮기되 축약 금지.
  세 백엔드 프롬프트에서 예전 "각 언어로 독립 작성(not a translation note)" 지시 제거.
  **다만 측정 가능한 개선은 확인하지 못했다** — E2E 실측 길이 비율이 ko/en 0.48→0.51로
  거의 그대로였다. 한글은 글자당 정보량이 커서 길이 비율 자체가 품질 지표로 약하다.
  앞머리 대조로는 세 언어가 정확히 대응함을 확인. E2E 하한은 명백한 축약만 잡도록 완화
- [x] **하단 액션 바 텍스트 잘림 방지** (2026-09-07 사용자 질문) — 복사·저장 버튼에만
  `.fixedSize()`가 없어 좁은 패널(최소 280pt)에서 잘릴 수 있었다. `ViewThatFits`로
  좁아지면 아이콘만 표시. ("저장…"의 말줄임표는 대화상자를 뜻하는 macOS 관례라 유지)
- [x] 실캡처 검증: 자동 분석 off "분석 대기" 화면, 메타 접힘+연필 버튼, 좁아진 사이드바
- [ ] 실캡처 검증 잔여(합성 클릭 중단 — 사용자 기기 사용 중): 분석 시작 버튼 실행 흐름,
  연필 편집 모드 화면, 메타 펼침, 설정 토글 화면 — 직접 사용하며 확인 권장

## UX/UI 앱스토어 수준 개선 (2026-07-27)

- [x] 메뉴 커맨드·단축키 — 파일 열기 ⌘O, 클립보드 분석 ⌘⇧V, "캡처" 메뉴(⌘1/2/3)
- [x] 툴바 그룹핑 — 캡처 3종(primary)과 클립보드/파일(secondary) 분리, 도움말에 단축키 병기
- [x] 사이드바 섹션 헤더("히스토리 · N"), 결과 빈 상태 ContentUnavailableView 표준화
- [x] 한국어 지역화 선언 — CFBundleDevelopmentRegion=ko + ko.lproj (설정 창 제목·시스템
  메뉴 한국어화, make_app.sh가 lproj 복사)
- [x] 설정 창 잘림 수정(480×620), 분석 중 메시지 백엔드 인지형("Codex가 분석 중…")
- [x] 실캡처 검증 — 라이트/다크/설정 창 스크린샷 확인, 쓰레기 claudePath("rr") 정리
- [x] **영어 지역화** — `en.lproj/Localizable.strings`(한국어 리터럴을 키로 ~80개 문자열),
  `-AppleLanguages '("en")'` 실행으로 전 화면 영어 UI 실캡처 검증 완료
- [x] 앱 아이콘 품질 검토 — 전 사이즈(16~512@2x) 포함, 품질 양호로 판정 (작업 불필요)
- **결정(2026-07-27)**: 사내 전용 배포로 확정 — App Store 제출 안 함 (샌드박스 재설계
  불필요). 팀 배포 시 우클릭-열기 안내가 번거로우면 "배포 (공증)" 섹션의 Developer ID
  공증만 선택적으로 진행

## codex 백엔드 + 이미지 생성 (2026-07-27)

- [x] **Codex CLI 백엔드** (4번째, ChatGPT 구독 로그인 사용) — `codex exec -i <이미지>
  --output-schema <스키마> -o <출력> --ephemeral --skip-git-repo-check -s read-only`,
  stdin 반드시 닫음(안 닫으면 hang — 위키 gotcha). CLI 탐색/PATH 보강은 `CLILocator`로
  공용화(claude와 공유). 실 E2E 통과(44초):
  `RUN_CODEX_E2E=1 swift test --filter CodexIntegrationTests`
- [x] **이미지 생성** — OpenAI 호환 Images API(`{base}/images/generations`) 클라이언트
  `ImageGenerator`. b64_json/url 응답 모두 처리, response_format은 모델별 수락이 갈려
  미전송. 결과 화면에 "이미지 생성" 카드(영문 프롬프트 사용, 복사/PNG 저장).
  설정: Base URL(기본 api.openai.com/v1 — 향후 llm-router images 지원 시 교체 가능)/
  API 키(비우면 OPENAI_API_KEY)/모델(기본 gpt-image-2)
- [x] **Codex 이미지 생성 엔진** (기본값, 키 불필요) — codex 0.144의 `image_generation`
  기능(stable)로 ChatGPT 구독만으로 생성. `codex exec -s workspace-write`로 작업 폴더에
  `generated.png` 저장 지시 → 파일 회수(다른 이름 저장 폴백 포함). 실 E2E 통과(52초):
  `RUN_CODEXIMG_E2E=1 swift test --filter CodexImageGenIntegrationTests`.
  설정 "이미지 생성 > 엔진"에서 OpenAI 호환 API(키)로 전환 가능
- [ ] OpenAI API 엔진 실 E2E — OpenAI API 키 필요 (사용자 확인 항목, 기본 엔진은 codex라 급하지 않음):
  `RUN_IMAGEGEN_E2E=1 OPENAI_API_KEY=<키> swift test --filter ImageGenIntegrationTests`
- 테스트 55개(게이트 E2E 5개 스킵 포함) 전부 통과

## 자동업데이트 (중단됨 — 2026-07-24)

사용자 지시로 브레인스토밍 단계에서 중단. 재개 시 아래 확정 사항에서 이어가면 됨.

- 확정: spooncast org 저장소는 **private** / 릴리스는 **로컬 빌드 + release.sh** /
  업데이트 방식은 **Sparkle 2** / 배포 채널은 **사내 S3(기존 버킷)**
- 중단 지점: 버킷 경로·서빙 URL·AWS 프로필 확인 대기 (인프라 정보 필요)
- 미결: repo 생성 자체도 보류 상태 (git init 안 됨)

## llm-router 연동

목표: `~/Ax/llm-router`(OpenAI 호환 단일 엔드포인트)를 세 번째 분석 백엔드로 추가.

- [x] llm-router의 **이미지 입력(vision) 지원 여부 확인** — 소스 검증 완료: OpenAI content-parts
  (`image_url` data URI/원격 URL) 수락, JPEG/PNG 등 허용, 이미지당 5MB·요청당 8장 제한,
  vision 미지원 모델은 라우팅에서 자동 제외됨
- [x] `LLMRouterAnalyzer.swift` 추가 — llm-router가 `response_format: json_schema`를
  지원해서(TODO의 가정과 달리) 기존 `PromptAnalyzer.outputSchema`를 그대로 전달.
  방어적으로 `ClaudeCLIAnalyzer.stripFences` 파싱 병행. 인증은 `Authorization: Bearer`
- [x] 설정: 백엔드 3종(cli/api/router) 라디오 + Base URL(기본 `http://localhost:3000`) +
  API 키 필드(비우면 `LLM_ROUTER_API_KEY` 환경변수) + 모델 필드(기본 `auto`,
  별칭은 `auto:cost`/`auto:speed`/`auto:quality`)
- [x] AppState.analyze 분기 확장 + 파싱 단위 테스트 8개 (전체 26개 통과)
- [x] E2E(배선): `API_KEY=<마스터키> pnpm dev`로 띄워 mock 모드 실 HTTP 왕복 성공 —
  `RUN_ROUTER_E2E=1 LLM_ROUTER_API_KEY=<키> swift test --filter RouterIntegrationTests`
- [ ] E2E(실 모델): llm-router에 프로바이더 키(.env.local)가 없어 mock 응답까지만 검증됨.
  키 설정 후 위 명령으로 실 분석 1회 확인 필요 (사용자 확인 항목)

참고: 기존 백엔드 구조는 `PromptAnalyzer.swift`(Anthropic raw HTTP), `ClaudeCLIAnalyzer.swift`
(claude CLI). 공통 스키마/모델은 `Models.swift`의 `PromptAnalysis`.

## v0.1 — PromptCard 대체 macOS 앱 (MVP)

- [x] 리서치: PromptCard 확장 기능 파악 (이미지→다국어 프롬프트, 캡처, 히스토리, 커스텀 API)
- [x] SwiftPM 프로젝트 스캐폴딩 (macOS 14+, SwiftUI)
- [x] PromptAnalyzer: Anthropic Messages API raw HTTP + `output_config.format`(json_schema)
- [x] ImageProcessor: 장변 1568px 다운스케일 → JPEG
- [x] ScreenCapture: `screencapture -i` 영역 캡처
- [x] HistoryStore: 로컬 히스토리 (history.json + images/)
- [x] UI: 메인 창(드롭존/이미지/결과 탭/복사), 히스토리 사이드바, 설정, 메뉴바 엑스트라
- [x] 단위 테스트 9개 (요청 구성/응답 파싱/refusal/HTTP 오류/히스토리 영속성) — 전부 통과
- [x] `.app` 번들 스크립트 + ad-hoc 서명, 실행 스모크 테스트 통과
- [x] **Claude Code CLI 백엔드 추가** (API 키 불필요, 기본값) — 실 이미지 E2E 통과 (43.8초)
- [x] 실 분석 E2E 검증 — `RUN_CLI_E2E=1 swift test --filter CLIIntegrationTests`
- [ ] API 키 백엔드 실 호출 검증 — 사용자가 키를 마련하면 (현재 키 없음, CLI 백엔드로 대체됨)
- [x] **전역 단축키** (Carbon RegisterEventHotKey, 기본 ⌥⇧C, 설정에서 프리셋 변경)
- [x] **마우스 아래 창 자동 인식 캡처** (CGWindowList → `screencapture -l <windowID>`)
  — 창 검출 로직 실증 완료. 실제 창 캡처는 앱에 화면 기록 권한 부여 후 사용자 확인 필요
- [ ] (선택) 앱 아이콘 추가
- [ ] (선택) API 키 Keychain 저장으로 전환 (현재 UserDefaults)
- [ ] (선택) 단축키 자유 지정 (현재는 프리셋 3종)

## UI 개선 — Liquid Glass (macOS 26)

- [x] 타깃 macOS 26 상향 (swift-tools 6.2, 언어 모드는 v5 유지)
- [x] 빈 상태 온보딩: 안내 문구 + glass 퀵 액션 버튼(창/영역/클립보드) + 단축키 힌트
- [x] 분석 중 UX: glass 카드 + 경과 시간 표시 ("보통 30~60초")
- [x] 결과 화면: glassProminent 복사 버튼(⌘⇧C), 본문 카드, 태그 = 클릭 복사되는 glass 칩
- [x] 복사 토스트(glass capsule), 드롭 하이라이트, 오류 배너(glass, 닫기 버튼)
- [x] 히스토리: 상대 시간 표시, hover 삭제 버튼, 컨텍스트 메뉴 복사, 빈 상태 뷰
- [x] 창 배경 반투명화 — `.containerBackground(.ultraThinMaterial, for: .window)`,
  본문 카드도 material로 교체 (유리 터미널 느낌)
- [ ] 사용자 실사용 확인 (glass 렌더링/토스트/칩/투명 배경)

## 버그 수정

- [ ] **전역 단축키를 누르면 설정 창이 뜨는 문제** — 캡처 대신(또는 함께) 설정 창이
  자꾸 열림 (2026-07-24 사용자 보고). 재현 조건·원인 미조사
- [ ] **메인 창이 사라지고 재생성 안 되는 문제** (2026-07-29 자동화 검증 중 반복 관찰) —
  ⌘2(창 선택) 직후 등에서 창 개수가 0이 되고, 이후 `reopen`/Dock 클릭/메뉴바 "창 열기"
  (`bringToFront`)로도 창이 다시 안 만들어짐 (앱 재시작해야 복구). `bringToFront`가
  기존 창 orderFront만 하고 WindowGroup 재생성 경로가 없는 것이 최소 절반의 원인.
  위 설정 창 버그와 함께 창 관리 로직 조사 필요
- [x] **CLI 백엔드 127 오류** (`env: node: No such file or directory`) — npm 설치형
  claude는 `#!/usr/bin/env node` 셔뱅 스크립트라 GUI 최소 PATH에서 node를 못 찾음.
  네이티브 설치(이 Mac)는 무관해서 "내 PC에선 되는" 증상. `ClaudeCLIAnalyzer`가
  프로세스 PATH에 알려진 node 위치(homebrew/nvm 최신/volta/bun/asdf/mise)를 보강하도록
  수정 + 단위 테스트 3개 (2026-07-24). 다른 PC에는 새로 빌드한 dist 번들 전달 필요
- [x] **nvm 설치형 claude 탐색 불가** — anna PC 실사례: claude가
  `~/.nvm/versions/node/v24.14.0/bin/claude` 에만 존재. `locateBinary` 후보를
  고정 4곳 + nvm 버전별 bin(숫자 기준 최신 우선) + volta/bun/pnpm global/
  npm-global prefix/asdf/mise shims까지 확장 + 단위 테스트 3개
  (2026-07-24). dist/CaptureToPrompt.zip 재생성됨 — anna PC에 재전달 필요
- [x] **claude 경로 수동 지정** — 자동 탐색이 못 커버하는 설치 방식 대비 최종 탈출구.
  설정 CLI 섹션에 경로 필드(비우면 자동 탐색, 잘못된 경로는 폴백 없이 실패) +
  감지 상태·해석된 경로 실시간 표시 + 미탐색/127 에러 메시지에 설정 안내 문구.
  Claude Code 미설치 PC 대비: 미탐지 안내에 "다른 백엔드(API 키/LLM Router) 선택" 경로 포함
  (2026-07-24, 테스트 3개 추가 — 전체 34개)

## 서명/권한

- [x] 화면 기록 권한이 계속 재요청되는 문제 해결 — 원인: ad-hoc 서명은 빌드마다
  정체성이 바뀌어 TCC가 새 앱으로 인식. 자체 서명 인증서("CaptureToPrompt Dev")를
  키체인에 등록하고 make_app.sh가 그걸로 서명 (없으면 ad-hoc 폴백 + 경고).
  p12는 OpenSSL 3에서 `-legacy` 필요. 기존 꼬인 권한은 `tccutil reset ScreenCapture`로 초기화.
- [ ] 첫 캡처 시 권한 1회 허용 — 사용자 확인 필요 (이후 재빌드에도 유지됨)

## 배포 (공증)

- [x] `scripts/notarize.sh` 작성 — Developer ID 서명 + notarytool 공증 + 스테이플 + 배포 zip
- [ ] 이 Mac에 Developer ID Application 인증서 설치 (Xcode 계정 로그인 또는 .p12)
- [ ] `xcrun notarytool store-credentials c2p-notary ...` 자격증명 1회 저장
- [ ] 공증 실행 및 다른 Mac에서 실행 확인

## 창 선택 캡처

- [x] `screencapture -i -W`(창 선택 모드) 기반 "창 선택 캡처" 추가 — 툴바·메뉴바·빈 상태
  퀵 액션 3곳에 진입점, 캡처 전 앱 자동 숨김/복귀
- [x] **Exposé풍 창 그리드 선택기로 교체** — ScreenCaptureKit(SCShareableContent +
  SCScreenshotManager)으로 열린 창 썸네일 그리드 표시, 클릭 → `screencapture -l` 캡처.
  가려진 창도 내용 그대로 캡처됨

<!-- 2026-07-24: Liquid Glass UI 개선 완료(테스트 17개 통과), 다음: 사용자 확인 -->

