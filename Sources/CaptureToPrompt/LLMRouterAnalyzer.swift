import Foundation

/// llm-router(OpenAI 호환 단일 엔드포인트)로 분석하는 백엔드.
/// POST {baseURL}/api/v1/chat/completions, Bearer 인증.
/// 시스템 프롬프트·출력 스키마는 PromptAnalyzer 것을 그대로 재사용한다.
struct LLMRouterAnalyzer {
    static let defaultBaseURL = "http://localhost:3000"
    static let defaultModel = "auto"

    /// 요청 구성 (테스트 가능하도록 분리).
    static func buildRequest(baseURL: String, apiKey: String, model: String,
                             imageData: Data, mediaType: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingRouterKey }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/api/v1/chat/completions"),
              url.scheme != nil else {
            throw AnalyzerError.apiError(status: 0, message: "잘못된 Base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let dataURI = "data:\(mediaType);base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": PromptAnalyzer.systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": dataURI]],
                        ["type": "text", "text": "Analyze this image and generate the prompts."],
                    ],
                ],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "prompt_analysis", "schema": PromptAnalyzer.outputSchema],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 이미지 없이 텍스트만 보내는 요청 (프롬프트 개선 제안 등).
    static func buildTextRequest(baseURL: String, apiKey: String, model: String,
                                 prompt: String, schema: [String: Any]) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingRouterKey }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/api/v1/chat/completions"),
              url.scheme != nil else {
            throw AnalyzerError.apiError(status: 0, message: "잘못된 Base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
        ]
        if !schema.isEmpty {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "prompt_revision", "schema": schema],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 텍스트 응답의 본문만 꺼낸다.
    static func parseTextResponse(status: Int, data: Data) throws -> String {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?
                .error.message ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw AnalyzerError.apiError(status: status, message: message)
        }
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        return content
    }

    /// OpenAI 호환 응답 파싱 (테스트 가능하도록 분리).
    static func parseResponse(status: Int, data: Data) throws -> PromptAnalysis {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?
                .error.message ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw AnalyzerError.apiError(status: status, message: message)
        }
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw AnalyzerError.emptyResponse
        }
        let json = ClaudeCLIAnalyzer.stripFences(content)
        guard let jsonData = json.data(using: .utf8) else { throw AnalyzerError.emptyResponse }
        do {
            return try JSONDecoder().decode(PromptAnalysis.self, from: jsonData)
        } catch {
            throw AnalyzerError.fromNonJSONResponse(json)
        }
    }

    let baseURL: String
    let apiKey: String
    let model: String

    init(baseURL: String = LLMRouterAnalyzer.defaultBaseURL,
         apiKey: String,
         model: String = LLMRouterAnalyzer.defaultModel) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    /// 텍스트 요청 1회 — 모델의 원문 응답을 돌려준다.
    func complete(prompt: String, schema: [String: Any]) async throws -> String {
        let request = try Self.buildTextRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                                prompt: prompt, schema: schema)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        return try Self.parseTextResponse(
            status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    func analyze(imageData: Data, mediaType: String) async throws -> PromptAnalysis {
        let request = try Self.buildRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                            imageData: imageData, mediaType: mediaType)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseResponse(status: status, data: data)
    }
}

// MARK: - OpenAI 호환 응답 디코딩용 내부 타입

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

struct OpenAIErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let message: String
    }
    let error: Inner
}
