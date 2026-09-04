import XCTest
@testable import CaptureToPrompt

/// codex 이미지 생성 실 호출 통합 테스트. ChatGPT 구독 사용량을 쓰므로
/// RUN_CODEXIMG_E2E=1 환경변수를 준 경우에만 실행된다.
final class CodexImageGenIntegrationTests: XCTestCase {

    func testRealImageGenerationThroughCodex() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CODEXIMG_E2E"] == "1",
                          "RUN_CODEXIMG_E2E=1 일 때만 실행")
        try XCTSkipIf(CodexCLIAnalyzer.locateBinary() == nil, "codex CLI 없음")

        let data = try await CodexImageGenerator().generate(
            prompt: "a tiny blue triangle centered on a plain white background, flat minimal")

        XCTAssertGreaterThan(data.count, 1000, "이미지치고 너무 작음: \(data.count) bytes")
        print("Codex ImageGen E2E OK — \(data.count) bytes")
    }
}
