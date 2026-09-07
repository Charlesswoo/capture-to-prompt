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
}
