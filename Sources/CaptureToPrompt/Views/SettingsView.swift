import SwiftUI

struct SettingsView: View {
    @AppStorage("backend") private var backend = AppState.Backend.claudeCLI.rawValue
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("model") private var model = PromptAnalyzer.defaultModel
    @AppStorage("routerBaseURL") private var routerBaseURL = LLMRouterAnalyzer.defaultBaseURL
    @AppStorage("routerAPIKey") private var routerAPIKey = ""
    @AppStorage("routerModel") private var routerModel = LLMRouterAnalyzer.defaultModel
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("imageGenEngine") private var imageGenEngine = AppState.ImageGenEngine.codexCLI.rawValue
    @AppStorage("imageGenBaseURL") private var imageGenBaseURL = ImageGenerator.defaultBaseURL
    @AppStorage("imageGenAPIKey") private var imageGenAPIKey = ""
    @AppStorage("imageGenModel") private var imageGenModel = ImageGenerator.defaultModel

    private let models = [
        "claude-opus-4-8",
        "claude-sonnet-5",
        "claude-haiku-4-5",
    ]

    @AppStorage("hotKeyPreset") private var hotKeyPreset = HotKeyManager.defaultPreset.rawValue
    @AppStorage("windowOpacity") private var windowOpacity = 0.85
    @AppStorage("autoAnalyzeOnCapture") private var autoAnalyzeOnCapture = false

    var body: some View {
        Form {
            Section {
                LabeledContent("배경 투명도") {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.dotted")
                            .foregroundStyle(.secondary)
                        Slider(value: $windowOpacity, in: 0.35...1)  // 완전 투명 방지
                            .frame(width: 180)
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("왼쪽으로 갈수록 유리처럼 투명해집니다. 메인 창에 바로 반영됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("전역 캡처 단축키", selection: $hotKeyPreset) {
                    ForEach(HotKeyManager.Preset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
                .onChange(of: hotKeyPreset) { _, newValue in
                    let preset = HotKeyManager.Preset(rawValue: newValue) ?? HotKeyManager.defaultPreset
                    HotKeyManager.shared.apply(preset: preset)
                }
                Text("어느 앱에 있든 이 키를 누르면 마우스 커서 아래 창을 자동 인식해 캡처·분석합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("캡처 후 자동 분석", isOn: $autoAnalyzeOnCapture)
                Text("끄면 캡처한 이미지를 먼저 확인한 뒤 '분석 시작' 버튼(⌘↩)으로 분석합니다. 파일 열기·클립보드는 항상 바로 분석합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("백엔드", selection: $backend) {
                    Text("Claude Code CLI (키 불필요)").tag(AppState.Backend.claudeCLI.rawValue)
                    Text("Codex CLI (키 불필요)").tag(AppState.Backend.codexCLI.rawValue)
                    Text("Anthropic API 키").tag(AppState.Backend.apiKey.rawValue)
                    Text("LLM Router (OpenAI 호환)").tag(AppState.Backend.router.rawValue)
                }
                .pickerStyle(.radioGroup)

                if backend == AppState.Backend.codexCLI.rawValue {
                    if let resolved = CodexCLIAnalyzer.locateBinary() {
                        Label("codex CLI 감지됨: \(resolved) — ChatGPT 로그인을 그대로 사용합니다.",
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("codex CLI를 찾을 수 없습니다. brew install codex 또는 npm i -g @openai/codex 후 로그인하세요.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if backend == AppState.Backend.claudeCLI.rawValue {
                    TextField("claude 경로 (비우면 자동 탐색)", text: $claudePath,
                              prompt: Text("예: /opt/homebrew/bin/claude"))
                        .autocorrectionDisabled()
                    if let resolved = ClaudeCLIAnalyzer.resolveBinary(custom: claudePath) {
                        Label("claude CLI 감지됨: \(resolved) — 구독 로그인을 그대로 사용합니다.",
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if claudePath.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("""
                        claude CLI를 찾을 수 없습니다. 설치되어 있다면 위에 경로를 입력하세요 \
                        (터미널에서 which claude). Claude Code가 없는 PC라면 위에서 \
                        다른 백엔드를 선택하세요.
                        """,
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("지정한 경로를 실행할 수 없습니다. 터미널에서 which claude 로 확인하세요.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if backend == AppState.Backend.apiKey.rawValue {
                Section {
                    SecureField("Anthropic API 키", text: $apiKey)
                        .textContentType(.password)
                    Text("비워두면 ANTHROPIC_API_KEY 환경변수를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("모델", selection: $model) {
                        ForEach(models, id: \.self) { Text($0) }
                    }
                    Text("기본값 claude-opus-4-8 — 가장 정확한 분석. 비용을 아끼려면 haiku를 선택하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if backend == AppState.Backend.router.rawValue {
                Section {
                    TextField("Base URL", text: $routerBaseURL,
                              prompt: Text(LLMRouterAnalyzer.defaultBaseURL))
                        .autocorrectionDisabled()
                    SecureField("LLM Router API 키", text: $routerAPIKey)
                        .textContentType(.password)
                    Text("비워두면 LLM_ROUTER_API_KEY 환경변수를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("모델", text: $routerModel,
                              prompt: Text(LLMRouterAnalyzer.defaultModel))
                        .autocorrectionDisabled()
                    Text("auto = 자동 라우팅. auto:cost / auto:speed / auto:quality 라우팅 목표나 특정 모델 id도 지정할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("이미지 생성") {
                Picker("엔진", selection: $imageGenEngine) {
                    Text("Codex CLI (키 불필요)").tag(AppState.ImageGenEngine.codexCLI.rawValue)
                    Text("OpenAI 호환 API (키)").tag(AppState.ImageGenEngine.openAIAPI.rawValue)
                }
                .pickerStyle(.radioGroup)

                if imageGenEngine == AppState.ImageGenEngine.codexCLI.rawValue {
                    if CodexCLIAnalyzer.locateBinary() != nil {
                        Label("codex CLI 감지됨 — ChatGPT 구독으로 이미지를 생성합니다.",
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("codex CLI를 찾을 수 없습니다. brew install codex 또는 npm i -g @openai/codex 후 로그인하세요.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    TextField("Base URL", text: $imageGenBaseURL,
                              prompt: Text(ImageGenerator.defaultBaseURL))
                        .autocorrectionDisabled()
                    SecureField("API 키", text: $imageGenAPIKey)
                        .textContentType(.password)
                    TextField("모델", text: $imageGenModel,
                              prompt: Text(ImageGenerator.defaultModel))
                        .autocorrectionDisabled()
                    Text("OpenAI 호환 Images API — 키를 비우면 OPENAI_API_KEY 환경변수를 사용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // 섹션이 많아 스크롤이 생기므로 높이를 넉넉히 고정 (잘림 방지)
        .frame(width: 480, height: 620)
    }
}
