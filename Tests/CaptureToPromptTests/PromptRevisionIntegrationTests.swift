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

    /// 한국어로 고친 프롬프트가 실제로 영어·일본어에 반영되는지 (claude CLI 왕복).
    func testRealPromptSyncThroughClaudeCLI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_REVISION_E2E"] == "1",
                          "Test skipped - RUN_REVISION_E2E=1 일 때만 실행")

        let edited = "흐린 겨울 아침, 낡은 목조 등대 앞에 선 빨간 코트의 소녀. "
            + "정면 전신 구도, 낮은 채도의 회청색 팔레트, 은은한 안개, 필름 그레인."
        let raw = try await ClaudeCLIAnalyzer().complete(
            prompt: PromptSync.prompt(edited: edited, language: .korean))

        let original = PromptAnalysis(
            promptEn: "old", promptKo: edited, promptJa: "old",
            breakdown: .init(subject: "s", style: "s", composition: "c", lighting: "l",
                             colorPalette: "p", mood: "m", medium: "d", tags: []))
        let updated = try PromptSync.apply(raw, to: original, edited: .korean)

        XCTAssertEqual(updated.promptKo, edited, "고친 한국어는 그대로 남아야 한다")
        // 한국어에만 있던 요소가 영어에도 담겨야 한다
        for keyword in ["lighthouse", "red", "coat"] {
            XCTAssertTrue(updated.promptEn.lowercased().contains(keyword),
                          "영어에 '\(keyword)' 누락: \(updated.promptEn)")
        }
        XCTAssertFalse(updated.promptJa.isEmpty)
        print("=== synced en ===\n\(updated.promptEn)")
        print("=== synced ja ===\n\(updated.promptJa.prefix(120))")
    }
}
