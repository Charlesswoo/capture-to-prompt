import XCTest
@testable import CaptureToPrompt

final class PromptRevisionAdvisorTests: XCTestCase {

    // MARK: - 요청 프롬프트

    func testPromptCarriesOriginalAndRejectionReason() {
        let text = PromptRevisionAdvisor.prompt(
            originalPrompt: "a portrait of Emma Watson in the style of Greg Rutkowski",
            rejection: "Your request was rejected as a result of our safety system.")

        XCTAssertTrue(text.contains("Emma Watson"))
        XCTAssertTrue(text.contains("safety system"))
        // 응답 형식(키)을 지시해야 한다
        for key in ["summary", "issues", "phrase", "reason", "suggestion", "revised_prompt"] {
            XCTAssertTrue(text.contains(key), "프롬프트에 \(key) 키 지시가 없음")
        }
    }

    /// 거부 원문을 못 받은 경우에도 요청은 성립해야 한다.
    func testPromptWorksWithoutRejectionDetail() {
        let text = PromptRevisionAdvisor.prompt(originalPrompt: "a cat", rejection: nil)
        XCTAssertTrue(text.contains("a cat"))
        XCTAssertFalse(text.isEmpty)
    }

    /// 수정본은 원문과 같은 언어로 오게 지시해야 한다 (한국어 탭이면 한국어 프롬프트).
    func testPromptAsksToKeepOriginalLanguage() {
        let text = PromptRevisionAdvisor.prompt(originalPrompt: "고양이 사진", rejection: nil)
        XCTAssertTrue(text.lowercased().contains("same language"))
    }

    // MARK: - 응답 파싱

    private let sampleJSON = """
    {
      "summary": "실존 인물 이름과 생존 작가 화풍 지정이 문제입니다.",
      "issues": [
        {"phrase": "Emma Watson",
         "reason": "실존 인물의 사실적 묘사는 생성 정책에서 차단됩니다.",
         "suggestion": "green-eyed young woman with shoulder-length brown hair"},
        {"phrase": "in the style of Greg Rutkowski",
         "reason": "생존 작가의 화풍을 이름으로 지정하는 것은 거부됩니다.",
         "suggestion": "painterly high-fantasy illustration, dramatic lighting"}
      ],
      "revised_prompt": "a painterly portrait of a green-eyed young woman"
    }
    """

    func testParseReadsIssuesAndRevisedPrompt() throws {
        let revision = try PromptRevisionAdvisor.parse(sampleJSON)

        XCTAssertEqual(revision.issues.count, 2)
        XCTAssertEqual(revision.issues.first?.phrase, "Emma Watson")
        XCTAssertTrue(revision.issues.first?.reason.contains("실존 인물") == true)
        XCTAssertEqual(revision.issues.last?.suggestion,
                       "painterly high-fantasy illustration, dramatic lighting")
        XCTAssertEqual(revision.revisedPrompt, "a painterly portrait of a green-eyed young woman")
        XCTAssertTrue(revision.summary.contains("실존 인물"))
    }

    /// 모델이 ```json 펜스나 앞뒤 잡담을 붙여도 읽어야 한다.
    func testParseStripsFencesAndChatter() throws {
        let noisy = "여기 결과입니다:\n```json\n\(sampleJSON)\n```\n도움이 되었길!"
        let revision = try PromptRevisionAdvisor.parse(noisy)
        XCTAssertEqual(revision.issues.count, 2)
    }

    /// issues가 비어 있어도(원인 특정 실패) 수정본만 있으면 유효하다.
    func testParseAcceptsEmptyIssues() throws {
        let json = #"{"summary":"원인을 특정하지 못했습니다","issues":[],"revised_prompt":"a cat"}"#
        let revision = try PromptRevisionAdvisor.parse(json)
        XCTAssertTrue(revision.issues.isEmpty)
        XCTAssertEqual(revision.revisedPrompt, "a cat")
    }

    func testParseThrowsOnGarbage() {
        XCTAssertThrowsError(try PromptRevisionAdvisor.parse("죄송하지만 도와드릴 수 없습니다"))
    }

    /// 수정본이 비어 있으면 적용할 게 없으므로 실패로 본다.
    func testParseThrowsOnEmptyRevisedPrompt() {
        let json = #"{"summary":"s","issues":[],"revised_prompt":"   "}"#
        XCTAssertThrowsError(try PromptRevisionAdvisor.parse(json))
    }

    // MARK: - 구조화 출력 스키마

    func testOutputSchemaDeclaresRequiredKeys() throws {
        let schema = PromptRevisionAdvisor.outputSchema
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["summary"])
        XCTAssertNotNil(properties["issues"])
        XCTAssertNotNil(properties["revised_prompt"])
        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertTrue(required.contains("revised_prompt"))
    }
}
