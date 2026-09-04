import XCTest
@testable import CaptureToPrompt

final class ClaudeCLIAnalyzerTests: XCTestCase {

    private let sampleAnalysisJSON = """
    {"prompt_en":"a cat","prompt_ko":"고양이","prompt_ja":"猫","breakdown":{"subject":"cat",\
    "style":"photo","composition":"close-up","lighting":"soft","color_palette":"warm",\
    "mood":"calm","medium":"photography","tags":["cat"]}}
    """

    private func envelope(result: String, isError: Bool = false) -> Data {
        let obj: [String: Any] = ["type": "result", "result": result, "is_error": isError]
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    func testParseCLIOutputSuccess() throws {
        let analysis = try ClaudeCLIAnalyzer.parseCLIOutput(envelope(result: sampleAnalysisJSON))
        XCTAssertEqual(analysis.promptKo, "고양이")
        XCTAssertEqual(analysis.breakdown.tags, ["cat"])
    }

    func testParseCLIOutputWithMarkdownFences() throws {
        let fenced = "```json\n\(sampleAnalysisJSON)\n```"
        let analysis = try ClaudeCLIAnalyzer.parseCLIOutput(envelope(result: fenced))
        XCTAssertEqual(analysis.promptEn, "a cat")
    }

    func testParseCLIOutputWithSurroundingChatter() throws {
        let chatty = "Here is the analysis:\n\(sampleAnalysisJSON)\nHope this helps!"
        let analysis = try ClaudeCLIAnalyzer.parseCLIOutput(envelope(result: chatty))
        XCTAssertEqual(analysis.promptJa, "猫")
    }

    func testParseCLIOutputErrorEnvelope() {
        let data = envelope(result: "usage limit reached", isError: true)
        XCTAssertThrowsError(try ClaudeCLIAnalyzer.parseCLIOutput(data)) { error in
            guard case AnalyzerError.apiError(_, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertTrue(message.contains("usage limit"))
        }
    }

    func testParseCLIOutputGarbage() {
        XCTAssertThrowsError(try ClaudeCLIAnalyzer.parseCLIOutput(Data("not json".utf8)))
    }

    // MARK: - resolveBinary
    // 자동 탐색이 모든 설치 방식을 커버할 수 없으므로 설정에서 경로를 직접 지정할 수 있다.

    func testResolveBinaryPrefersCustomPathWhenExecutable() {
        // /bin/ls 는 어디서나 실행 가능한 파일
        XCTAssertEqual(ClaudeCLIAnalyzer.resolveBinary(custom: "/bin/ls"), "/bin/ls")
    }

    func testResolveBinaryFailsWhenCustomPathInvalid() {
        // 지정했는데 잘못됐으면 자동 탐색으로 조용히 폴백하지 않는다
        XCTAssertNil(ClaudeCLIAnalyzer.resolveBinary(custom: "/nonexistent/claude"))
    }

    func testResolveBinaryFallsBackToAutoDiscoveryWhenEmpty() {
        XCTAssertEqual(ClaudeCLIAnalyzer.resolveBinary(custom: ""),
                       ClaudeCLIAnalyzer.locateBinary())
        XCTAssertEqual(ClaudeCLIAnalyzer.resolveBinary(custom: "   "),
                       ClaudeCLIAnalyzer.locateBinary())
    }

    // MARK: - candidatePaths
    // nvm 환경에서 npm i -g 로 설치한 claude는 ~/.nvm/versions/node/vX/bin/claude 에만
    // 존재한다 (실사례: v24.14.0). 고정 후보 4곳만 봐서는 못 찾는다.

    func testCandidatePathsIncludeNvmBins() {
        let paths = ClaudeCLIAnalyzer.candidatePaths(
            home: "/Users/anna", nvmVersions: ["v24.14.0"])
        XCTAssertTrue(paths.contains("/Users/anna/.nvm/versions/node/v24.14.0/bin/claude"))
        // 고정 후보가 우선, nvm은 뒤
        XCTAssertEqual(paths.first, "/Users/anna/.local/bin/claude")
    }

    func testCandidatePathsCoverAlternativePackageManagers() {
        let paths = ClaudeCLIAnalyzer.candidatePaths(home: "/Users/anna", nvmVersions: [])
        for expected in [
            "/Users/anna/.volta/bin/claude",
            "/Users/anna/.bun/bin/claude",
            "/Users/anna/Library/pnpm/claude",
            "/Users/anna/.npm-global/bin/claude",
            "/Users/anna/.asdf/shims/claude",
            "/Users/anna/.local/share/mise/shims/claude",
        ] {
            XCTAssertTrue(paths.contains(expected), "누락: \(expected)")
        }
    }

    func testCandidatePathsOrderNvmVersionsNumericallyDescending() {
        let paths = ClaudeCLIAnalyzer.candidatePaths(
            home: "/Users/anna", nvmVersions: ["v9.0.0", "v24.14.0"])
        let v24 = paths.firstIndex(of: "/Users/anna/.nvm/versions/node/v24.14.0/bin/claude")
        let v9 = paths.firstIndex(of: "/Users/anna/.nvm/versions/node/v9.0.0/bin/claude")
        XCTAssertNotNil(v24)
        XCTAssertNotNil(v9)
        XCTAssertLessThan(v24!, v9!, "숫자 기준 최신 버전을 먼저 시도해야 함")
    }

    // MARK: - augmentedPATH
    // npm 설치형 claude는 #!/usr/bin/env node 셔뱅이라, GUI 앱의 최소 PATH로 실행하면
    // "env: node: No such file or directory"(127)로 죽는다. PATH 보강이 이를 막는다.

    func testAugmentedPATHAppendsKnownNodeLocations() {
        let path = ClaudeCLIAnalyzer.augmentedPATH(
            base: "/usr/bin:/bin:/usr/sbin:/sbin", home: "/Users/dev", nvmVersions: [])
        let parts = path.split(separator: ":").map(String.init)
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/local/bin"))
        XCTAssertTrue(parts.contains("/Users/dev/.local/bin"))
        // 기존 항목은 앞자리를 유지한다
        XCTAssertEqual(parts.first, "/usr/bin")
    }

    func testAugmentedPATHDoesNotDuplicateExistingEntries() {
        let path = ClaudeCLIAnalyzer.augmentedPATH(
            base: "/opt/homebrew/bin:/usr/bin", home: "/Users/dev", nvmVersions: [])
        let parts = path.split(separator: ":").map(String.init)
        XCTAssertEqual(parts.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    func testAugmentedPATHPicksNumericallyLatestNvmVersion() {
        let path = ClaudeCLIAnalyzer.augmentedPATH(
            base: "/usr/bin", home: "/Users/dev",
            nvmVersions: ["v9.0.0", "v24.15.0", "v10.2.1"])
        XCTAssertTrue(path.contains("/Users/dev/.nvm/versions/node/v24.15.0/bin"),
                      "v9가 아니라 숫자 기준 최신인 v24가 선택되어야 함: \(path)")
        XCTAssertFalse(path.contains("/v9.0.0/"))
    }

    // MARK: - 텍스트 전용 요청 (프롬프트 개선 제안용)

    func testBuildTextArgumentsCarryPromptAndJSONOutput() {
        let args = ClaudeCLIAnalyzer.buildTextArguments(prompt: "왜 거부됐나요?")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("왜 거부됐나요?"))
        XCTAssertTrue(args.contains("--output-format") && args.contains("json"))
    }

    func testParseCLIResultTextReturnsResultField() throws {
        let data = Data(#"{"result":"{\"a\":1}","is_error":false}"#.utf8)
        XCTAssertEqual(try ClaudeCLIAnalyzer.parseCLIResultText(data), #"{"a":1}"#)
    }

    func testParseCLIResultTextThrowsOnErrorFlag() {
        let data = Data(#"{"result":"quota exceeded","is_error":true}"#.utf8)
        XCTAssertThrowsError(try ClaudeCLIAnalyzer.parseCLIResultText(data))
    }

    // MARK: - 모델이 분석을 거절했을 때

    /// JSON 대신 산문이 오면 "JSON 해석 실패"가 아니라 거절로 알려야 한다.
    func testParseCLIOutputTreatsProseAsRefusal() throws {
        let prose = "이 이미지는 재현 프롬프트를 만들어 드리기 어렵습니다. 대신 화풍만 설명드릴 수 있습니다."
        let payload = try JSONSerialization.data(
            withJSONObject: ["result": prose, "is_error": false])

        XCTAssertThrowsError(try ClaudeCLIAnalyzer.parseCLIOutput(payload)) { error in
            guard case AnalyzerError.refusal(let reason) = error else {
                return XCTFail("expected refusal, got \(error)")
            }
            // 모델이 말한 이유가 그대로 보여야 사용자가 다음 행동을 정할 수 있다
            XCTAssertTrue(reason?.contains("화풍만 설명") == true, "이유 누락: \(reason ?? "nil")")
            XCTAssertFalse(error.localizedDescription.contains("JSON"))
        }
    }

    /// JSON 형태이긴 한데 깨진 경우는 기존대로 해석 실패로 남는다.
    func testParseCLIOutputStillReportsBrokenJSON() throws {
        let payload = try JSONSerialization.data(
            withJSONObject: ["result": "{\"prompt_en\": ", "is_error": false])

        XCTAssertThrowsError(try ClaudeCLIAnalyzer.parseCLIOutput(payload)) { error in
            guard case AnalyzerError.apiError(_, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertTrue(message.contains("JSON"))
        }
    }
}
