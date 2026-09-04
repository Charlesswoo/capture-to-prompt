import Foundation

/// 이미지 생성이 정책으로 거부됐을 때, 프롬프트의 **어느 부분**이 문제였는지 짚고
/// 고친 프롬프트를 제안한다. 분석에 쓰는 백엔드를 그대로 재사용한다(텍스트 요청 1회).
enum PromptRevisionAdvisor {

    /// 모델에 보낼 요청문. 거부 원문을 알면 함께 넘겨 근거를 좁힌다.
    static func prompt(originalPrompt: String, rejection: String?) -> String {
        let rejectionBlock = rejection.map {
            "\nThe provider rejected it with this message:\n\"\"\"\n\($0)\n\"\"\"\n"
        } ?? "\nThe provider gave no specific reason.\n"

        return """
        You are helping a user whose AI image-generation prompt was rejected by the \
        provider's safety/content policy. Your job is diagnostic: identify which specific \
        parts of the prompt most likely triggered the rejection, and rewrite it so it can \
        pass while keeping the same visual intent.

        The rejected prompt:
        \"\"\"
        \(originalPrompt)
        \"\"\"
        \(rejectionBlock)
        Common triggers to consider: named real people (living or dead) and celebrities, \
        named living artists' styles, copyrighted or trademarked characters and brands, \
        violence, gore, weapons aimed at people, sexual or suggestive content, minors in \
        any risky context, hate symbols, and realistic depictions of public figures.

        Respond with ONLY a raw JSON object (no markdown fences, no commentary) with \
        exactly these keys:
        - summary: one sentence in Korean saying why it was most likely rejected.
        - issues: an array (may be empty) of objects with keys phrase, reason, suggestion. \
        phrase must be copied verbatim from the prompt above. reason is in Korean and \
        explains why that phrase is risky. suggestion is a safer replacement written in \
        the same language as the prompt.
        - revised_prompt: the full rewritten prompt, in the SAME LANGUAGE as the original, \
        preserving the visual intent (subject, composition, lighting, mood) while removing \
        every risky element. Plain descriptive text only, no tool flags such as --ar or --v.

        If you cannot pinpoint a specific phrase, return an empty issues array but still \
        provide a safer revised_prompt.
        """
    }

    /// 구조화 출력을 지원하는 백엔드(API·codex)를 위한 JSON 스키마.
    static var outputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "summary": ["type": "string"],
                "issues": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "phrase": ["type": "string"],
                            "reason": ["type": "string"],
                            "suggestion": ["type": "string"],
                        ],
                        "required": ["phrase", "reason", "suggestion"],
                        "additionalProperties": false,
                    ],
                ],
                "revised_prompt": ["type": "string"],
            ],
            "required": ["summary", "issues", "revised_prompt"],
            "additionalProperties": false,
        ]
    }

    /// 모델 응답 → PromptRevision. 펜스·잡담이 섞여도 JSON 본문만 취한다.
    static func parse(_ text: String) throws -> PromptRevision {
        let json = ClaudeCLIAnalyzer.stripFences(text)
        guard let data = json.data(using: .utf8), json.hasPrefix("{") else {
            throw AnalyzerError.apiError(
                status: 0, message: "개선안 응답을 해석하지 못했습니다: \(text.prefix(300))")
        }
        let revision: PromptRevision
        do {
            revision = try JSONDecoder().decode(PromptRevision.self, from: data)
        } catch {
            throw AnalyzerError.apiError(
                status: 0, message: "개선안 JSON 해석 실패: \(json.prefix(300))")
        }
        guard !revision.revisedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyzerError.apiError(status: 0, message: "개선안에 수정된 프롬프트가 없습니다.")
        }
        return revision
    }
}
