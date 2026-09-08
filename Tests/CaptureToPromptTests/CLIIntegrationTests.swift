import XCTest
@testable import CaptureToPrompt

/// 실 CLI 호출 통합 테스트. 느리고(수십 초) 구독 사용량을 쓰므로
/// RUN_CLI_E2E=1 환경변수를 준 경우에만 실행된다.
final class CLIIntegrationTests: XCTestCase {

    func testRealAnalyzeThroughClaudeCLI() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CLI_E2E"] == "1",
                          "RUN_CLI_E2E=1 일 때만 실행")
        try XCTSkipIf(ClaudeCLIAnalyzer.locateBinary() == nil, "claude CLI 없음")

        let imagePath = ProcessInfo.processInfo.environment["E2E_IMAGE"]
            ?? "/System/Library/CoreServices/DefaultDesktop.heic"
        let raw = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let normalized = try XCTUnwrap(ImageProcessor.normalize(raw), "이미지 정규화 실패")

        let analysis = try await ClaudeCLIAnalyzer().analyze(
            imageData: normalized.data, mediaType: normalized.mediaType)

        XCTAssertFalse(analysis.promptEn.isEmpty)
        XCTAssertFalse(analysis.promptKo.isEmpty)
        XCTAssertFalse(analysis.promptJa.isEmpty)
        XCTAssertFalse(analysis.breakdown.subject.isEmpty)
        XCTAssertFalse(analysis.breakdown.tags.isEmpty)

        // 도구 전용 플래그(--ar, --v 등)가 붙지 않아야 한다
        for prompt in [analysis.promptEn, analysis.promptKo, analysis.promptJa] {
            XCTAssertFalse(prompt.contains(" --"), "플래그 발견: \(prompt.suffix(60))")
        }
        // 그림체(화풍) 규칙 — style은 다섯 축 라벨을 영어로 갖춰야 한다
        let style = analysis.breakdown.style
        for label in ["Line work:", "Shading:", "Color:", "Rendering:", "Finish:"] {
            XCTAssertTrue(style.contains(label), "style 축 누락(\(label)): \(style)")
        }
        XCTAssertLessThan(style.count, 900, "style이 지시한 700자를 크게 넘음")
        XCTAssertFalse(analysis.breakdown.medium.isEmpty)

        // 포즈: 인물이 있으면 자세가 구체적으로, 없으면 빈 문자열
        let pose = analysis.breakdown.pose
        if ProcessInfo.processInfo.environment["E2E_EXPECT_FIGURE"] == "1" {
            XCTAssertFalse(pose.isEmpty, "인물 이미지인데 pose가 비어 있음")
            XCTAssertGreaterThan(pose.count, 80, "pose가 너무 짧음: \(pose)")
        } else if ProcessInfo.processInfo.environment["E2E_EXPECT_FIGURE"] == "0" {
            XCTAssertTrue(pose.isEmpty, "인물이 없는데 pose가 채워짐: \(pose)")
        }
        print("E2E OK — pose  : \(pose.isEmpty ? "(없음)" : pose)")

        // 세 언어는 같은 내용이어야 한다 — 축약되면 한국어 탭에서 본 것과
        // 실제 생성(영어) 결과가 어긋난다
        let en = analysis.promptEn.count, ko = analysis.promptKo.count, ja = analysis.promptJa.count
        print("E2E 길이 — en \(en) / ko \(ko) / ja \(ja)")
        // 한글·가나는 글자당 정보량이 커서 영어보다 짧은 게 정상이라 길이 비율은
        // 품질 지표로 약하다(실측: 지시문을 번역 방식으로 바꿔도 ko/en은 0.48→0.51).
        // 명백한 축약만 잡는 느슨한 하한으로 둔다.
        XCTAssertGreaterThan(Double(ko) / Double(en), 0.4,
                             "한국어가 영어의 40% 미만 — 내용 누락 의심")
        XCTAssertGreaterThan(Double(ja) / Double(en), 0.3,
                             "일본어가 영어의 30% 미만 — 내용 누락 의심")

        // 카메라 시점 — 어디서 보고 있는지가 빠지면 기본 아이레벨로 렌더된다
        let composition = analysis.breakdown.composition.lowercased()
        let angleWords = ["eye level", "eye-level", "low angle", "low-angle", "high angle",
                          "high-angle", "overhead", "dutch", "looking up", "looking down",
                          "from above", "from below"]
        XCTAssertTrue(angleWords.contains { composition.contains($0) },
                      "composition에 카메라 앵글이 없음: \(analysis.breakdown.composition)")
        print("E2E OK — composition: \(analysis.breakdown.composition.prefix(160))")

        // E2E_DUMP를 주면 결과 전문을 파일로 남긴다 (언어 간 내용 대조용)
        if let dump = ProcessInfo.processInfo.environment["E2E_DUMP"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(analysis) {
                try? data.write(to: URL(fileURLWithPath: dump))
                print("E2E dump → \(dump)")
            }
        }

        print("E2E OK — subject: \(analysis.breakdown.subject)")
        print("E2E OK — style : \(style)")
        print("E2E OK — medium: \(analysis.breakdown.medium)")
        print("E2E OK — prompt_en 앞머리: \(analysis.promptEn.prefix(160))")
        print("E2E OK — prompt_ko 앞머리: \(analysis.promptKo.prefix(120))")
    }

    /// 두 이미지를 동시에 분석했을 때 실제로 겹쳐서 도는지 (순차면 합계, 병렬이면 최대값).
    func testTwoAnalysesRunConcurrently() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CLI_E2E"] == "1",
                          "RUN_CLI_E2E=1 일 때만 실행")
        try XCTSkipIf(ClaudeCLIAnalyzer.locateBinary() == nil, "claude CLI 없음")
        guard let p1 = ProcessInfo.processInfo.environment["E2E_IMAGE"],
              let p2 = ProcessInfo.processInfo.environment["E2E_IMAGE2"] else {
            throw XCTSkip("E2E_IMAGE / E2E_IMAGE2 필요")
        }

        func normalized(_ path: String) throws -> (data: Data, mediaType: String) {
            let raw = try Data(contentsOf: URL(fileURLWithPath: path))
            return try XCTUnwrap(ImageProcessor.normalize(raw))
        }
        let a = try normalized(p1)
        let b = try normalized(p2)

        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            async let first = ClaudeCLIAnalyzer().analyze(imageData: a.data, mediaType: a.mediaType)
            async let second = ClaudeCLIAnalyzer().analyze(imageData: b.data, mediaType: b.mediaType)
            let (r1, r2) = try await (first, second)
            XCTAssertFalse(r1.promptEn.isEmpty)
            XCTAssertFalse(r2.promptEn.isEmpty)
        }
        print("E2E 병렬 2건 총 소요: \(elapsed)")
        // 한 건이 60~90초이므로 순차라면 120초를 훌쩍 넘는다
        XCTAssertLessThan(elapsed, .seconds(115), "두 분석이 겹쳐 돌지 않은 것으로 보임")
    }
}
