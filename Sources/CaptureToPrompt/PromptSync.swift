import Foundation

/// 한 언어의 프롬프트를 고치면 나머지 두 언어를 같은 내용으로 맞춘다.
///
/// 세 프롬프트를 각각 독립 작성하던 시절에는 언어마다 내용이 어긋났고,
/// 이미지 생성은 영어만 쓰기 때문에 **한국어로 고친 내용이 생성에 반영되지 않았다**.
/// 편집한 언어는 그대로 두고, 나머지만 그 내용에 맞춰 다시 쓴다.
enum PromptSync {

    static func languageName(_ language: PromptAnalysis.PromptLanguage) -> String {
        switch language {
        case .korean: return "Korean"
        case .english: return "English"
        case .japanese: return "Japanese"
        }
    }

    static func key(_ language: PromptAnalysis.PromptLanguage) -> String {
        switch language {
        case .korean: return "prompt_ko"
        case .english: return "prompt_en"
        case .japanese: return "prompt_ja"
        }
    }

    /// 동기화 요청문.
    static func prompt(edited text: String,
                       language: PromptAnalysis.PromptLanguage) -> String {
        let source = languageName(language)
        return """
        A user edited an AI image-generation prompt written in \(source). Rewrite it in the \
        other two languages so that all three carry exactly the same content — same subject, \
        pose, composition, lighting, color palette, style and mood, with nothing added, \
        dropped or reinterpreted. This is a faithful rendering, not a new prompt.

        The edited \(source) prompt:
        \"\"\"
        \(text)
        \"\"\"

        Keep the \(source) version verbatim as given. Each version must read as a natural, \
        self-contained image-generation prompt in its own language — not a literal word-for-word \
        transliteration — while preserving every detail.

        Respond with ONLY a raw JSON object (no markdown fences, no commentary) with exactly \
        these keys: prompt_en (English), prompt_ko (Korean), prompt_ja (Japanese). \
        Plain descriptive text only — never append tool-specific parameter flags such as \
        --ar, --v, --style.
        """
    }

    /// 구조화 출력을 지원하는 백엔드용 스키마.
    static var outputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "prompt_en": ["type": "string"],
                "prompt_ko": ["type": "string"],
                "prompt_ja": ["type": "string"],
            ],
            "required": ["prompt_en", "prompt_ko", "prompt_ja"],
            "additionalProperties": false,
        ]
    }

    /// 모델 응답을 분석 결과에 반영한다.
    /// 사용자가 직접 쓴 언어는 응답으로 덮어쓰지 않는다.
    static func apply(_ text: String, to analysis: PromptAnalysis,
                      edited language: PromptAnalysis.PromptLanguage) throws -> PromptAnalysis {
        let json = ClaudeCLIAnalyzer.stripFences(text)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalyzerError.apiError(
                status: 0, message: "다른 언어 프롬프트를 해석하지 못했습니다: \(text.prefix(200))")
        }
        var updated = analysis
        for target in [PromptAnalysis.PromptLanguage.korean, .english, .japanese]
        where target != language {
            guard let value = object[key(target)] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AnalyzerError.apiError(
                    status: 0,
                    message: "\(languageName(target)) 프롬프트가 응답에 없습니다.")
            }
            updated = updated.updating(prompt: value, for: target)
        }
        return updated
    }
}
