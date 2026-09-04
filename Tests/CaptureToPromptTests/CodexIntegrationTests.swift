import XCTest
@testable import CaptureToPrompt

/// 실 codex CLI 호출 통합 테스트. 느리고 ChatGPT 구독 사용량을 쓰므로
/// RUN_CODEX_E2E=1 환경변수를 준 경우에만 실행된다.
final class CodexIntegrationTests: XCTestCase {

    func testRealAnalyzeThroughCodexCLI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CODEX_E2E"] == "1",
                          "RUN_CODEX_E2E=1 일 때만 실행")
        try XCTSkipIf(CodexCLIAnalyzer.locateBinary() == nil, "codex CLI 없음")

        let imagePath = ProcessInfo.processInfo.environment["E2E_IMAGE"]
            ?? "/System/Library/CoreServices/DefaultDesktop.heic"
        let raw = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let normalized = try XCTUnwrap(ImageProcessor.normalize(raw), "이미지 정규화 실패")

        let analysis = try await CodexCLIAnalyzer().analyze(
            imageData: normalized.data, mediaType: normalized.mediaType)

        XCTAssertFalse(analysis.promptEn.isEmpty)
        XCTAssertFalse(analysis.promptKo.isEmpty)
        XCTAssertFalse(analysis.promptJa.isEmpty)
        XCTAssertFalse(analysis.breakdown.subject.isEmpty)
        XCTAssertFalse(analysis.breakdown.tags.isEmpty)

        for prompt in [analysis.promptEn, analysis.promptKo, analysis.promptJa] {
            XCTAssertFalse(prompt.contains(" --"), "플래그 발견: \(prompt.suffix(60))")
        }
        print("Codex E2E OK — subject: \(analysis.breakdown.subject)")
        // 백엔드가 달라도 결과 형식은 같아야 한다 — 화풍 5축 + 인물 포즈
        let style = analysis.breakdown.style
        for label in ["Line work:", "Shading:", "Color:", "Rendering:", "Finish:"] {
            XCTAssertTrue(style.contains(label), "style 축 누락(\(label)): \(style)")
        }
        if ProcessInfo.processInfo.environment["E2E_EXPECT_FIGURE"] == "1" {
            XCTAssertFalse(analysis.breakdown.pose.isEmpty, "인물 이미지인데 pose가 비어 있음")
        }
        print("Codex E2E OK — style: \(style.prefix(120))")
        print("Codex E2E OK — pose : \(analysis.breakdown.pose.isEmpty ? "(없음)" : String(analysis.breakdown.pose.prefix(120)))")
        print("Codex E2E OK — prompt_ko: \(analysis.promptKo.prefix(120))")
    }
}
