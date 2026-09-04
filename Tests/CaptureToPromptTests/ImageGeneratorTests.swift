import XCTest
@testable import CaptureToPrompt

final class ImageGeneratorTests: XCTestCase {

    // MARK: - buildRequest

    func testBuildRequestSetsURLHeadersAndBody() throws {
        let request = try ImageGenerator.buildRequest(
            baseURL: "https://api.openai.com/v1", apiKey: "sk-img", model: "gpt-image-2",
            prompt: "a serene lake at dawn")

        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.openai.com/v1/images/generations")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-img")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "gpt-image-2")
        XCTAssertEqual(body?["prompt"] as? String, "a serene lake at dawn")
        XCTAssertEqual(body?["n"] as? Int, 1)
    }

    func testBuildRequestNormalizesTrailingSlash() throws {
        let request = try ImageGenerator.buildRequest(
            baseURL: "http://localhost:3000/api/v1/", apiKey: "k", model: "m", prompt: "p")
        XCTAssertEqual(request.url?.absoluteString,
                       "http://localhost:3000/api/v1/images/generations")
    }

    func testBuildRequestThrowsWithoutKey() {
        XCTAssertThrowsError(try ImageGenerator.buildRequest(
            baseURL: "https://api.openai.com/v1", apiKey: "", model: "m", prompt: "p")) { error in
            guard case AnalyzerError.missingImageGenKey = error else {
                return XCTFail("expected missingImageGenKey, got \(error)")
            }
        }
    }

    // MARK: - parseResponse

    func testParseResponseB64JSON() throws {
        let pixel = Data([0x89, 0x50, 0x4E, 0x47])
        let apiJSON = """
        {"created":1,"data":[{"b64_json":"\(pixel.base64EncodedString())"}]}
        """.data(using: .utf8)!

        let result = try ImageGenerator.parseResponse(status: 200, data: apiJSON)
        guard case .data(let imageData) = result else {
            return XCTFail("expected .data, got \(result)")
        }
        XCTAssertEqual(imageData, pixel)
    }

    func testParseResponseURLVariant() throws {
        let apiJSON = """
        {"created":1,"data":[{"url":"https://cdn.example.com/img.png"}]}
        """.data(using: .utf8)!

        let result = try ImageGenerator.parseResponse(status: 200, data: apiJSON)
        guard case .url(let url) = result else {
            return XCTFail("expected .url, got \(result)")
        }
        XCTAssertEqual(url.absoluteString, "https://cdn.example.com/img.png")
    }

    func testParseResponseHTTPError() {
        let apiJSON = """
        {"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 401, data: apiJSON)) { error in
            guard case AnalyzerError.apiError(let status, let message) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(message.contains("Incorrect API key"))
        }
    }

    func testParseResponseEmptyDataThrows() {
        let apiJSON = #"{"created":1,"data":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 200, data: apiJSON)) { error in
            guard case AnalyzerError.emptyResponse = error else {
                return XCTFail("expected emptyResponse, got \(error)")
            }
        }
    }

    // MARK: - 변형 생성 (POST /images/edits, multipart)

    func testBuildEditRequestUsesMultipartEditsEndpoint() throws {
        let request = try ImageGenerator.buildEditRequest(
            baseURL: "https://api.openai.com/v1", apiKey: "sk-img", model: "gpt-image-2",
            prompt: "make it night", referenceImage: Data([0x89, 0x50, 0x4E, 0x47]))

        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-img")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try XCTUnwrap(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains(#"name="image[]""#))
        XCTAssertTrue(text.contains(#"name="prompt""#))
        XCTAssertTrue(text.contains("make it night"))
        XCTAssertTrue(text.contains(#"name="model""#))
        XCTAssertTrue(text.contains("gpt-image-2"))
        // 본문이 boundary로 정확히 닫혀야 한다
        let boundary = contentType.replacingOccurrences(
            of: "multipart/form-data; boundary=", with: "")
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
    }

    func testBuildEditRequestThrowsWithoutKey() {
        XCTAssertThrowsError(try ImageGenerator.buildEditRequest(
            baseURL: "https://api.openai.com/v1", apiKey: "", model: "m",
            prompt: "p", referenceImage: Data([1]))) { error in
            guard case AnalyzerError.missingImageGenKey = error else {
                return XCTFail("expected missingImageGenKey, got \(error)")
            }
        }
    }

    // MARK: - 정책 거부 안내

    /// gpt-image 계열: code = moderation_blocked
    func testParseResponseDetectsModerationBlocked() throws {
        let json = Data(#"""
        {"error":{"code":"moderation_blocked","message":"Your request was rejected as a result of our safety system."}}
        """#.utf8)

        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 400, data: json)) { error in
            guard case AnalyzerError.contentPolicy(let detail) = error else {
                return XCTFail("expected contentPolicy, got \(error)")
            }
            XCTAssertEqual(detail, "Your request was rejected as a result of our safety system.")
            let text = try? XCTUnwrap(error.localizedDescription)
            // 원인과 다음 행동(프롬프트 수정)이 한국어로 안내돼야 한다
            XCTAssertTrue(text?.contains("정책") == true)
            XCTAssertTrue(text?.contains("프롬프트") == true)
        }
    }

    /// DALL·E 계열: code = content_policy_violation
    func testParseResponseDetectsContentPolicyViolation() throws {
        let json = Data(#"""
        {"error":{"code":"content_policy_violation","message":"blocked"}}
        """#.utf8)
        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 400, data: json)) { error in
            guard case AnalyzerError.contentPolicy = error else {
                return XCTFail("expected contentPolicy, got \(error)")
            }
        }
    }

    /// code가 없어도 안전 시스템 문구면 정책 거부로 본다.
    func testParseResponseDetectsSafetySystemMessageWithoutCode() throws {
        let json = Data(#"""
        {"error":{"message":"Your input may contain content that is not allowed by our safety system."}}
        """#.utf8)
        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 400, data: json)) { error in
            guard case AnalyzerError.contentPolicy = error else {
                return XCTFail("expected contentPolicy, got \(error)")
            }
        }
    }

    /// 정책과 무관한 오류는 기존처럼 apiError로 남는다.
    func testParseResponseKeepsOrdinaryErrorsAsAPIError() throws {
        let json = Data(#"{"error":{"code":"rate_limit_exceeded","message":"slow down"}}"#.utf8)
        XCTAssertThrowsError(try ImageGenerator.parseResponse(status: 429, data: json)) { error in
            guard case AnalyzerError.apiError(let status, _) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(status, 429)
        }
    }
}
