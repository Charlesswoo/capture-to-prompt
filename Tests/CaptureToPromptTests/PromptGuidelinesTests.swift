import XCTest
@testable import CaptureToPrompt

/// 그림체(화풍) 추출 규칙이 4개 백엔드 지시문에 빠짐없이 들어가는지 확인한다.
/// (규칙 문구는 PoC로 고른 것 — 축 라벨과 "프롬프트 앞머리 스타일 구절"이 핵심)
final class PromptGuidelinesTests: XCTestCase {

    func testStyleRulesDeclareFiveAxesAndOpeningClause() {
        let rules = PromptGuidelines.styleRules

        // style 필드의 다섯 축 라벨
        for label in ["Line work:", "Shading:", "Color:", "Rendering:", "Finish:"] {
            XCTAssertTrue(rules.contains(label), "축 라벨 누락: \(label)")
        }
        // 프롬프트 본문이 화풍 구절로 시작해야 한다는 지시
        XCTAssertTrue(rules.contains("OPEN with"))
        // 피사체 묘사를 줄이지 말라는 균형 지시 (PoC에서 c안이 짧아졌던 문제)
        XCTAssertTrue(rules.lowercased().contains("do not shorten"))
        // style/medium은 영어 고정 (기존 히스토리는 한국어·영어가 섞여 있었다)
        XCTAssertTrue(rules.contains("in English"))
        // 정책 거부를 부르는 고유명사 금지
        XCTAssertTrue(rules.lowercased().contains("never name artists"))
    }

    /// 네 백엔드 모두 같은 규칙을 쓴다 — 백엔드를 바꿔도 결과 형식이 같아야 한다.
    func testAllBackendPromptsIncludeStyleRules() {
        let rules = PromptGuidelines.styleRules
        XCTAssertTrue(ClaudeCLIAnalyzer.prompt(imageFileName: "input.png").contains(rules))
        XCTAssertTrue(CodexCLIAnalyzer.prompt.contains(rules))
        XCTAssertTrue(PromptAnalyzer.systemPrompt.contains(rules))
    }

    /// 구조화 출력 스키마의 style/medium 설명도 같은 규칙을 안내해야 한다
    /// (API·codex는 스키마를 함께 보낸다).
    func testOutputSchemaDescribesStyleAxes() throws {
        let properties = try XCTUnwrap(PromptAnalyzer.outputSchema["properties"] as? [String: Any])
        let breakdown = try XCTUnwrap(properties["breakdown"] as? [String: Any])
        let fields = try XCTUnwrap(breakdown["properties"] as? [String: Any])

        let style = try XCTUnwrap(fields["style"] as? [String: Any])
        let styleDescription = try XCTUnwrap(style["description"] as? String)
        XCTAssertTrue(styleDescription.contains("Line work:"))
        XCTAssertTrue(styleDescription.contains("Finish:"))

        let medium = try XCTUnwrap(fields["medium"] as? [String: Any])
        XCTAssertNotNil(medium["description"] as? String)
    }

    // MARK: - 포즈 추출 규칙

    func testPoseRulesCoverBodyAxesAndEmptyCase() {
        let rules = PromptGuidelines.poseRules
        for axis in ["framing", "orientation", "gaze", "torso", "arm", "leg", "expression"] {
            XCTAssertTrue(rules.lowercased().contains(axis), "포즈 축 누락: \(axis)")
        }
        // 인물이 없으면 빈 문자열이어야 한다 (풍경·사물 이미지)
        XCTAssertTrue(rules.contains("empty string"))
        // subject는 포즈가 아니라 '누가/무엇'에 집중 (사이드바 목록 제목으로 쓰인다)
        XCTAssertTrue(rules.contains("subject"))
    }

    func testAllBackendPromptsIncludePoseRules() {
        let rules = PromptGuidelines.poseRules
        XCTAssertTrue(ClaudeCLIAnalyzer.prompt(imageFileName: "input.png").contains(rules))
        XCTAssertTrue(CodexCLIAnalyzer.prompt.contains(rules))
        XCTAssertTrue(PromptAnalyzer.systemPrompt.contains(rules))
    }

    func testOutputSchemaDeclaresPose() throws {
        let properties = try XCTUnwrap(PromptAnalyzer.outputSchema["properties"] as? [String: Any])
        let breakdown = try XCTUnwrap(properties["breakdown"] as? [String: Any])
        let fields = try XCTUnwrap(breakdown["properties"] as? [String: Any])
        let pose = try XCTUnwrap(fields["pose"] as? [String: Any])
        XCTAssertNotNil(pose["description"] as? String)
        let required = try XCTUnwrap(breakdown["required"] as? [String])
        XCTAssertTrue(required.contains("pose"))
    }

    // MARK: - 세 언어 프롬프트 (독립 작성 → 번역 방식)

    func testLanguageRulesMakeEnglishDefinitive() {
        let rules = PromptGuidelines.languageRules

        // 영어가 정본이고 나머지는 같은 내용이어야 한다
        XCTAssertTrue(rules.contains("prompt_en"))
        XCTAssertTrue(rules.lowercased().contains("same content"))
        // 축약·추가 금지 (기존에는 ko/ja가 영어의 절반 분량으로 축약됐다)
        XCTAssertTrue(rules.lowercased().contains("nothing added"))
        // 직역이 아니라 그 언어의 자연스러운 프롬프트여야 한다
        XCTAssertTrue(rules.lowercased().contains("natural"))
    }

    func testAllBackendPromptsIncludeLanguageRules() {
        let rules = PromptGuidelines.languageRules
        XCTAssertTrue(ClaudeCLIAnalyzer.prompt(imageFileName: "input.png").contains(rules))
        XCTAssertTrue(CodexCLIAnalyzer.prompt.contains(rules))
        XCTAssertTrue(PromptAnalyzer.systemPrompt.contains(rules))
    }

    /// 예전 지시("각 언어로 독립 작성")가 남아 있으면 안 된다.
    func testNoIndependentAuthoringInstructionRemains() {
        for text in [ClaudeCLIAnalyzer.prompt(imageFileName: "i.png"),
                     CodexCLIAnalyzer.prompt, PromptAnalyzer.systemPrompt] {
            XCTAssertFalse(text.contains("not a translation note"),
                           "독립 작성 지시가 남아 있음")
        }
    }

    // MARK: - 카메라 앵글·시점 (2026-09-08 사용자 지적)

    func testCameraRulesCoverAngleAndLens() {
        let rules = PromptGuidelines.cameraRules

        // 카메라 높이·기울기 — 같은 포즈라도 앵글이 다르면 전혀 다른 그림이 된다
        for axis in ["eye level", "low angle", "high angle", "camera height"] {
            XCTAssertTrue(rules.lowercased().contains(axis), "앵글 축 누락: \(axis)")
        }
        // 거리·렌즈감 (광각 왜곡 / 망원 압축)
        XCTAssertTrue(rules.lowercased().contains("lens"))
        XCTAssertTrue(rules.lowercased().contains("distance"))
        // composition 필드에 담으라는 지시
        XCTAssertTrue(rules.contains("composition"))
    }

    func testAllBackendPromptsIncludeCameraRules() {
        let rules = PromptGuidelines.cameraRules
        XCTAssertTrue(ClaudeCLIAnalyzer.prompt(imageFileName: "input.png").contains(rules))
        XCTAssertTrue(CodexCLIAnalyzer.prompt.contains(rules))
        XCTAssertTrue(PromptAnalyzer.systemPrompt.contains(rules))
    }

    func testCompositionSchemaMentionsCamera() throws {
        let properties = try XCTUnwrap(PromptAnalyzer.outputSchema["properties"] as? [String: Any])
        let breakdown = try XCTUnwrap(properties["breakdown"] as? [String: Any])
        let fields = try XCTUnwrap(breakdown["properties"] as? [String: Any])
        let composition = try XCTUnwrap(fields["composition"] as? [String: Any])
        let description = try XCTUnwrap(composition["description"] as? String)
        XCTAssertTrue(description.lowercased().contains("camera"))
    }
}

// MARK: - 핵심 3가지 (2026-09-15, A/B 검증 후 적용)

extension PromptGuidelinesTests {

    /// 긴 프롬프트에서 무엇이 중요한지 알려주는 장치. 3개로 못 박아야 의미가 있다.
    func testKeyFeatureRulesDemandExactlyThree() {
        let r = PromptGuidelines.keyFeatureRules
        XCTAssertTrue(r.contains("key_features"))
        XCTAssertTrue(r.lowercased().contains("three") || r.contains("3"))
        // 앞쪽에 실려야 효과가 있다 (뒤에 묻히면 넣으나 마나)
        XCTAssertTrue(r.lowercased().contains("first two sentences"))
    }

    /// 세 백엔드가 같은 규칙을 받아야 결과가 갈리지 않는다.
    func testAllBackendsAskForKeyFeatures() {
        XCTAssertTrue(ClaudeCLIAnalyzer.prompt(imageFileName: "a.png").contains("key_features"))
        XCTAssertTrue(CodexCLIAnalyzer.prompt.contains("key_features"))
        XCTAssertTrue(PromptAnalyzer.systemPrompt.contains("key_features"))
        // 구조화 출력 스키마에도 있어야 API 백엔드가 실제로 채운다
        let props = PromptAnalyzer.outputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(props?["key_features"])
    }
}

// MARK: - UI 제외 · 차원 고정 · 간략 프롬프트 (2026-09-17 사용자 요청)

extension PromptGuidelinesTests {

    /// 자막·HUD·워터마크는 그림이 아니라 화면에 얹힌 것 — 재현 대상이 아니다.
    func testExclusionRulesCoverOverlays() {
        let r = PromptGuidelines.exclusionRules.lowercased()
        for sign in ["subtitle", "watermark", "hud", "timestamp", "button", "cursor"] {
            XCTAssertTrue(r.contains(sign), "제외 대상 누락: \(sign)")
        }
        XCTAssertTrue(r.contains("do not describe") || r.contains("ignore"))
    }

    /// 원본이 2D인데 생성본이 입체로 나오던 원인 — 맨 "semi-realistic"이
    /// 3D 렌더링 지시로 읽힌다. 차원을 첫 문장에 못 박게 한다.
    func testDimensionRulesPinDimensionInFirstSentence() {
        let r = PromptGuidelines.dimensionRules.lowercased()
        XCTAssertTrue(r.contains("2d"))
        XCTAssertTrue(r.contains("3d"))
        XCTAssertTrue(r.contains("first sentence"))
    }

    /// **금지가 아니라 한정이다.** 반실사 2D 일러스트는 실재하므로
    /// "semi-realistic"이 정확한 묘사일 수 있다 — 쓰되 혼자 두지 않게 한다.
    func testAmbiguousWordsAreQualifiedNotBanned() {
        let r = PromptGuidelines.dimensionRules.lowercased()
        XCTAssertTrue(r.contains("semi-realistic"))
        XCTAssertFalse(r.contains("never use \"semi-realistic"),
                       "단어를 통째로 금지하면 원본의 성격을 적을 수 없다")
        XCTAssertTrue(r.contains("never on their own") || r.contains("on their own"),
                      "단독 사용만 막아야 한다")
        // 진짜 입체인 원본을 평면으로 적으면 그것도 왜곡이다
        XCTAssertTrue(r.contains("never flatten"))
    }

    /// 간략 프롬프트는 길이 상한이 있어야 의미가 있다.
    func testShortPromptRulesSetALimit() {
        let r = PromptGuidelines.shortPromptRules
        XCTAssertTrue(r.contains("prompt_short"))
        XCTAssertTrue(r.lowercased().contains("characters") || r.contains("300"))
    }

    /// 세 백엔드가 같은 규칙을 받아야 한다.
    func testAllBackendsCarryNewRules() {
        for prompt in [ClaudeCLIAnalyzer.prompt(imageFileName: "a.png"),
                       CodexCLIAnalyzer.prompt, PromptAnalyzer.systemPrompt] {
            XCTAssertTrue(prompt.contains("prompt_short"), "간략 프롬프트 지시 누락")
            XCTAssertTrue(prompt.lowercased().contains("watermark"), "제외 지시 누락")
            XCTAssertTrue(prompt.lowercased().contains("semi-realistic"), "차원 지시 누락")
        }
        let props = PromptAnalyzer.outputSchema["properties"] as? [String: Any]
        XCTAssertNotNil(props?["prompt_short"])
    }
}
