import Foundation

/// 4개 백엔드가 공유하는 분석 지시문 규칙.
/// 특히 **그림체(화풍) 재현** 규칙은 실측 PoC로 고른 것이다 (2026-09-03):
/// - 축 라벨 없이 두면 style이 "동양 무협 판타지 키 비주얼" 같은 장르 이름에 그쳐,
///   어떻게 그린 그림인지가 남지 않았다.
/// - 축을 지시하면 style은 충실해지지만 생성 프롬프트 본문 앞머리에는 화풍이 안 실린다.
///   이미지 생성 모델은 앞쪽 구절에 더 크게 반응하므로 본문도 화풍으로 열게 했다.
/// - 앞머리 지시만 주면 피사체 묘사가 짧아져, "줄이지 말라"는 균형 지시를 함께 둔다.
enum PromptGuidelines {

    static let styleRules = """
    Each prompt must OPEN with a short style clause (15-25 words) naming the drawing \
    style — line work, shading, color treatment, finish — and then continue with the \
    subject, composition, lighting and mood in full detail. Do not shorten the subject \
    description to make room for the style clause. \
    The "style" field, always written in English, must describe the drawing style along \
    five axes using these exact labels in this order, as one paragraph without \
    numbering: "Line work:", "Shading:", "Color:", "Rendering:", "Finish:". Keep it \
    under 700 characters. \
    The "medium" field, always written in English, states the production technique and \
    output format in one short phrase — not the software or brushes used. \
    Never name artists, studios, franchises or existing works in any field; describe how \
    the drawing looks instead. \
    Prompts must be plain descriptive text only — never append tool-specific parameter \
    flags such as --ar, --v, --style, --q, --chaos. If aspect ratio matters, describe it \
    in words (e.g. "vertical 2:3 portrait format").
    """

    /// 인물 포즈 규칙. PoC(2026-09-03) 결과 subject에 포즈를 몰아넣으면 1200자를 넘겨
    /// 인물 외형 묘사가 밀리고, subject를 목록 제목으로 쓰는 사이드바도 읽기 어려워졌다.
    /// 그래서 pose를 전용 필드로 분리했다.
    static let poseRules = """
    If the image contains one or more people or characters, the "pose" field, written in \
    English, must describe the figure's pose concretely: framing (how much of the body \
    is in frame), body orientation relative to the camera (front, three-quarter, \
    profile, from behind), head tilt and gaze direction, torso posture and weight \
    distribution, each arm and hand position, leg and foot placement, facial expression, \
    and whether the figure is mid-motion or still. With several figures, describe the \
    main one first and then the others briefly. If the image contains no person or \
    character, "pose" must be an empty string. Keep "subject" focused on who or what is \
    depicted — not the pose — and carry the same pose detail into the prompts as natural \
    sentences.
    """

    /// breakdown.pose 스키마 설명.
    static let poseFieldDescription = """
    Pose of the figure in English — framing, body orientation, head and gaze, torso and \
    weight, arms and hands, legs and feet, expression, motion. Empty string if the image \
    has no person or character.
    """

    /// breakdown.style 스키마 설명 (구조화 출력을 쓰는 백엔드용).
    static let styleFieldDescription = """
    Drawing style along five axes, in English, one paragraph, using these labels in \
    order: "Line work:", "Shading:", "Color:", "Rendering:", "Finish:". Under 700 \
    characters. No artist, studio or franchise names.
    """

    /// breakdown.medium 스키마 설명.
    static let mediumFieldDescription =
        "Production technique and output format in one short English phrase."
}
