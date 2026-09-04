import Foundation

/// codex CLI의 image_generation 기능(stable)으로 이미지를 생성한다.
/// ChatGPT 구독 로그인을 그대로 쓰므로 API 키가 필요 없다.
/// 에이전트가 작업 폴더에 파일을 저장해야 하므로 샌드박스는 workspace-write.
struct CodexImageGenerator {
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
                + (trimmed.isEmpty ? "." : " — \(trimmed)"))
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
        process.environment = CLILocator.augmentedEnvironment()
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
        _ = await outData

        guard process.terminationStatus == 0 else {
            let err = String(data: await errData, encoding: .utf8) ?? ""
            throw CLIProcessFailure.error(
                status: process.terminationStatus,
                wasSignal: process.terminationReason == .uncaughtSignal,
                stderr: err, what: "이미지 생성")
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
