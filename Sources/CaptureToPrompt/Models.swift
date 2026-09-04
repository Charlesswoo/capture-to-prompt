import Foundation

/// Claude가 이미지 한 장을 분석해 반환하는 구조화 결과.
struct PromptAnalysis: Codable, Equatable {
    var promptEn: String
    var promptKo: String
    var promptJa: String
    var breakdown: Breakdown

    struct Breakdown: Codable, Equatable {
        var subject: String
        /// 인물이 있을 때의 자세·시선·손발 위치. 인물이 없으면 빈 문자열.
        var pose: String
        var style: String
        var composition: String
        var lighting: String
        var colorPalette: String
        var mood: String
        var medium: String
        var tags: [String]

        enum CodingKeys: String, CodingKey {
            case subject, pose, style, composition, lighting, mood, medium, tags
            case colorPalette = "color_palette"
        }

        init(subject: String, pose: String = "", style: String, composition: String,
             lighting: String, colorPalette: String, mood: String, medium: String,
             tags: [String]) {
            self.subject = subject
            self.pose = pose
            self.style = style
            self.composition = composition
            self.lighting = lighting
            self.colorPalette = colorPalette
            self.mood = mood
            self.medium = medium
            self.tags = tags
        }

        /// pose는 나중에 추가된 필드라 예전 history.json에는 없다 — 없으면 빈 문자열.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            subject = try c.decode(String.self, forKey: .subject)
            pose = try c.decodeIfPresent(String.self, forKey: .pose) ?? ""
            style = try c.decode(String.self, forKey: .style)
            composition = try c.decode(String.self, forKey: .composition)
            lighting = try c.decode(String.self, forKey: .lighting)
            colorPalette = try c.decode(String.self, forKey: .colorPalette)
            mood = try c.decode(String.self, forKey: .mood)
            medium = try c.decode(String.self, forKey: .medium)
            tags = try c.decode([String].self, forKey: .tags)
        }
    }

    enum CodingKeys: String, CodingKey {
        case promptEn = "prompt_en"
        case promptKo = "prompt_ko"
        case promptJa = "prompt_ja"
        case breakdown
    }

    /// 사용자가 수정할 수 있는 프롬프트 언어.
    enum PromptLanguage {
        case korean, english, japanese
    }

    /// 지정 언어의 프롬프트를 돌려준다 (이미지 생성에 쓸 언어 선택용).
    func prompt(for language: PromptLanguage) -> String {
        switch language {
        case .korean: return promptKo
        case .english: return promptEn
        case .japanese: return promptJa
        }
    }

    /// 지정 언어의 프롬프트만 교체한 사본을 돌려준다.
    func updating(prompt: String, for language: PromptLanguage) -> PromptAnalysis {
        var copy = self
        switch language {
        case .korean: copy.promptKo = prompt
        case .english: copy.promptEn = prompt
        case .japanese: copy.promptJa = prompt
        }
        return copy
    }

    /// JSON 탭에 표시할 정렬된 pretty JSON.
    func prettyJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 이미지 생성에 쓰는 기본 프롬프트 언어.
/// 실측(2026-09-04): 같은 프롬프트라도 한국어로 넘기면 gpt-image 계열이 색감·구도 지시를
/// 놓치고 전혀 다른 톤을 만든다. 영어판은 원본 톤을 그대로 재현했다.
let defaultGenerationLanguage: PromptAnalysis.PromptLanguage = .english

/// 정책 거부된 프롬프트의 진단 결과 — 문제 구절과 고쳐 쓴 프롬프트.
struct PromptRevision: Codable, Equatable {
    /// 왜 거부됐는지 한 줄 요약 (한국어).
    var summary: String
    /// 문제로 지목된 구절들 (원인을 특정하지 못하면 비어 있을 수 있다).
    var issues: [Issue]
    /// 원문과 같은 언어로 고쳐 쓴 전체 프롬프트.
    var revisedPrompt: String

    struct Issue: Codable, Equatable, Identifiable {
        var phrase: String       // 프롬프트에서 그대로 따온 문제 구절
        var reason: String       // 왜 위험한지 (한국어)
        var suggestion: String   // 대체 표현
        var id: String { phrase + reason }
    }

    enum CodingKeys: String, CodingKey {
        case summary, issues
        case revisedPrompt = "revised_prompt"
    }
}

/// 히스토리 한 항목. 이미지는 별도 파일로 저장하고 파일명만 갖는다.
struct HistoryItem: Codable, Equatable, Identifiable {
    var id: UUID
    var createdAt: Date
    var imageFileName: String
    var analysis: PromptAnalysis
    /// 이 항목에서 생성한 이미지들의 파일명(오래된 순). 생성할 때마다 누적된다.
    var generatedImageFileNames: [String]

    init(id: UUID, createdAt: Date, imageFileName: String, analysis: PromptAnalysis,
         generatedImageFileNames: [String] = []) {
        self.id = id
        self.createdAt = createdAt
        self.imageFileName = imageFileName
        self.analysis = analysis
        self.generatedImageFileNames = generatedImageFileNames
    }

    /// 구버전 history.json에는 generatedImageFileNames가 없으므로 빈 배열로 읽는다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        imageFileName = try container.decode(String.self, forKey: .imageFileName)
        analysis = try container.decode(PromptAnalysis.self, forKey: .analysis)
        generatedImageFileNames =
            try container.decodeIfPresent([String].self, forKey: .generatedImageFileNames) ?? []
    }
}

extension AnalyzerError {
    /// 모델이 JSON 대신 산문을 돌려줬을 때의 오류.
    /// 대개 "이 이미지는 분석해 드릴 수 없습니다" 같은 거절이므로, 원문을 그대로 실어
    /// 사용자가 이유를 읽고 다음 행동을 정할 수 있게 한다.
    /// JSON 형태이긴 한데 깨진 경우는 기존대로 해석 실패로 남긴다.
    static func fromNonJSONResponse(_ text: String) -> AnalyzerError {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else {
            return .refusal(trimmed.isEmpty ? nil : trimmed)
        }
        return .apiError(status: 0, message: "결과 JSON 해석 실패: \(trimmed.prefix(300))")
    }

    /// 응답 코드·문구가 안전/콘텐츠 정책 거부로 보이는지.
    /// (OpenAI는 gpt-image 계열 `moderation_blocked`, DALL·E 계열 `content_policy_violation`,
    ///  codex CLI는 코드 없이 모델의 거부 문장만 남기므로 문구도 함께 본다)
    static func looksLikeContentPolicy(code: String?, message: String?) -> Bool {
        let codes = ["moderation_blocked", "content_policy_violation", "content_filter"]
        if let code, codes.contains(code.lowercased()) { return true }
        guard let message = message?.lowercased() else { return false }
        let phrases = ["safety system", "content policy", "content_policy",
                       "usage policies", "safety policies", "moderation",
                       "violates the content", "not allowed by our safety"]
        return phrases.contains { message.contains($0) }
    }
}

enum AnalyzerError: LocalizedError {
    case missingAPIKey
    case missingImageGenKey
    case invalidImage
    case refusal(String?)
    /// 이미지 생성이 안전·콘텐츠 정책에 걸려 거부된 경우.
    case contentPolicy(String?)
    case apiError(status: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API 키가 없습니다. 설정에서 Anthropic API 키를 입력하거나 ANTHROPIC_API_KEY 환경변수를 지정하세요."
        case .missingImageGenKey:
            return "이미지 생성 API 키가 없습니다. 설정에서 키를 입력하거나 OPENAI_API_KEY 환경변수를 지정하세요."
        case .invalidImage:
            return "이미지를 읽을 수 없습니다. PNG/JPEG/WebP/GIF 형식인지 확인하세요."
        case .refusal(let reason):
            return "모델이 이 이미지 분석을 거절했습니다." + (reason.map { " (\($0))" } ?? "")
        case .contentPolicy(let detail):
            // 같은 프롬프트로 재시도해도 결과가 같으므로 표현을 바꾸도록 안내한다
            return "프롬프트가 이미지 생성 정책에 걸려 거부됐습니다. 같은 문장으로 다시 시도해도 "
                + "결과는 같으니, 프롬프트를 수정한 뒤 다시 생성하세요."
                + (detail.map { "\n원문: \($0)" } ?? "")
        case .apiError(let status, let message):
            return "API 오류 (\(status)): \(message)"
        case .emptyResponse:
            return "API 응답에 결과 텍스트가 없습니다."
        }
    }
}
