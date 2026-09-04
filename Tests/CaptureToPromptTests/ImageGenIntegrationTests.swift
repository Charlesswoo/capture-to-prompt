import XCTest
@testable import CaptureToPrompt

/// 실 이미지 생성 통합 테스트. 장당 과금되므로
/// RUN_IMAGEGEN_E2E=1 + OPENAI_API_KEY(또는 IMAGEGEN_API_KEY)를 준 경우에만 실행된다.
final class ImageGenIntegrationTests: XCTestCase {

    func testRealImageGeneration() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_IMAGEGEN_E2E"] == "1", "RUN_IMAGEGEN_E2E=1 일 때만 실행")
        let apiKey = env["IMAGEGEN_API_KEY"] ?? env["OPENAI_API_KEY"] ?? ""
        try XCTSkipIf(apiKey.isEmpty, "OPENAI_API_KEY 또는 IMAGEGEN_API_KEY 필요")

        let generator = ImageGenerator(
            baseURL: env["IMAGEGEN_BASE_URL"] ?? ImageGenerator.defaultBaseURL,
            apiKey: apiKey,
            model: env["IMAGEGEN_MODEL"] ?? ImageGenerator.defaultModel)
        let data = try await generator.generate(
            prompt: "a tiny red square on a white background, flat minimal test image")

        XCTAssertGreaterThan(data.count, 1000, "이미지치고 너무 작음: \(data.count) bytes")
        print("ImageGen E2E OK — \(data.count) bytes")
    }
}
