import Foundation

/// OpenAI 호환 Images API(`POST {base}/images/generations`)로 프롬프트 → 이미지 생성.
/// Base URL만 바꾸면 OpenAI 직결이든 호환 프록시든 동일하게 동작한다.
struct ImageGenerator {
    static let defaultBaseURL = "https://api.openai.com/v1"
    /// 기본 모델. 공식 문서(2026-09-08 출시) 기준 gpt-image-2보다 품질이 높고
    /// 지연이 절반이라 기본값으로 둔다.
    static let defaultModel = "gpt-image-2.5-flare"

    /// 문서로 ID를 확인한 모델들 — 목록 조회가 안 되는 환경에서도 고를 수 있게.
    /// (developers.openai.com/api/docs/models, 2026-09-17 확인)
    static let knownModels = [
        "gpt-image-2.5-flare",      // 기본. 빠르고 품질 높음
        "gpt-image-2.5-sunburst",   // 편집 정밀도 우선, 생성이 느림
        "gpt-image-2",
    ]

    /// 조회 결과와 알려진 목록을 합친다 (중복 없이, 알려진 것 먼저).
    static func mergedModels(fetched: [String]) -> [String] {
        var seen = Set<String>()
        return (knownModels + fetched).filter { seen.insert($0).inserted }
    }

    /// 오류 응답 — 정책 거부 판별에 code가 필요해 별도로 둔다 (message만 있는 프록시도 있다).
    struct ImageErrorEnvelope: Decodable {
        struct Inner: Decodable {
            let message: String?
            let code: String?
        }
        let error: Inner
    }

    /// 응답이 b64_json(기본) 또는 url(일부 모델/프록시) 두 형태라 모두 다룬다.
    enum GeneratedImage {
        case data(Data)
        case url(URL)
    }

    /// 요청 구성 (테스트 가능하도록 분리).
    static func buildRequest(baseURL: String, apiKey: String, model: String,
                             prompt: String, size: String? = nil) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingImageGenKey }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/images/generations"), url.scheme != nil else {
            throw AnalyzerError.apiError(status: 0, message: "잘못된 이미지 생성 Base URL: \(baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // response_format은 모델마다 수락 여부가 갈려서(gpt-image 계열은 거부) 보내지 않는다
        var body: [String: Any] = ["model": model, "prompt": prompt, "n": 1]
        if let size { body["size"] = size }   // 없으면 auto — 대체로 맞지만 가끔 크게 어긋난다
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 변형 생성 요청 구성 — `POST {base}/images/edits` (multipart/form-data).
    /// 참조 이미지는 `image[]` 필드로 보낸다 (공식 문서 기준, 여러 장도 같은 필드명).
    static func buildEditRequest(baseURL: String, apiKey: String, model: String,
                                 prompt: String, referenceImage: Data,
                                 size: String? = nil) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingImageGenKey }
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(trimmed)/images/edits"), url.scheme != nil else {
            throw AnalyzerError.apiError(status: 0, message: "잘못된 이미지 생성 Base URL: \(baseURL)")
        }

        let boundary = "c2p-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        appendField("model", model)
        appendField("prompt", prompt)
        appendField("n", "1")
        if let size { appendField("size", size) }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"image[]\"; filename=\"reference.png\"\r\n".utf8))
        body.append(Data("Content-Type: image/png\r\n\r\n".utf8))
        body.append(referenceImage)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    /// 응답 파싱 (테스트 가능하도록 분리).
    static func parseResponse(status: Int, data: Data) throws -> GeneratedImage {
        guard (200..<300).contains(status) else {
            let envelope = try? JSONDecoder().decode(ImageErrorEnvelope.self, from: data)
            let message = envelope?.error.message ?? String(data: data, encoding: .utf8) ?? "unknown"
            if AnalyzerError.looksLikeContentPolicy(code: envelope?.error.code, message: message) {
                throw AnalyzerError.contentPolicy(message)
            }
            throw AnalyzerError.apiError(status: status, message: message)
        }
        struct Response: Decodable {
            struct Item: Decodable {
                let b64Json: String?
                let url: String?
                enum CodingKeys: String, CodingKey {
                    case b64Json = "b64_json"
                    case url
                }
            }
            let data: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let item = response.data.first else { throw AnalyzerError.emptyResponse }
        if let b64 = item.b64Json, let imageData = Data(base64Encoded: b64) {
            return .data(imageData)
        }
        if let urlString = item.url, let url = URL(string: urlString) {
            return .url(url)
        }
        throw AnalyzerError.emptyResponse
    }

    // MARK: - 출력 크기

    /// 원본 화면비를 유지하는 생성 크기 ("1536x1408").
    ///
    /// 실측(2026-09-09, 8쌍 평균 오차): size 미지정(auto) 6.8% / 표준 3종 매핑 10.0% /
    /// 원본 비율 그대로 0.5%. **표준 3종은 auto보다 나쁘다** — auto가 대체로 잘
    /// 맞히는데 세 칸에 욱여넣으면 맞던 것까지 틀어지기 때문. 그래서 custom을 쓴다.
    ///
    /// 모델 제약: 두 변 모두 16의 배수, 종횡비 1:3~3:1, 최대 변 3840, 총 픽셀 8,294,400.
    static func outputSize(matching source: String?) -> String? {
        guard let source, let x = source.firstIndex(of: "x"),
              let sw = Int(source[source.startIndex..<x]),
              let sh = Int(source[source.index(after: x)...]),
              sw > 0, sh > 0 else { return nil }

        let ratio = min(max(Double(sw) / Double(sh), 1.0 / 3.0), 3.0)   // 1:3~3:1로 당긴다
        // 장변 1536 기준 — 표준 크기대와 같은 급이면서 총 픽셀 상한에 여유가 있다
        var w = ratio >= 1 ? 1536.0 : 1536.0 * ratio
        var h = ratio >= 1 ? 1536.0 / ratio : 1536.0
        let longest = max(w, h)
        if longest > 3840 { w *= 3840 / longest; h *= 3840 / longest }
        if w * h > 8_294_400 {
            let scale = (8_294_400 / (w * h)).squareRoot()
            w *= scale; h *= scale
        }
        // 16의 배수로 맞추되 0이 되지 않게
        let rw = max(16, (Int(w.rounded()) / 16) * 16)
        let rh = max(16, (Int(h.rounded()) / 16) * 16)
        return "\(rw)x\(rh)"
    }

    // MARK: - 모델 목록

    /// 이미지 모델 접두사 — OpenAI 호환 API가 온갖 모델을 함께 돌려주므로 걸러낸다.
    private static let imageModelPrefixes = ["gpt-image", "dall-e"]

    static func modelsRequest(baseURL: String, apiKey: String) -> URLRequest {
        var request = URLRequest(
            url: URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                     + "/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func parseModels(_ data: Data) throws -> [String] {
        struct Payload: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AnalyzerError.apiError(status: 0, message: "모델 목록을 해석하지 못했습니다.")
        }
        return payload.data.map(\.id)
            .filter { id in imageModelPrefixes.contains { id.hasPrefix($0) } }
            .sorted()
    }

    /// 키로 쓸 수 있는 이미지 모델을 조회한다.
    /// 새 모델(gpt-image-2.5 등)이 나와도 앱에 ID를 박아둘 필요가 없다.
    static func availableModels(baseURL: String, apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AnalyzerError.missingImageGenKey }
        let (data, response) = try await URLSession.shared
            .data(for: modelsRequest(baseURL: baseURL, apiKey: apiKey))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AnalyzerError.apiError(status: status, message: "모델 목록을 가져오지 못했습니다.")
        }
        return try parseModels(data)
    }

    let baseURL: String
    let apiKey: String
    let model: String

    init(baseURL: String = ImageGenerator.defaultBaseURL,
         apiKey: String,
         model: String = ImageGenerator.defaultModel) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    /// 프롬프트로 이미지를 생성해 바이트로 반환한다 (url 응답이면 내려받는다).
    /// referenceImage를 주면 그 이미지를 바탕으로 변형(images/edits)한다.
    /// - sourceSize: 원본 픽셀 크기("1024x1536"). 주면 그 화면비를 유지해 생성한다.
    func generate(prompt: String, referenceImage: Data? = nil,
                  sourceSize: String? = nil) async throws -> Data {
        let size = Self.outputSize(matching: sourceSize)
        let request: URLRequest
        if let referenceImage {
            request = try Self.buildEditRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                                prompt: prompt, referenceImage: referenceImage,
                                                size: size)
        } else {
            request = try Self.buildRequest(baseURL: baseURL, apiKey: apiKey,
                                            model: model, prompt: prompt, size: size)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch try Self.parseResponse(status: status, data: data) {
        case .data(let imageData):
            return imageData
        case .url(let url):
            let (downloaded, _) = try await session.data(from: url)
            return downloaded
        }
    }
}
