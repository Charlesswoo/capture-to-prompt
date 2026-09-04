import XCTest
@testable import CaptureToPrompt

/// llm-router 실 호출 통합 테스트. 로컬에 llm-router가 떠 있어야 하므로
/// RUN_ROUTER_E2E=1 + LLM_ROUTER_API_KEY 를 준 경우에만 실행된다.
/// 주의: mock 모드(프로바이더 키 없음)에서는 스키마 합성 placeholder가 오므로
/// 배선(요청 수락·vision 페이로드·응답 디코딩)까지만 검증한다.
final class RouterIntegrationTests: XCTestCase {

    func testRealAnalyzeThroughLLMRouter() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_ROUTER_E2E"] == "1", "RUN_ROUTER_E2E=1 일 때만 실행")
        let apiKey = try XCTUnwrap(env["LLM_ROUTER_API_KEY"], "LLM_ROUTER_API_KEY 필요")

        let imagePath = env["E2E_IMAGE"] ?? "/System/Library/CoreServices/DefaultDesktop.heic"
        let raw = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let normalized = try XCTUnwrap(ImageProcessor.normalize(raw), "이미지 정규화 실패")

        let analyzer = LLMRouterAnalyzer(
            baseURL: env["LLM_ROUTER_BASE_URL"] ?? LLMRouterAnalyzer.defaultBaseURL,
            apiKey: apiKey,
            model: env["LLM_ROUTER_MODEL"] ?? LLMRouterAnalyzer.defaultModel)
        let analysis = try await analyzer.analyze(
            imageData: normalized.data, mediaType: normalized.mediaType)

        print("Router E2E OK — subject: \(analysis.breakdown.subject)")
        print("Router E2E OK — prompt_ko: \(analysis.promptKo.prefix(120))")
    }
}
