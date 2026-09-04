import XCTest
@testable import CaptureToPrompt

final class LLMRouterAnalyzerTests: XCTestCase {

    // MARK: - buildRequest

    func testBuildRequestSetsURLHeadersAndBody() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let request = try LLMRouterAnalyzer.buildRequest(
            baseURL: "http://localhost:3000", apiKey: "rk-test", model: "auto",
            imageData: imageData, mediaType: "image/jpeg")

        XCTAssertEqual(request.url?.absoluteString,
                       "http://localhost:3000/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "auto")

        // OpenAI 호환 구조화 출력: response_format json_schema + 기존 outputSchema 재사용
        let responseFormat = try XCTUnwrap(body?["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertNotNil(jsonSchema["schema"])

        // messages: system + user(content parts: image_url data URI, text)
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        let user = try XCTUnwrap(messages.last)
        XCTAssertEqual(user["role"] as? String, "user")
        let content = try XCTUnwrap(user["content"] as? [[String: Any]])
        let imagePart = try XCTUnwrap(content.first { $0["type"] as? String == "image_url" })
        let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String,
                       "data:image/jpeg;base64,\(imageData.base64EncodedString())")
        XCTAssertTrue(content.contains { $0["type"] as? String == "text" })
    }

    func testBuildRequestNormalizesTrailingSlash() throws {
        let request = try LLMRouterAnalyzer.buildRequest(
            baseURL: "http://localhost:3000/", apiKey: "rk", model: "auto",
            imageData: Data([1]), mediaType: "image/png")
        XCTAssertEqual(request.url?.absoluteString,
                       "http://localhost:3000/api/v1/chat/completions")
    }

    func testBuildRequestThrowsWithoutKey() {
        XCTAssertThrowsError(try LLMRouterAnalyzer.buildRequest(
            baseURL: "http://localhost:3000", apiKey: "", model: "auto",
            imageData: Data(), mediaType: "image/png")) { error in
            guard case AnalyzerError.missingRouterKey = error else {
                return XCTFail("expected missingRouterKey, got \(error)")
            }
        }
    }

    func testBuildRequestThrowsOnInvalidBaseURL() {
        XCTAssertThrowsError(try LLMRouterAnalyzer.buildRequest(
            baseURL: "", apiKey: "rk", model: "auto",
            imageData: Data(), mediaType: "image/png"))
    }

    // MARK: - parseResponse

    private let sampleAnalysisJSON = """
    {"prompt_en":"a cat","prompt_ko":"고양이","prompt_ja":"猫","breakdown":{"subject":"cat",\
    "style":"photo","composition":"close-up","lighting":"soft","color_palette":"warm",\
    "mood":"calm","medium":"photography","tags":["cat","photo"]}}
    """

    func testParseResponseSuccess() throws {
        let apiJSON = """
        {"id":"chatcmpl-1","choices":[{"index":0,"finish_reason":"stop",
         "message":{"role":"assistant","content":\(escapedJSONString(sampleAnalysisJSON))}}]}
        """.data(using: .utf8)!

        let analysis = try LLMRouterAnalyzer.parseResponse(status: 200, data: apiJSON)
        XCTAssertEqual(analysis.promptKo, "고양이")
        XCTAssertEqual(analysis.breakdown.tags, ["cat", "photo"])
    }

    func testParseResponseStripsMarkdownFences() throws {
        let fenced = "```json\n\(sampleAnalysisJSON)\n```"
        let apiJSON = """
        {"choices":[{"message":{"role":"assistant","content":\(escapedJSONString(fenced))}}]}
        """.data(using: .utf8)!

        let analysis = try LLMRouterAnalyzer.parseResponse(status: 200, data: apiJSON)
        XCTAssertEqual(analysis.promptJa, "猫")
    }

    func testParseResponseHTTPError() {
        let apiJSON = """
        {"error":{"message":"invalid or missing API key","type":"authentication_error"}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try LLMRouterAnalyzer.parseResponse(status: 401, data: apiJSON)) { error in
            guard case AnalyzerError.apiError(let status, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "invalid or missing API key")
        }
    }

    func testParseResponseEmptyChoices() {
        let apiJSON = #"{"choices":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try LLMRouterAnalyzer.parseResponse(status: 200, data: apiJSON)) { error in
            guard case AnalyzerError.emptyResponse = error else {
                return XCTFail("expected emptyResponse, got \(error)")
            }
        }
    }

    private func escapedJSONString(_ raw: String) -> String {
        let data = try! JSONEncoder().encode(raw)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - 텍스트 전용 요청 (프롬프트 개선 제안용)

    func testBuildTextRequestSendsPlainTextMessage() throws {
        let request = try LLMRouterAnalyzer.buildTextRequest(
            baseURL: "http://localhost:3000", apiKey: "k", model: "auto",
            prompt: "왜 거부됐나요?", schema: PromptRevisionAdvisor.outputSchema)

        XCTAssertEqual(request.url?.absoluteString,
                       "http://localhost:3000/api/v1/chat/completions")
        let body = try JSONSerialization.jsonObject(
            with: XCTUnwrap(request.httpBody)) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        // 이미지 없이 문자열 content 하나
        XCTAssertEqual(messages.last?["content"] as? String, "왜 거부됐나요?")
        XCTAssertNotNil(body?["response_format"])
    }

    func testParseTextResponseReturnsContent() throws {
        let json = Data(#"{"choices":[{"message":{"content":"{\"a\":1}"}}]}"#.utf8)
        XCTAssertEqual(try LLMRouterAnalyzer.parseTextResponse(status: 200, data: json),
                       #"{"a":1}"#)
    }

    /// router 응답도 산문이면 거절로 알린다.
    func testParseResponseTreatsProseAsRefusal() throws {
        let json = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "I cannot analyze this image."]]],
        ])
        XCTAssertThrowsError(try LLMRouterAnalyzer.parseResponse(status: 200, data: json)) { error in
            guard case AnalyzerError.refusal = error else {
                return XCTFail("expected refusal, got \(error)")
            }
        }
    }
}
