import Foundation

/// 4개 백엔드가 공유하는 분석 지시문 규칙.
/// 특히 **그림체(화풍) 재현** 규칙은 실측 PoC로 고른 것이다 (2026-09-03):
/// - 축 라벨 없이 두면 style이 "동양 무협 판타지 키 비주얼" 같은 장르 이름에 그쳐,
///   어떻게 그린 그림인지가 남지 않았다.
/// - 축을 지시하면 style은 충실해지지만 생성 프롬프트 본문 앞머리에는 화풍이 안 실린다.
///   이미지 생성 모델은 앞쪽 구절에 더 크게 반응하므로 본문도 화풍으로 열게 했다.
/// - 앞머리 지시만 주면 피사체 묘사가 짧아져, "줄이지 말라"는 균형 지시를 함께 둔다.
enum PromptGuidelines {

    /// 핵심 3가지. prompt_en이 1300~3900자까지 벌어지는데 무엇이 중요한지 알려주는
    /// 장치가 없었다. A/B 3쌍(2026-09-15)에서 형식 3/3·앞배치 3/3·기존 축 누락 0으로
    /// 부작용은 없음을 확인했다. 재현율 개선은 로그의 reanalyze/prompt_edited 비율로 잰다.
    static let keyFeatureRules = """
    Before writing the prompts, identify the THREE features that matter most for \
    recognising this image at a glance — the ones a viewer notices first and whose loss \
    would make a regeneration feel wrong. Return them in "key_features" as exactly 3 \
    short English phrases, most important first, and state each one explicitly within \
    the first two sentences of every prompt.
    """

    /// 화면에 얹힌 것은 그림이 아니다 — 재현하면 원본에 없던 자막·HUD가 따라 들어온다.
    static let exclusionRules = """
    Describe only the artwork itself. Do NOT describe, and do not carry into the prompts, \
    anything overlaid on top of it: subtitles and captions, watermarks and signatures, \
    game HUD and status bars, health/mana meters, minimaps, menus, buttons, icons, \
    cursors, timestamps, channel logos, platform chrome, window title bars, or any \
    UI text. If such an element hides part of the artwork, describe what the artwork \
    plainly shows and ignore the overlay. Text that is painted into the artwork itself \
    (a sign in the scene, a title drawn as part of a cover) may be described, but never \
    the interface around it.
    """

    /// 원본이 2D인데 생성본이 입체로 나오던 문제 (2026-09-17).
    /// 실측: prompt_en 12건 중 6건이 "semi-realistic"을 썼고, 생성 모델은 그것을
    /// 3D 렌더링 지시로 받아들인다. 차원을 첫 문장에 못 박고 모호한 말을 금지한다.
    static let dimensionRules = """
    State the dimensionality explicitly in the FIRST SENTENCE of every prompt. If the \
    source is a flat drawing, say "flat 2D <medium>" and add "no 3D rendering, no \
    photographic depth". If it is a 3D render or a photograph, say so just as plainly. \
    Never use "semi-realistic", "realistic volume", "lifelike" or similar hedging words \
    for a 2D drawing — image models read them as a request for 3D shading and the result \
    stops looking like the original. Describe realistic anatomy or detailed shading with \
    terms that stay inside the drawing ("carefully drawn proportions", "soft cel shadows").
    """

    /// 긴 프롬프트가 늘 필요하지는 않다 — 짧은 판도 함께 준다.
    static let shortPromptRules = """
    Also produce "prompt_short": one English sentence under 300 characters that would \
    regenerate a recognisable version of this image. Lead with the dimensionality and \
    drawing style, then the subject and the single most important detail. It must work \
    on its own as a generation prompt — not a summary of the long one.
    """

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

    /// 세 언어 프롬프트 규칙 — 영어가 정본, 나머지는 같은 내용의 자연스러운 번역.
    ///
    /// 처음에는 각 언어를 독립 작성하게 했는데(2026-09-03까지) 내용과 분량이 어긋났다
    /// (실측: en 1437자 / ko 763자 / ja 594자 — 한국어·일본어가 절반 수준으로 축약).
    /// 이미지 생성에는 영어만 쓰므로, 한국어 탭을 읽고 예상한 것과 실제 생성 결과가
    /// 달라지는 문제가 있었다. 영어를 정본으로 삼아 세 탭이 같은 내용을 담게 한다.
    static let languageRules = """
    Write prompt_en first as the definitive version, with every detail. prompt_ko \
    (Korean) and prompt_ja (Japanese) must then carry exactly the same content as \
    prompt_en — same subject, pose, composition, lighting, color palette, style and \
    mood, with nothing added, dropped or reinterpreted. Render each one as a natural, \
    self-contained image-generation prompt in its own language rather than a \
    word-for-word transliteration, and keep them comparable in detail to the English \
    version — never a shortened summary.
    """

    /// 카메라 앵글·시점 규칙.
    ///
    /// 실측(2026-09-08): 히스토리 3건 중 앵글이 또렷이 적힌 것은 1건뿐이었다.
    /// composition이 "화면 어디에 배치됐는지"만 적고 **어디서 보고 있는지**는 빠졌다.
    /// 같은 인물·같은 포즈라도 로우앵글이냐 하이앵글이냐에 따라 전혀 다른 그림이 되므로
    /// 카메라 쪽 정보를 반드시 담게 한다. (pose는 피사체 쪽, composition은 카메라 쪽)
    static let cameraRules = """
    The "composition" field must state where the camera is, not just where things sit in \
    the frame: camera height and tilt (eye level, low angle looking up, high angle looking \
    down, overhead, or a dutch tilt), shooting distance (close-up, bust, waist-up, \
    full-body, wide establishing), and the lens character that follows from it (wide-angle \
    spread and edge distortion, normal, or telephoto compression with a flattened \
    background). Also note the horizon or vanishing-point placement when it is visible. \
    Carry the same viewpoint into the prompts — state the angle early, right after the \
    style clause, because a prompt that omits it gets rendered at a default eye-level view.
    """

    /// breakdown.composition 스키마 설명.
    static let compositionFieldDescription = """
    Framing and camera viewpoint: camera height and tilt (eye level / low / high / \
    overhead / dutch), shooting distance, lens character, subject placement in frame, \
    and horizon or vanishing-point placement when visible.
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
