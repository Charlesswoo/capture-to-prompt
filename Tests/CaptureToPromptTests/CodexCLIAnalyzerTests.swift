import XCTest
@testable import CaptureToPrompt

final class CodexCLIAnalyzerTests: XCTestCase {

    private let sampleAnalysisJSON = """
    {"prompt_en":"a cat","prompt_ko":"고양이","prompt_ja":"猫","breakdown":{"subject":"cat",\
    "style":"photo","composition":"close-up","lighting":"soft","color_palette":"warm",\
    "mood":"calm","medium":"photography","tags":["cat"]}}
    """

    // MARK: - buildArguments

    func testBuildArgumentsContainRequiredFlags() {
        let args = CodexCLIAnalyzer.buildArguments(
            prompt: "analyze it", imagePath: "/tmp/in.jpg",
            schemaPath: "/tmp/schema.json", outputPath: "/tmp/out.txt")

        XCTAssertEqual(args.first, "exec")
        // 이미지 첨부·구조화 출력·최종 메시지 파일
        XCTAssertTrue(args.contains("-i") && args.contains("/tmp/in.jpg"))
        XCTAssertTrue(args.contains("--output-schema") && args.contains("/tmp/schema.json"))
        XCTAssertTrue(args.contains("-o") && args.contains("/tmp/out.txt"))
        // 임시 폴더 실행 대비 + 세션 파일 미생성 + 읽기 전용 샌드박스
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
        XCTAssertTrue(args.contains("--ephemeral"))
        XCTAssertTrue(args.contains("read-only"))
        // 프롬프트는 마지막 위치 (옵션 값으로 오인되지 않게)
        XCTAssertEqual(args.last, "analyze it")
    }

    // MARK: - parseOutput (-o 파일 내용)

    func testParseOutputPlainJSON() throws {
        let analysis = try CodexCLIAnalyzer.parseOutput(Data(sampleAnalysisJSON.utf8))
        XCTAssertEqual(analysis.promptKo, "고양이")
    }

    func testParseOutputWithMarkdownFences() throws {
        let fenced = "```json\n\(sampleAnalysisJSON)\n```"
        let analysis = try CodexCLIAnalyzer.parseOutput(Data(fenced.utf8))
        XCTAssertEqual(analysis.promptJa, "猫")
    }

    func testParseOutputGarbageThrows() {
        XCTAssertThrowsError(try CodexCLIAnalyzer.parseOutput(Data("oops".utf8)))
    }

    func testParseOutputEmptyThrows() {
        XCTAssertThrowsError(try CodexCLIAnalyzer.parseOutput(Data()))
    }

    // MARK: - locate (공용 CLILocator 경유)

    func testCandidatePathsForCodexCoverCommonInstalls() {
        let paths = CLILocator.candidatePaths(
            binary: "codex", home: "/Users/dev", nvmVersions: ["v24.14.0"])
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(paths.contains("/Users/dev/.local/bin/codex"))
        // npm 설치형(@openai/codex) 대비 nvm bin도 포함
        XCTAssertTrue(paths.contains("/Users/dev/.nvm/versions/node/v24.14.0/bin/codex"))
    }

    // MARK: - 텍스트 전용 요청 (프롬프트 개선 제안용)

    func testBuildTextArgumentsHaveNoImageFlag() {
        let args = CodexCLIAnalyzer.buildTextArguments(
            prompt: "왜 거부됐나요?", schemaPath: "/tmp/s.json", outputPath: "/tmp/o.txt")

        XCTAssertEqual(args.first, "exec")
        XCTAssertFalse(args.contains("-i"))
        XCTAssertTrue(args.contains("--output-schema") && args.contains("/tmp/s.json"))
        XCTAssertTrue(args.contains("-o") && args.contains("/tmp/o.txt"))
        XCTAssertTrue(args.contains("read-only"))  // 셸 실행 불필요
        XCTAssertEqual(args.last, "왜 거부됐나요?")
    }

    /// codex도 마찬가지 — 산문 응답은 거절로 알린다.
    func testParseOutputTreatsProseAsRefusal() {
        let prose = Data("Sorry, I can't create a prompt that reproduces this image.".utf8)
        XCTAssertThrowsError(try CodexCLIAnalyzer.parseOutput(prose)) { error in
            guard case AnalyzerError.refusal = error else {
                return XCTFail("expected refusal, got \(error)")
            }
        }
    }
}
