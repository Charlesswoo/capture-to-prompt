import Foundation

/// API 키 없이 로컬에 로그인된 Claude Code CLI(`claude -p`)로 분석하는 백엔드.
/// 구독 로그인을 그대로 사용하므로 별도 키가 필요 없다.
struct ClaudeCLIAnalyzer {
    /// GUI 앱은 셸 PATH를 물려받지 못하므로 알려진 위치에서 직접 찾는다.
    static func locateBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return candidatePaths(home: home, nvmVersions: CLILocator.nvmVersionDirs(home: home))
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 설정에서 지정한 경로가 있으면 그것만 쓴다 (잘못됐으면 실패 — 조용한 폴백은
    /// "지정했는데 딴 걸 쓰는" 혼란을 만든다). 비어 있으면 자동 탐색.
    static func resolveBinary(custom: String) -> String? {
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return locateBinary() }
        return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
    }

    /// 공용 후보(CLILocator) + claude 전용 위치. 기존 테스트 호환용 시그니처 유지.
    static func candidatePaths(home: String, nvmVersions: [String]) -> [String] {
        var candidates = CLILocator.candidatePaths(
            binary: "claude", home: home, nvmVersions: nvmVersions)
        candidates.insert("\(home)/.claude/local/claude", at: 1)
        return candidates
    }

    /// 기존 테스트 호환용 — 실제 구현은 CLILocator.
    static func augmentedPATH(base: String, home: String, nvmVersions: [String]) -> String {
        CLILocator.augmentedPATH(base: base, home: home, nvmVersions: nvmVersions)
    }

    static func augmentedEnvironment() -> [String: String] {
        CLILocator.augmentedEnvironment()
    }

    static func prompt(imageFileName: String) -> String {
        """
        Read the image file ./\(imageFileName) and analyze it as an expert prompt \
        engineer for AI image generation tools (Midjourney, Stable Diffusion, DALL-E). \
        Reproducing the ORIGINAL DRAWING STYLE matters as much as the subject. \
        Analyze subject, composition, art style, lighting, color palette, materials, \
        and mood, then produce a single detailed generation-ready prompt that would \
        recreate the look of this image. Respond with ONLY a raw JSON object \
        (no markdown fences, no commentary) with exactly these keys: \
        prompt_en, prompt_ko, prompt_ja (each a self-contained detailed prompt in that \
        language, not a translation note), and breakdown (object with keys: subject, \
        style, composition, lighting, color_palette, mood, medium, \
        tags (array of short lowercase english strings)). \
        \(PromptGuidelines.poseRules)
        \(PromptGuidelines.styleRules)
        """
    }

    /// `claude -p --output-format json`의 stdout → PromptAnalysis (테스트 가능하도록 분리).
    static func parseCLIOutput(_ data: Data) throws -> PromptAnalysis {
        let json = stripFences(try parseCLIResultText(data))
        guard let jsonData = json.data(using: .utf8) else { throw AnalyzerError.emptyResponse }
        do {
            return try JSONDecoder().decode(PromptAnalysis.self, from: jsonData)
        } catch {
            throw AnalyzerError.fromNonJSONResponse(json)
        }
    }

    /// 텍스트 전용 인자 (이미지 없이 프롬프트 하나만).
    static func buildTextArguments(prompt: String) -> [String] {
        ["-p", prompt, "--output-format", "json"]
    }

    /// `--output-format json` 봉투에서 result 문자열만 꺼낸다 (JSON 해석은 호출한 쪽에서).
    static func parseCLIResultText(_ data: Data) throws -> String {
        struct Envelope: Decodable {
            let result: String?
            let isError: Bool?
            enum CodingKeys: String, CodingKey {
                case result
                case isError = "is_error"
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let result = envelope.result else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AnalyzerError.apiError(status: 0, message: "CLI 출력 해석 실패: \(raw.prefix(300))")
        }
        if envelope.isError == true {
            throw AnalyzerError.apiError(status: 0, message: result)
        }
        return result
    }

    /// 모델이 지시를 어기고 ```json 펜스로 감쌌을 때 대비.
    static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if let range = t.range(of: "```", options: .backwards) {
                t = String(t[..<range.lowerBound])
            }
        }
        // 앞뒤 잡담이 섞였을 때 첫 '{'부터 마지막 '}'까지만 취한다.
        if let first = t.firstIndex(of: "{"), let last = t.lastIndex(of: "}") {
            t = String(t[first...last])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let claudePath: String

    init(claudePath: String = "") {
        self.claudePath = claudePath
    }

    /// 텍스트 요청 1회 — 모델의 원문 응답을 돌려준다.
    func complete(prompt: String) async throws -> String {
        guard let binary = Self.resolveBinary(custom: claudePath) else {
            throw Self.binaryNotFoundError(claudePath: claudePath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildTextArguments(prompt: prompt)
        process.environment = Self.augmentedEnvironment()
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice  // 위와 같은 이유로 stdin을 닫는다
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = await readToEnd(stdout)
        await Task.detached { process.waitUntilExit() }.value
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, what: "요청")
        }
        return try Self.parseCLIResultText(outData)
    }

    /// 실행 파일을 못 찾았을 때의 안내 (analyze/complete 공용).
    static func binaryNotFoundError(claudePath: String) -> AnalyzerError {
        .apiError(
            status: 0,
            message: claudePath.isEmpty
                ? "claude CLI를 찾을 수 없습니다. 설치되어 있다면 설정에서 claude 경로를 직접 지정하세요 (터미널에서 which claude 로 확인). Claude Code가 없는 PC라면 설정에서 다른 백엔드(Codex CLI 또는 Anthropic API 키)를 선택하세요."
                : "지정된 claude 경로를 실행할 수 없습니다: \(claudePath) — 설정에서 경로를 확인하세요. (터미널에서 which claude 로 확인 가능)")
    }

    func analyze(imageData: Data, mediaType: String) async throws -> PromptAnalysis {
        guard let binary = Self.resolveBinary(custom: claudePath) else {
            throw AnalyzerError.apiError(
                status: 0,
                message: claudePath.isEmpty
                    ? "claude CLI를 찾을 수 없습니다. 설치되어 있다면 설정에서 claude 경로를 직접 지정하세요 (터미널에서 which claude 로 확인). Claude Code가 없는 PC라면 설정에서 다른 백엔드(Codex CLI 또는 Anthropic API 키)를 선택하세요."
                    : "지정된 claude 경로를 실행할 수 없습니다: \(claudePath) — 설정에서 경로를 확인하세요. (터미널에서 which claude 로 확인 가능)")
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let ext = mediaType == "image/png" ? "png" : "jpg"
        let fileName = "input.\(ext)"
        try imageData.write(to: workDir.appendingPathComponent(fileName))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", Self.prompt(imageFileName: fileName), "--output-format", "json"]
        process.environment = Self.augmentedEnvironment()
        process.currentDirectoryURL = workDir
        // stdin을 열어두면 claude가 3초를 기다렸다 진행한다 ("no stdin data received in 3s")
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = await readToEnd(stdout)
        await Task.detached { process.waitUntilExit() }.value

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            let failure = CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, what: "분석")
            guard err.contains("env: node") else { throw failure }
            throw AnalyzerError.apiError(
                status: Int(process.terminationStatus),
                message: failure.localizedDescription
                    + " — node를 찾지 못했습니다. 설정에서 claude 경로를 직접 지정해 보세요 (터미널에서 which claude 로 확인).")
        }
        return try Self.parseCLIOutput(outData)
    }

    private func readToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}
