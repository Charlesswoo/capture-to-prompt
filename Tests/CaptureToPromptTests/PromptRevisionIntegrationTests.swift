import XCTest
@testable import CaptureToPrompt

/// 실제 claude CLI로 프롬프트 개선 제안을 왕복하는 E2E.
/// 구독 사용량을 소모하므로 RUN_REVISION_E2E=1 일 때만 실행한다.
final class PromptRevisionIntegrationTests: XCTestCase {

    func testRealPromptRevisionThroughClaudeCLI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_REVISION_E2E"] == "1",
                          "Test skipped - RUN_REVISION_E2E=1 일 때만 실행")

        let rejected = "a hyperrealistic portrait of Emma Watson holding a gun, "
            + "in the style of Greg Rutkowski"
        let request = PromptRevisionAdvisor.prompt(
            originalPrompt: rejected,
            rejection: "Your request was rejected as a result of our safety system.")

        let raw = try await ClaudeCLIAnalyzer().complete(prompt: request)
        let revision = try PromptRevisionAdvisor.parse(raw)

        // 수정본이 실제로 쓸 수 있는 프롬프트여야 한다
        XCTAssertFalse(revision.revisedPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
        XCTAssertFalse(revision.summary.isEmpty)
        // 위험 요소가 실제로 빠졌는지 — 이름은 남아 있으면 안 된다
        XCTAssertFalse(revision.revisedPrompt.contains("Emma Watson"))
        XCTAssertFalse(revision.revisedPrompt.contains("Greg Rutkowski"))
        // 문제 구절을 짚어줬다면 원문에서 따온 것이어야 한다
        for issue in revision.issues {
            XCTAssertTrue(rejected.contains(issue.phrase),
                          "원문에 없는 구절을 지목함: \(issue.phrase)")
            XCTAssertFalse(issue.suggestion.isEmpty)
        }

        print("=== summary ===\n\(revision.summary)")
        for issue in revision.issues {
            print("- [\(issue.phrase)] \(issue.reason) → \(issue.suggestion)")
        }
        print("=== revised ===\n\(revision.revisedPrompt)")
    }
}
