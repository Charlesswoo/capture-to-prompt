import Foundation

/// codex CLI의 image_generation 기능(stable)으로 이미지를 생성한다.
/// ChatGPT 구독 로그인을 그대로 쓰므로 API 키가 필요 없다.
/// 에이전트가 작업 폴더에 파일을 저장해야 하므로 샌드박스는 workspace-write.
struct CodexImageGenerator {

    /// 설정에 넣은 OpenAI 키. GUI 앱은 셸 환경변수를 물려받지 않으므로
    /// 우리가 직접 넘기지 않으면 codex는 키가 없다고 판단한다 (2026-09-16).
    let apiKey: String

    init(apiKey: String = "") {
        self.apiKey = apiKey
    }

    /// PATH를 보강한 환경에 키를 얹는다.
    func environment() -> [String: String] {
        var env = CLILocator.augmentedEnvironment()
        if !apiKey.isEmpty { env["OPENAI_API_KEY"] = apiKey }
        return env
    }
    static let outputImageName = "generated.png"

    static func prompt(userPrompt: String, hasReference: Bool = false) -> String {
        let base = hasReference
            ? """
              Using the attached image as the base, generate a new image with the built-in \
              image generation capability following exactly this prompt: \(userPrompt)
              """
            : """
              Generate an image with the built-in image generation capability using \
              exactly this prompt: \(userPrompt)
              """
        return """
        \(base)
        Save the generated image as ./\(outputImageName) in the current directory. \
        When the file is saved, reply with exactly: DONE
        """
    }

    /// 인자 구성 (테스트 가능하도록 분리).
    /// referenceImagePaths를 주면 `-i`로 첨부해 그 이미지를 바탕으로 변형하게 한다.
    static func buildArguments(prompt userPrompt: String, outputPath: String,
                               referenceImagePaths: [String] = []) -> [String] {
        var args = [
            "exec",
            "-o", outputPath,
            "--ephemeral",
            "--skip-git-repo-check",
            "-s", "workspace-write",
            "--color", "never",
        ]
        for path in referenceImagePaths {
            args += ["-i", path]
        }
        args.append(prompt(userPrompt: userPrompt, hasReference: !referenceImagePaths.isEmpty))
        return args
    }

    /// codex는 정책 거부든 다른 사정이든 "파일 없이 정상 종료"로 끝난다.
    /// 마지막 메시지를 보고 정책 거부인지 가려낸다 (테스트 가능하도록 분리).
    static func failure(lastMessage: String) -> AnalyzerError {
        let trimmed = lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if AnalyzerError.looksLikeContentPolicy(code: nil, message: trimmed)
            || Self.refusalPhrases.contains(where: { trimmed.lowercased().contains($0) }) {
            return .contentPolicy(trimmed.isEmpty ? nil : trimmed)
        }
        return .apiError(
            status: 0,
            message: "codex가 이미지를 만들지 못했습니다"
                + (trimmed.isEmpty ? "." : " — \(trimmed)")
                + engineHint(trimmed))
    }

    /// codex의 내장 image_generation은 **ChatGPT 구독 로그인 전용**이다.
    /// API 키 모드로 쓰면 툴이 없다고만 하고 끝나서, 무엇을 바꿔야 할지 알 수 없다
    /// (2026-09-16 사용자 보고). 앱에는 이미 OpenAI Images API 엔진이 있으니 그리로 안내한다.
    static func engineHint(_ message: String) -> String {
        let lowered = message.lowercased()
        let signs = ["image generation tool is unavailable", "openai_api_key",
                     "requires your explicit authorization", "tool is not available"]
        guard signs.contains(where: { lowered.contains($0) }) else { return "" }
        return "\n→ 설정 › 이미지 생성에 OpenAI 키를 넣으면 codex에 그 키를 넘깁니다. "
            + "그래도 같은 오류가 나면 codex의 내장 이미지 생성이 ChatGPT 구독 로그인 "
            + "전용이라 그런 것이니, 엔진을 **OpenAI 호환 Images API**로 바꾸세요."
    }

    /// 모델이 정책상 거절할 때 흔히 쓰는 표현들.
    private static let refusalPhrases = [
        "can't create", "cannot create", "can't generate", "cannot generate",
        "won't be able to", "unable to generate", "i'm not able to",
    ]

    /// 지시한 파일명을 우선 찾고, 모델이 다른 이름으로 저장했으면 이미지 확장자로 폴백.
    static func findGeneratedImage(in dir: URL) -> URL? {
        let expected = dir.appendingPathComponent(outputImageName)
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        let imageExts = ["png", "jpg", "jpeg", "webp"]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return contents.first { imageExts.contains($0.pathExtension.lowercased()) }
    }

    /// referenceImage를 주면 그 이미지를 첨부해 변형본을 만든다.
    func generate(prompt userPrompt: String, referenceImage: Data? = nil) async throws -> Data {
        guard let binary = CodexCLIAnalyzer.locateBinary() else {
            throw AnalyzerError.apiError(
                status: 0,
                message: "codex CLI를 찾을 수 없습니다. OpenAI Codex CLI 설치 후 로그인하세요 (brew install codex 또는 npm i -g @openai/codex).")
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-codeximg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let outputURL = workDir.appendingPathComponent("last-message.txt")

        // 참조 이미지는 작업 폴더에 써두고 -i로 첨부한다. 생성 결과 탐색 때 참조본을
        // 결과로 착각하지 않도록 별도 폴더에 둔다.
        var referencePaths: [String] = []
        if let referenceImage {
            let refDir = workDir.appendingPathComponent("reference")
            try FileManager.default.createDirectory(at: refDir, withIntermediateDirectories: true)
            let refURL = refDir.appendingPathComponent("reference.png")
            try referenceImage.write(to: refURL)
            referencePaths = [refURL.path]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Self.buildArguments(prompt: userPrompt, outputPath: outputURL.path,
                                                referenceImagePaths: referencePaths)
        process.environment = environment()
        process.currentDirectoryURL = workDir
        // codex exec는 stdin이 열려 있으면 hang — 반드시 닫는다
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        async let outData = readToEnd(stdout)
        async let errData = readToEnd(stderr)
        await Task.detached { process.waitUntilExit() }.value
        let out = String(data: await outData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let err = String(data: await errData, encoding: .utf8) ?? ""
            throw CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, stdout: out, what: "이미지 생성")
        }
        guard let imageURL = Self.findGeneratedImage(in: workDir),
              let data = try? Data(contentsOf: imageURL), !data.isEmpty else {
            let lastMessage = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            throw Self.failure(lastMessage: lastMessage)
        }
        return data
    }

    private func readToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}
