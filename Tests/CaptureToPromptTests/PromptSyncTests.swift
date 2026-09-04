import XCTest
@testable import CaptureToPrompt

/// 한 언어의 프롬프트를 고치면 나머지 두 언어를 같은 내용으로 맞춘다.
final class PromptSyncTests: XCTestCase {

    // MARK: - 요청 프롬프트

    func testSyncPromptCarriesSourceAndTargets() {
        let text = PromptSync.prompt(edited: "밝은 골목의 소녀, 셀 셰이딩", language: .korean)

        XCTAssertTrue(text.contains("밝은 골목의 소녀"))
        // 어느 언어에서 고쳤는지, 무엇을 만들어야 하는지 명시해야 한다
        XCTAssertTrue(text.contains("Korean"))
        XCTAssertTrue(text.contains("English"))
        XCTAssertTrue(text.contains("Japanese"))
        for key in ["prompt_en", "prompt_ko", "prompt_ja"] {
            XCTAssertTrue(text.contains(key), "키 지시 누락: \(key)")
        }
        // 번역이지 재창작이 아니어야 한다 (내용이 어긋나면 편집이 무의미해진다)
        XCTAssertTrue(text.lowercased().contains("same content"))
    }

    /// 고친 언어 자신은 그대로 둬야 한다 — 사용자가 쓴 문장을 모델이 다시 손대면 안 된다.
    func testSyncPromptKeepsEditedLanguageIntact() {
        let text = PromptSync.prompt(edited: "a cat on a wall", language: .english)
        XCTAssertTrue(text.lowercased().contains("keep") || text.lowercased().contains("verbatim"),
                      "고친 언어를 그대로 두라는 지시가 없음")
    }

    // MARK: - 응답 반영

    private let responseJSON = """
    {"prompt_en":"a girl in a bright alley, cel shading",
     "prompt_ko":"밝은 골목의 소녀, 셀 셰이딩",
     "prompt_ja":"明るい路地の少女、セルシェーディング"}
    """

    func testApplySyncedFillsOtherLanguagesOnly() throws {
        let original = PromptAnalysis(
            promptEn: "old english", promptKo: "밝은 골목의 소녀, 셀 셰이딩", promptJa: "old japanese",
            breakdown: .init(subject: "girl", style: "s", composition: "c", lighting: "l",
                             colorPalette: "p", mood: "m", medium: "d", tags: ["t"]))

        let updated = try PromptSync.apply(responseJSON, to: original, edited: .korean)

        XCTAssertEqual(updated.promptEn, "a girl in a bright alley, cel shading")
        XCTAssertEqual(updated.promptJa, "明るい路地の少女、セルシェーディング")
        // 사용자가 직접 쓴 한국어는 모델 응답으로 덮어쓰지 않는다
        XCTAssertEqual(updated.promptKo, "밝은 골목의 소녀, 셀 셰이딩")
        // 분석 메타는 건드리지 않는다
        XCTAssertEqual(updated.breakdown.subject, "girl")
    }

    func testApplyThrowsWhenTargetLanguageMissing() {
        let json = #"{"prompt_ko":"밝은 골목"}"#
        let original = PromptAnalysis(promptEn: "e", promptKo: "k", promptJa: "j",
                                      breakdown: .init(subject: "s", style: "s", composition: "c",
                                                       lighting: "l", colorPalette: "p", mood: "m",
                                                       medium: "d", tags: []))
        XCTAssertThrowsError(try PromptSync.apply(json, to: original, edited: .korean))
    }

    /// 모델이 펜스나 잡담을 붙여도 읽어야 한다.
    func testApplyStripsFences() throws {
        let noisy = "```json\n\(responseJSON)\n```"
        let original = PromptAnalysis(promptEn: "e", promptKo: "k", promptJa: "j",
                                      breakdown: .init(subject: "s", style: "s", composition: "c",
                                                       lighting: "l", colorPalette: "p", mood: "m",
                                                       medium: "d", tags: []))
        let updated = try PromptSync.apply(noisy, to: original, edited: .korean)
        XCTAssertEqual(updated.promptEn, "a girl in a bright alley, cel shading")
    }
}
