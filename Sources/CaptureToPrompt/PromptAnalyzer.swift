import Foundation

/// Anthropic Messages API(raw HTTP)로 이미지 → 프롬프트 분석을 수행한다.
/// Swift 공식 SDK가 없으므로 POST /v1/messages 를 직접 호출한다.
struct PromptAnalyzer {
    static let defaultModel = "claude-opus-4-8"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let systemPrompt = """
    You are an expert prompt engineer for AI image generation tools (Midjourney, \
    Stable Diffusion, DALL-E, etc.). Analyze the given image in detail: subject, \
    composition, art style, lighting, color palette, materials/textures, and mood. \
    Reproducing the ORIGINAL DRAWING STYLE matters as much as the subject. \
    Then produce a single detailed, generation-ready prompt that would recreate the \
    look of this image as closely as possible. Write the prompt in three languages \
    (English, Korean, Japanese). Also fill in the structured breakdown fields. \
    Keep tags short (1-3 words each, English, lowercase). \
    \(PromptGuidelines.languageRules)
    \(PromptGuidelines.poseRules)
    \(PromptGuidelines.styleRules)
    """

    static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "prompt_en": ["type": "string", "description": "Detailed generation-ready prompt in English"],
            "prompt_ko": ["type": "string", "description": "Detailed generation-ready prompt in Korean"],
            "prompt_ja": ["type": "string", "description": "Detailed generation-ready prompt in Japanese"],
            "breakdown": [
                "type": "object",
                "properties": [
                    "subject": ["type": "string"],
                    "pose": ["type": "string",
                             "description": PromptGuidelines.poseFieldDescription],
                    "style": ["type": "string",
                              "description": PromptGuidelines.styleFieldDescription],
                    "composition": ["type": "string"],
                    "lighting": ["type": "string"],
                    "color_palette": ["type": "string"],
                    "mood": ["type": "string"],
                    "medium": ["type": "string",
                               "description": PromptGuidelines.mediumFieldDescription],
                    "tags": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["subject", "pose", "style", "composition", "lighting",
                             "color_palette", "mood", "medium", "tags"],
                "additionalProperties": false,
            ] as [String: Any],
        ],
        "required": ["prompt_en", "prompt_ko", "prompt_ja", "breakdown"],
        "additionalProperties": false,
    ]

    /// 요청 구성 (테스트 가능하도록 분리).
    static func buildRequest(apiKey: String, model: String,
                             imageData: Data, mediaType: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": systemPrompt,
            "output_config": ["format": ["type": "json_schema", "schema": outputSchema]],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mediaType,
                            "data": imageData.base64EncodedString(),
                        ],
                    ],
                    ["type": "text", "text": "Analyze this image and generate the prompts."],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 이미지 없이 텍스트만 보내는 요청 (프롬프트 개선 제안 등).
    static func buildTextRequest(apiKey: String, model: String, prompt: String,
                                 schema: [String: Any]) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [[
                "role": "user",
                "content": [["type": "text", "text": prompt]],
            ]],
        ]
        if !schema.isEmpty {
            // 구조화 출력은 output_config.format — assistant prefill은 400을 낸다
            body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 텍스트 응답의 본문만 꺼낸다 (JSON 해석은 호출한 쪽에서).
    static func parseTextResponse(status: Int, data: Data) throws -> String {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?
                .error.message ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw AnalyzerError.apiError(status: status, message: message)
        }
        let response = try JSONDecoder().decode(APIResponse.self, from: data)
        if response.stopReason == "refusal" {
            throw AnalyzerError.refusal(response.stopDetails?.explanation)
        }
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw AnalyzerError.emptyResponse
        }
        return text
    }

    /// 응답 파싱 (테스트 가능하도록 분리).
    static func parseResponse(status: Int, data: Data) throws -> PromptAnalysis {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?
                .error.message ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw AnalyzerError.apiError(status: status, message: message)
        }
        let response = try JSONDecoder().decode(APIResponse.self, from: data)
        if response.stopReason == "refusal" {
            throw AnalyzerError.refusal(response.stopDetails?.explanation)
        }
        guard let text = response.content.first(where: { $0.type == "text" })?.text,
              let jsonData = text.data(using: .utf8) else {
            throw AnalyzerError.emptyResponse
        }
        return try JSONDecoder().decode(PromptAnalysis.self, from: jsonData)
    }

    let apiKey: String
    let model: String

    init(apiKey: String, model: String = PromptAnalyzer.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    /// 텍스트 요청 1회 — 모델의 원문 응답을 돌려준다.
    func complete(prompt: String, schema: [String: Any]) async throws -> String {
        let request = try Self.buildTextRequest(apiKey: apiKey, model: model,
                                                prompt: prompt, schema: schema)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        return try Self.parseTextResponse(
            status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    func analyze(imageData: Data, mediaType: String) async throws -> PromptAnalysis {
        let request = try Self.buildRequest(apiKey: apiKey, model: model,
                                            imageData: imageData, mediaType: mediaType)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseResponse(status: status, data: data)
    }
}

// MARK: - API 응답 디코딩용 내부 타입

struct APIResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    struct StopDetails: Decodable {
        let explanation: String?
    }
    let content: [Block]
    let stopReason: String?
    let stopDetails: StopDetails?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }
}

struct APIErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let type: String
        let message: String
    }
    let error: Inner
}
