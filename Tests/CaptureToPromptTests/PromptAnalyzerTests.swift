import XCTest
@testable import CaptureToPrompt

final class PromptAnalyzerTests: XCTestCase {

    // MARK: - buildRequest

    func testBuildRequestSetsHeadersAndBody() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let request = try PromptAnalyzer.buildRequest(
            apiKey: "sk-test", model: "claude-opus-4-8",
            imageData: imageData, mediaType: "image/png")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "claude-opus-4-8")
        XCTAssertNotNil(body?["output_config"])

        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let imageBlock = try XCTUnwrap(content.first { $0["type"] as? String == "image" })
        let source = try XCTUnwrap(imageBlock["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())
    }

    func testBuildRequestThrowsWithoutAPIKey() {
        XCTAssertThrowsError(try PromptAnalyzer.buildRequest(
            apiKey: "", model: "m", imageData: Data(), mediaType: "image/png")) { error in
            guard case AnalyzerError.missingAPIKey = error else {
                return XCTFail("expected missingAPIKey, got \(error)")
            }
        }
    }

    // MARK: - parseResponse

    private let sampleAnalysisJSON = """
    {"prompt_en":"a cat","prompt_ko":"고양이","prompt_ja":"猫","breakdown":{"subject":"cat",\
    "style":"photo","composition":"close-up","lighting":"soft","color_palette":"warm",\
    "mood":"calm","medium":"photography","tags":["cat","photo"]}}
    """

    func testParseResponseSuccess() throws {
        let apiJSON = """
        {"content":[{"type":"text","text":\(escapedJSONString(sampleAnalysisJSON))}],
         "stop_reason":"end_turn"}
        """.data(using: .utf8)!

        let analysis = try PromptAnalyzer.parseResponse(status: 200, data: apiJSON)
        XCTAssertEqual(analysis.promptKo, "고양이")
        XCTAssertEqual(analysis.breakdown.colorPalette, "warm")
        XCTAssertEqual(analysis.breakdown.tags, ["cat", "photo"])
    }

    func testParseResponseRefusal() {
        let apiJSON = """
        {"content":[],"stop_reason":"refusal","stop_details":{"explanation":"policy"}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try PromptAnalyzer.parseResponse(status: 200, data: apiJSON)) { error in
            guard case AnalyzerError.refusal(let reason) = error else {
                return XCTFail("expected refusal, got \(error)")
            }
            XCTAssertEqual(reason, "policy")
        }
    }

    func testParseResponseHTTPError() {
        let apiJSON = """
        {"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try PromptAnalyzer.parseResponse(status: 401, data: apiJSON)) { error in
            guard case AnalyzerError.apiError(let status, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "invalid x-api-key")
        }
    }

    // MARK: - PromptAnalysis codable

    func testPromptAnalysisRoundTrip() throws {
        let analysis = try JSONDecoder().decode(
            PromptAnalysis.self, from: sampleAnalysisJSON.data(using: .utf8)!)
        let pretty = analysis.prettyJSON()
        XCTAssertTrue(pretty.contains("\"prompt_ko\""))
        XCTAssertTrue(pretty.contains("\"color_palette\""))

        let decoded = try JSONDecoder().decode(PromptAnalysis.self, from: pretty.data(using: .utf8)!)
        XCTAssertEqual(decoded, analysis)
    }

    private func escapedJSONString(_ raw: String) -> String {
        let data = try! JSONEncoder().encode(raw)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - 텍스트 전용 요청 (프롬프트 개선 제안용)

    func testBuildTextRequestSendsNoImageAndUsesGivenSchema() throws {
        let request = try PromptAnalyzer.buildTextRequest(
            apiKey: "sk-test", model: "claude-opus-4-8", prompt: "왜 거부됐나요?",
            schema: PromptRevisionAdvisor.outputSchema)

        XCTAssertEqual(request.url, PromptAnalyzer.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try JSONSerialization.jsonObject(
            with: XCTUnwrap(request.httpBody)) as? [String: Any]
        let messages = try XCTUnwrap(body?["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        // 이미지 블록이 없어야 한다
        XCTAssertFalse(content.contains { $0["type"] as? String == "image" })
        XCTAssertEqual(content.first?["text"] as? String, "왜 거부됐나요?")
        // 구조화 출력은 output_config.format (assistant prefill 금지)
        let outputConfig = try XCTUnwrap(body?["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    func testBuildTextRequestThrowsWithoutKey() {
        XCTAssertThrowsError(try PromptAnalyzer.buildTextRequest(
            apiKey: "", model: "m", prompt: "p", schema: [:]))
    }

    func testParseTextResponseReturnsRawText() throws {
        let json = Data(#"{"content":[{"type":"text","text":"{\"a\":1}"}],"stop_reason":"end_turn"}"#.utf8)
        let text = try PromptAnalyzer.parseTextResponse(status: 200, data: json)
        XCTAssertEqual(text, #"{"a":1}"#)
    }

    // MARK: - pose 필드 (기존 히스토리 호환)

    /// pose가 없는 예전 JSON도 그대로 읽혀야 한다 (빈 문자열로).
    func testBreakdownDecodesLegacyJSONWithoutPose() throws {
        let json = Data(#"""
        {"prompt_en":"a","prompt_ko":"b","prompt_ja":"c","breakdown":{"subject":"cat",
        "style":"photo","composition":"close-up","lighting":"soft","color_palette":"warm",
        "mood":"calm","medium":"photography","tags":["cat"]}}
        """#.utf8)

        let analysis = try JSONDecoder().decode(PromptAnalysis.self, from: json)
        XCTAssertEqual(analysis.breakdown.pose, "")
        XCTAssertEqual(analysis.breakdown.subject, "cat")
    }

    func testBreakdownRoundTripsPose() throws {
        let json = Data(#"""
        {"prompt_en":"a","prompt_ko":"b","prompt_ja":"c","breakdown":{"subject":"archer",
        "pose":"three-quarter stance, bow drawn","style":"webtoon","composition":"vertical",
        "lighting":"rim","color_palette":"blue","mood":"heroic","medium":"digital","tags":["archer"]}}
        """#.utf8)

        let analysis = try JSONDecoder().decode(PromptAnalysis.self, from: json)
        XCTAssertEqual(analysis.breakdown.pose, "three-quarter stance, bow drawn")

        let encoded = try JSONEncoder().encode(analysis)
        let again = try JSONDecoder().decode(PromptAnalysis.self, from: encoded)
        XCTAssertEqual(again.breakdown.pose, "three-quarter stance, bow drawn")
    }
}
