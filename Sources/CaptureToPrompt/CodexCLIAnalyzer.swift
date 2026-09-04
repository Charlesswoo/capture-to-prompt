import Foundation

/// OpenAI Codex CLI(`codex exec`) 헤드리스 백엔드. ChatGPT 구독 로그인을 그대로 사용한다.
/// 이미지는 `-i`로 첨부하고, `--output-schema`로 구조화 출력을 강제하며,
/// 최종 메시지는 `-o` 파일에서 읽는다.
struct CodexCLIAnalyzer {
    static func locateBinary() -> String? {
        CLILocator.locate(binary: "codex")
    }

    static let prompt = """
    Analyze the attached image as an expert prompt engineer for AI image generation \
    tools (Midjourney, Stable Diffusion, DALL-E). Reproducing the ORIGINAL DRAWING \
    STYLE matters as much as the subject. Analyze subject, composition, art style, \
    lighting, color palette, materials, and mood, then produce a single detailed \
    generation-ready prompt that would recreate the look of this image. \
    Respond with ONLY a raw JSON object (no markdown fences, no commentary) with \
    exactly these keys: prompt_en, prompt_ko, prompt_ja (each a self-contained \
    detailed prompt in that language, not a translation note), and breakdown \
    (object with keys: subject, style, composition, lighting, color_palette, mood, \
    medium, tags (array of short lowercase english strings)). \
    \(PromptGuidelines.poseRules)
    \(PromptGuidelines.styleRules)
    """

    /// 인자 구성 (테스트 가능하도록 분리). 프롬프트는 반드시 마지막.
    static func buildArguments(prompt: String, imagePath: String,
                               schemaPath: String, outputPath: String) -> [String] {
        [
            "exec",
            "-i", imagePath,
            "--output-schema", schemaPath,
            "-o", outputPath,
            "--ephemeral",           // 세션 파일 미저장
            "--skip-git-repo-check", // 임시 폴더에서 실행
            "-s", "read-only",       // 셸 실행 불필요 — 최소 권한
            "--color", "never",
            prompt,
        ]
    }

    /// 텍스트 전용 인자 (이미지 첨부 없이). 프롬프트는 반드시 마지막.
    static func buildTextArguments(prompt: String, schemaPath: String,
                                   outputPath: String) -> [String] {
        [
            "exec",
            "--output-schema", schemaPath,
            "-o", outputPath,
            "--ephemeral",
            "--skip-git-repo-check",
            "-s", "read-only",
            "--color", "never",
            prompt,
        ]
    }

    /// 텍스트 요청 1회 — 모델의 원문 응답을 돌려준다.
    func complete(prompt: String, schema: [String: Any]) async throws -> String {
        guard let binary = Self.locateBinary() else {
            throw AnalyzerError.apiError(
                status: 0,
                message: "codex CLI를 찾을 수 없습니다. OpenAI Codex CLI 설치 후 로그인하세요 (brew install codex 또는 npm i -g @openai/codex).")
        }
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-codextext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let schemaURL = workDir.appendingPathComponent("schema.json")
        try JSONSerialization.data(withJSONObject: schema).write(to: schemaURL)
        let outputURL = workDir.appendingPathComponent("last-message.txt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildTextArguments(prompt: prompt, schemaPath: schemaURL.path,
                                                    outputPath: outputURL.path)
        process.environment = CLILocator.augmentedEnvironment()
        process.currentDirectoryURL = workDir
        process.standardInput = FileHandle.nullDevice  // codex exec는 stdin이 열려 있으면 hang
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        async let outData = readToEnd(stdout)
        async let errData = readToEnd(stderr)
        await Task.detached { process.waitUntilExit() }.value
        _ = await outData

        guard process.terminationStatus == 0 else {
            let err = String(data: await errData, encoding: .utf8) ?? ""
            throw CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, what: "분석")
        }
        guard let text = try? String(contentsOf: outputURL, encoding: .utf8), !text.isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        return text
    }

    /// `-o` 파일 내용 → PromptAnalysis (테스트 가능하도록 분리).
    static func parseOutput(_ data: Data) throws -> PromptAnalysis {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        let json = ClaudeCLIAnalyzer.stripFences(text)
        guard let jsonData = json.data(using: .utf8) else { throw AnalyzerError.emptyResponse }
        do {
            return try JSONDecoder().decode(PromptAnalysis.self, from: jsonData)
        } catch {
            throw AnalyzerError.fromNonJSONResponse(json)
        }
    }

    func analyze(imageData: Data, mediaType: String) async throws -> PromptAnalysis {
        guard let binary = Self.locateBinary() else {
            throw AnalyzerError.apiError(
                status: 0,
                message: "codex CLI를 찾을 수 없습니다. OpenAI Codex CLI 설치 후 로그인하세요 (brew install codex 또는 npm i -g @openai/codex).")
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let ext = mediaType == "image/png" ? "png" : "jpg"
        let imageURL = workDir.appendingPathComponent("input.\(ext)")
        try imageData.write(to: imageURL)
        let schemaURL = workDir.appendingPathComponent("schema.json")
        try JSONSerialization.data(withJSONObject: PromptAnalyzer.outputSchema)
            .write(to: schemaURL)
        let outputURL = workDir.appendingPathComponent("last-message.txt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildArguments(
            prompt: Self.prompt, imagePath: imageURL.path,
            schemaPath: schemaURL.path, outputPath: outputURL.path)
        process.environment = CLILocator.augmentedEnvironment()
        process.currentDirectoryURL = workDir
        // codex exec는 stdin이 열려 있으면 hang — 반드시 닫는다
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        // 파이프 버퍼가 차서 블록되지 않도록 stdout/stderr 모두 소비한다
        async let outData = readToEnd(stdout)
        async let errData = readToEnd(stderr)
        await Task.detached { process.waitUntilExit() }.value
        _ = await outData

        guard process.terminationStatus == 0 else {
            let err = String(data: await errData, encoding: .utf8) ?? ""
            throw CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, what: "분석")
        }
        let output = (try? Data(contentsOf: outputURL)) ?? Data()
        return try Self.parseOutput(output)
    }

    private func readToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}
