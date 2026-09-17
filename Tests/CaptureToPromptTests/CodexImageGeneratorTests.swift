import XCTest
@testable import CaptureToPrompt

final class CodexImageGeneratorTests: XCTestCase {

    func testBuildArgumentsContainRequiredFlags() {
        let args = CodexImageGenerator.buildArguments(
            prompt: "a red circle", outputPath: "/tmp/out.txt")

        XCTAssertEqual(args.first, "exec")
        // 이미지 파일을 저장해야 하므로 read-only가 아니라 workspace-write
        XCTAssertTrue(args.contains("workspace-write"))
        XCTAssertFalse(args.contains("read-only"))
        XCTAssertTrue(args.contains("--skip-git-repo-check"))
        XCTAssertTrue(args.contains("--ephemeral"))
        XCTAssertTrue(args.contains("-o") && args.contains("/tmp/out.txt"))
        // 마지막 인자(프롬프트)에 사용자 프롬프트와 저장 파일명이 포함되어야 함
        let final = args.last ?? ""
        XCTAssertTrue(final.contains("a red circle"))
        XCTAssertTrue(final.contains(CodexImageGenerator.outputImageName))
    }

    func testFindGeneratedImagePicksExpectedFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeximg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let expected = dir.appendingPathComponent(CodexImageGenerator.outputImageName)
        try Data([0x89, 0x50]).write(to: expected)

        XCTAssertEqual(CodexImageGenerator.findGeneratedImage(in: dir), expected)
    }

    /// 모델이 지시를 어기고 다른 이름으로 저장했을 때 이미지 확장자 파일로 폴백.
    func testFindGeneratedImageFallsBackToAnyImageFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeximg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data([1]).write(to: dir.appendingPathComponent("notes.txt"))
        let stray = dir.appendingPathComponent("picture.webp")
        try Data([2]).write(to: stray)

        // contentsOfDirectory는 /var → /private/var 로 심링크를 풀어 반환하므로 표준화 비교
        XCTAssertEqual(CodexImageGenerator.findGeneratedImage(in: dir)?.resolvingSymlinksInPath(),
                       stray.resolvingSymlinksInPath())
    }

    func testFindGeneratedImageNilWhenNone() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeximg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(CodexImageGenerator.findGeneratedImage(in: dir))
    }

    // MARK: - 변형 생성 (참조 이미지 첨부)

    func testBuildArgumentsAttachReferenceImages() {
        let args = CodexImageGenerator.buildArguments(
            prompt: "make it night", outputPath: "/tmp/out.txt",
            referenceImagePaths: ["/tmp/ref.png"])

        // codex exec -i/--image 로 참조 이미지를 첨부한다
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/ref.png"))
        // 프롬프트도 첨부 이미지를 바탕으로 하라고 지시해야 한다
        let final = args.last ?? ""
        XCTAssertTrue(final.contains("make it night"))
        XCTAssertTrue(final.lowercased().contains("attached"))
    }

    func testBuildArgumentsWithoutReferenceHasNoImageFlag() {
        let args = CodexImageGenerator.buildArguments(
            prompt: "a red circle", outputPath: "/tmp/out.txt")
        XCTAssertFalse(args.contains("-i"))
    }

    // MARK: - 거부 판별 (codex는 파일을 저장하지 않고 정상 종료한다)

    func testFailureFromRefusalMessageIsContentPolicy() {
        let message = "I can't create that image because it violates the content policy."
        let error = CodexImageGenerator.failure(lastMessage: message)
        guard case AnalyzerError.contentPolicy = error else {
            return XCTFail("expected contentPolicy, got \(error)")
        }
    }

    func testFailureFromSafetyWordingIsContentPolicy() {
        let error = CodexImageGenerator.failure(
            lastMessage: "Sorry, this request was blocked by our safety system.")
        guard case AnalyzerError.contentPolicy = error else {
            return XCTFail("expected contentPolicy, got \(error)")
        }
    }

    /// 정책과 무관한 실패는 원인을 그대로 보여준다 (문구가 오해를 주지 않아야 한다).
    func testFailureFromOtherReasonKeepsDetail() {
        let error = CodexImageGenerator.failure(lastMessage: "disk full while writing output")
        guard case AnalyzerError.apiError(_, let message) = error else {
            return XCTFail("expected apiError, got \(error)")
        }
        XCTAssertTrue(message.contains("disk full"))
        XCTAssertFalse(error.localizedDescription.contains("저장하지 않았습니다"))
    }

    /// 거부 사유가 길어도 200자에서 잘려 원인을 못 읽는 일이 없어야 한다.
    func testFailureKeepsLongDetail() {
        let long = String(repeating: "가", count: 500)
        let error = CodexImageGenerator.failure(lastMessage: long)
        XCTAssertGreaterThan(error.localizedDescription.count, 400)
    }

    // MARK: - 프로세스 실패 메시지 (2026-09-04)

    /// 외부에서 종료된 경우(SIGTERM 등)는 "생성 실패"가 아니라 중단으로 알린다.
    func testSignalTerminationReportsInterruption() {
        let error = CLIProcessFailure.error(status: 15, wasSignal: true,
                                            stderr: "hook: PostToolUse Completed",
                                            what: "이미지 생성")
        guard case AnalyzerError.apiError(_, let message) = error else {
            return XCTFail("expected apiError, got \(error)")
        }
        XCTAssertTrue(message.contains("중단"))
        XCTAssertFalse(message.contains("hook:"))   // 무의미한 로그는 싣지 않는다
    }

    /// codex는 stderr에 프롬프트 조각·hook 로그를 뱉는다 — 원인이 될 줄만 추려야 한다.
    func testStderrPicksMeaningfulLines() {
        let noisy = """
        built-in `image_gen` for actual transparency and preserve its alpha.

        More principles shared by both modes: `references/prompting.md`.
        Copy/paste specs shared by both modes: `references/sample-prompts.md`.

        ERROR: stream disconnected before completion
        hook: PostToolUse
        hook: PostToolUse Completed
        """
        let error = CLIProcessFailure.error(status: 1, wasSignal: false,
                                            stderr: noisy, what: "이미지 생성")
        guard case AnalyzerError.apiError(_, let message) = error else {
            return XCTFail("expected apiError, got \(error)")
        }
        XCTAssertTrue(message.contains("stream disconnected"), "원인 줄 누락: \(message)")
        XCTAssertFalse(message.contains("hook: PostToolUse"))
        XCTAssertFalse(message.contains("sample-prompts.md"))
    }

    /// 원인으로 보이는 줄이 없으면 마지막 실질 줄이라도 보여준다.
    func testStderrFallsBackToLastRealLine() {
        let error = CLIProcessFailure.error(status: 2, wasSignal: false,
                                            stderr: "warming up\n\nsomething odd happened\n\n",
                                            what: "분석")
        guard case AnalyzerError.apiError(_, let message) = error else {
            return XCTFail("expected apiError, got \(error)")
        }
        XCTAssertTrue(message.contains("something odd happened"))
    }

    func testEmptyStderrStillDescribesFailure() {
        let error = CLIProcessFailure.error(status: 1, wasSignal: false, stderr: "  \n ",
                                            what: "이미지 생성")
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}

// MARK: - 내장 이미지 생성 툴 없음 (2026-09-16 사용자 보고)

extension CodexImageGeneratorTests {

    /// codex를 API 키 모드로 쓰면 내장 image_generation을 못 쓴다
    /// (ChatGPT 구독 로그인 전용). 원문만 보면 무엇을 바꿔야 할지 알 수 없다.
    func testToolUnavailableSuggestsSwitchingEngine() {
        let message = "The built-in image generation tool is unavailable in this session, "
            + "so I couldn’t create `generated.png`. A CLI fallback exists but requires "
            + "your explicit authorization and `OPENAI_API_KEY`."

        let error = CodexImageGenerator.failure(lastMessage: message)

        let text = error.localizedDescription
        XCTAssertTrue(text.contains("설정"), "안내가 없음: \(text)")
        XCTAssertTrue(text.contains("OpenAI"), "어디로 바꿀지 없음: \(text)")
        // 정책 거부로 잘못 분류하면 엉뚱하게 프롬프트 개선안을 권하게 된다
        if case .contentPolicy = error { XCTFail("정책 거부로 오분류됨") }
    }

    /// 진짜 정책 거부는 그대로 정책 거부여야 한다.
    func testRealRefusalStillContentPolicy() {
        let error = CodexImageGenerator.failure(
            lastMessage: "I can't create that image — it violates the content policy.")
        guard case .contentPolicy = error else {
            return XCTFail("정책 거부가 아님")
        }
    }
}

// MARK: - stderr 노이즈·엉뚱한 안내 (2026-09-17 사용자 보고)

extension CodexImageGeneratorTests {

    /// codex는 MCP 워커 오류·hook 경고를 stderr에 섞어 뱉는다.
    /// 그게 원인으로 표시되면 진짜 원인이 가려진다.
    private var noisyStderr: String {
        """
        warning: clamping SessionEnd hook timeout to 3s in \
        /Users/charles/.codex/plugins/cache/openai-codex/codex/1.0.6/hooks/hooks.json
        2026-09-17T08:55:32.664172Z ERROR rmcp::transport::worker: worker quit with fatal: \
        Transport channel closed, when AuthRequired(AuthRequiredError { \
        www_authenticate_header: "Bearer realm=\\"mcp\\", \
        resource_metadata=\\"https://mcp.railway.com/.well-known/oauth-protected-resource\\"" })
        """
    }

    func testMCPAndHookNoiseIsFilteredOut() {
        let detail = CLIProcessFailure.detail(stderr: noisyStderr, stdout: "")
        XCTAssertFalse(detail.contains("rmcp::transport"), "MCP 워커 오류가 실림: \(detail)")
        XCTAssertFalse(detail.contains("hooks.json"), "hook 경고가 실림: \(detail)")
    }

    /// Railway MCP의 AuthRequired는 CLI 로그인과 무관하다.
    /// 여기에 "claude로 로그인하세요"가 붙으면 완전히 엉뚱한 안내가 된다.
    func testMCPAuthErrorDoesNotTriggerLoginHint() {
        XCTAssertTrue(CLIProcessFailure.loginHint(noisyStderr).isEmpty,
                      "MCP 인증 오류에 로그인 안내가 붙음")
    }

    /// 안내는 특정 CLI를 박지 않는다 — codex 실패에 "claude로 로그인"이 붙으면 틀린다.
    func testHintDoesNotHardcodeSingleCLI() {
        let hint = CLIProcessFailure.loginHint("Failed to authenticate: OAuth session expired")
        XCTAssertTrue(hint.contains("codex"), "codex 경로에서도 맞는 안내여야 한다")
    }

    /// 진짜 CLI 로그인 만료에만 붙어야 한다.
    func testRealSessionExpiryStillGetsHint() {
        XCTAssertFalse(CLIProcessFailure.loginHint(
            "Failed to authenticate: OAuth session expired and could not be refreshed").isEmpty)
    }
}
