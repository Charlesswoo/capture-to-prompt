import SwiftUI
import AppKit

/// 분석 결과 표시: 한국어/영어/일본어/JSON 탭 + 복사 + breakdown.
struct ResultPane: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .korean
    @State private var showCopiedToast = false
    @State private var isEditingPrompt = false
    /// 생성본 전체 삭제는 되돌릴 수 없으므로 한 번 확인한다.
    @State private var confirmDeleteAll = false
    @State private var editingText = ""
    /// 메타(breakdown)는 기본 접힘 — 프롬프트 중심 화면. 펼침 상태는 기억한다.
    @AppStorage("showBreakdown") private var showBreakdown = false

    enum Tab: String, CaseIterable, Identifiable {
        case korean = "한국어"
        case english = "English"
        case japanese = "日本語"
        case json = "JSON"
        var id: String { rawValue }

        /// JSON 탭은 파생 뷰이므로 편집 대상이 아니다.
        var editableLanguage: PromptAnalysis.PromptLanguage? {
            switch self {
            case .korean: return .korean
            case .english: return .english
            case .japanese: return .japanese
            case .json: return nil
            }
        }
    }

    var body: some View {
        Group {
            // 분석 중이라도 히스토리에서 불러온 결과가 있으면 그걸 우선 보여준다
            // (스피너는 보여줄 분석이 없을 때만)
            if let analysis = appState.analysis {
                resultView(analysis)
            } else if appState.isAnalyzing {
                analyzingView
            } else if appState.pendingImageData != nil {
                pendingView
            } else {
                placeholder
            }
        }
        .animation(.smooth(duration: 0.3), value: appState.isAnalyzing)
        .confirmationDialog("이 항목의 생성 이미지를 모두 삭제할까요?",
                            isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("\(appState.currentGeneratedImageCount)장 삭제", role: .destructive) {
                appState.deleteAllGeneratedImages()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("생성 이미지 \(appState.currentGeneratedImageCount)장(\(deletableSizeText))이 "
                 + "디스크에서 지워집니다. 되돌릴 수 없습니다.\n"
                 + "분석 결과와 원본 캡처 이미지는 그대로 남습니다.")
        }
    }

    /// 삭제될 용량 표기 (예: "5.4MB").
    private var deletableSizeText: String {
        ByteCountFormatter.string(fromByteCount: appState.currentGeneratedImagesByteSize,
                                  countStyle: .file)
    }

    // MARK: - 상태별 뷰

    private var placeholder: some View {
        ContentUnavailableView {
            Label("분석 결과 없음", systemImage: "text.below.photo")
        } description: {
            Text("이미지를 분석하면 3개 언어 프롬프트와 구조 분석이 여기에 표시됩니다")
        }
    }

    /// 자동 분석 off: 캡처 이미지를 확인한 뒤 수동으로 분석을 시작하는 화면.
    private var pendingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("캡처 완료 — 분석 대기 중")
                .font(.headline)
            Text("왼쪽 이미지를 확인한 뒤 분석을 시작하세요")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                appState.analyzePending()
            } label: {
                Label("분석 시작", systemImage: "wand.and.stars")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .help("대기 중인 캡처 이미지를 분석합니다 (⌘↩)")
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// CLI 백엔드는 30~60초가 걸리므로 경과 시간을 보여줘 불안감을 줄인다.
    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("\(appState.analyzerDisplayName)가 이미지를 분석 중입니다…")
                .font(.headline)
            if let startedAt = appState.analysisStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(startedAt))
                    Text("경과 \(elapsed)초 · 보통 30~60초 걸립니다")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ analysis: PromptAnalysis) -> some View {
        Group {
            if isEditingPrompt {
                promptEditor
            } else {
                normalResultView(analysis)
            }
        }
        // 탭 전환·새 분석 도착 시 편집 중이던 내용은 버린다 (다른 탭에 잘못 저장 방지).
        // 포즈는 언어 탭과 무관하므로 탭을 바꿔도 편집을 유지한다.
        .onChange(of: selectedTab) { _, _ in isEditingPrompt = false }
        .onChange(of: appState.analysis) { _, _ in isEditingPrompt = false }
    }

    /// 편집 모드: 결과 패널 전체를 차지하는 큰 편집기.
    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("프롬프트 수정 — \(selectedTab.rawValue)")
                    .font(.headline)
                Spacer()
                Button("취소") { isEditingPrompt = false }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .help("변경을 버리고 돌아갑니다 (Esc)")
                Button("저장") { commitPromptEdit() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("수정본을 저장합니다 — 이미지 생성·히스토리에도 반영 (⌘S)")
            }

            TextEditor(text: $editingText)
                .font(.body)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    /// 포즈는 프롬프트 본문에 이미 녹아 있는 내용을 따로 뽑아 보여주는 **대조용 요약**이다.
    /// (프롬프트 1000자를 이미지와 맞춰보긴 어려우므로) 메타를 접어도 이 줄만은 남긴다.
    /// 고칠 때는 프롬프트를 고쳐야 한다 — 생성에 쓰이는 건 프롬프트 문장이기 때문.
    private func poseSection(_ pose: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("포즈", systemImage: "figure.stand")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(pose)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("포즈 서술을 복사합니다")
                    .accessibilityHint("생성에는 위 프롬프트가 쓰입니다")
            }
            Text(pose)
                .font(.callout)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func normalResultView(_ analysis: PromptAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 이 항목을 다시 분석 중이거나, 화면을 점유한 새 분석이 도는 중임을 알린다
            if appState.isAnalyzing || appState.isAnalyzing(for: appState.currentHistoryID) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.isAnalyzing(for: appState.currentHistoryID)
                         ? "이 원본으로 다시 분석 중 — 완료되면 새 결과로 바뀝니다"
                         : "새 분석 진행 중 — 완료되면 이 화면이 새 결과로 바뀝니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            // 헤더: 언어 탭
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    if tab == .json {
                        Image(systemName: "curlybraces").tag(tab)
                            .help("JSON")
                    } else {
                        Text(tab.rawValue).tag(tab)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            // 본문 + breakdown을 한 스크롤로 — breakdown이 세로로 압축되며
            // 글자가 겹치는 문제 방지 (내용이 길면 함께 스크롤된다)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 프롬프트 카드 — 메타 박스와 같은 구조 (박스 안 헤더 + 복사 버튼)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("프롬프트")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if appState.isSyncingPrompt {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("다른 언어 맞추는 중…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTab.editableLanguage != nil {
                                Button {
                                    editingText = text(for: analysis)
                                    isEditingPrompt = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .help("프롬프트 수정 — 저장하면 이미지 생성·히스토리에도 반영됩니다")
                            }
                            Button {
                                copy(text(for: analysis))
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                            .help("현재 탭 내용을 복사합니다 (⌘⇧C)")
                        }

                        Text(text(for: analysis))
                            .font(selectedTab == .json ? .system(.callout, design: .monospaced) : .body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )

                    breakdownView(analysis.breakdown)
                }
                .padding([.horizontal, .bottom])
            }

            Divider()
            imageGenBar
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast { copiedToast }
        }
        .animation(.bouncy(duration: 0.35), value: showCopiedToast)
    }

    /// 편집 내용을 현재 분석·히스토리에 반영한다.
    private func commitPromptEdit() {
        if let language = selectedTab.editableLanguage {
            appState.applyEditedPrompt(editingText, for: language)
            // 이미지 생성은 영어 프롬프트를 쓰므로, 다른 언어로 고쳤다면
            // 나머지 언어를 같은 내용으로 맞춰야 수정이 생성에 반영된다
            appState.syncEditedPrompt(editingText, from: language)
        }
        isEditingPrompt = false
    }

    // MARK: - 이미지 생성

    /// 하단 고정 액션 바 — 스크롤과 무관하게 항상 보인다.
    /// 생성된 이미지는 왼쪽 패널(원본/생성N 전환)에 크게 표시되고, 복사·저장·삭제는
    /// 거기서 지금 보고 있는 생성본에 적용된다.
    private var imageGenBar: some View {
        HStack(spacing: 8) {
            if appState.selectedGeneratedImage != nil {
                // 패널이 좁아지면(최소 280pt) 텍스트가 잘리므로 아이콘만 남긴다
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { generatedImageActions(showsText: true) }
                    HStack(spacing: 8) { generatedImageActions(showsText: false) }
                }
                .fixedSize()
            }
            Spacer(minLength: 8)
            generateMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 좁은 패널에서는 아이콘만 (텍스트가 줄임표로 잘리는 것 방지).
    @ViewBuilder
    private func actionLabel(_ title: String, icon: String, showsText: Bool) -> some View {
        if showsText {
            Label(title, systemImage: icon)
        } else {
            Label(title, systemImage: icon).labelStyle(.iconOnly)
        }
    }

    /// 보고 있는 생성본에 대한 동작 — 복사·저장·삭제.
    @ViewBuilder
    private func generatedImageActions(showsText: Bool) -> some View {
        if let data = appState.selectedGeneratedImage {
            Button {
                copyImage(data)
            } label: {
                actionLabel("복사", icon: "doc.on.doc", showsText: showsText)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("보고 있는 생성 이미지를 복사합니다")

            Button {
                saveImage(data)
            } label: {
                // "저장…"의 말줄임표는 대화상자가 열린다는 macOS 관례 표기다
                actionLabel("저장…", icon: "square.and.arrow.down", showsText: showsText)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("보고 있는 생성 이미지를 PNG로 저장합니다")

            Menu {
                Button("이 생성본 삭제", systemImage: "trash") {
                    appState.deleteSelectedGeneratedImage()
                }
                if appState.currentGeneratedImageCount > 1 {
                    Divider()
                    Button("생성본 \(appState.currentGeneratedImageCount)장 모두 삭제",
                           systemImage: "trash.slash", role: .destructive) {
                        confirmDeleteAll = true
                    }
                }
            } label: {
                Image(systemName: "trash")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .controlSize(.small)
            .fixedSize()
            .help("생성 이미지를 삭제합니다 (이 장만 또는 전부)")
        }
    }

    /// 주 버튼은 "새로 생성", 화살표를 누르면 변형·교체·프롬프트 추출.
    /// 프롬프트는 지금 보고 있는 언어 탭의 것을 쓴다 (JSON 탭이면 영문).
    private var generateMenu: some View {
        Menu {
            Button {
                appState.generateImage(prompt: promptForGeneration,
                                       language: generationLanguage, mode: .variation)
            } label: {
                Label("보고 있는 이미지 기반 변형", systemImage: "wand.and.sparkles")
            }
            .disabled(appState.currentImageData == nil)

            Button {
                appState.generateImage(prompt: promptForGeneration,
                                       language: generationLanguage, mode: .replaceCurrent)
            } label: {
                Label("이 탭 다시 생성 (자리 교체)", systemImage: "arrow.trianglehead.2.clockwise")
            }
            .disabled(appState.selectedGeneratedImage == nil)

            Divider()

            Button {
                appState.extractPromptFromSelection()
            } label: {
                Label("이 생성본으로 프롬프트 추출", systemImage: "text.viewfinder")
            }
            .disabled(!appState.canExtractPromptFromSelection)

            if let language = currentTabLanguage, let analysis = appState.analysis {
                Divider()
                Button {
                    appState.generateImage(prompt: analysis.prompt(for: language),
                                           language: language, mode: .new)
                } label: {
                    Label("\(selectedTab.rawValue) 프롬프트로 생성", systemImage: "character.bubble")
                }
            }

            Divider()
            Text("생성에는 영어 프롬프트를 씁니다 — 다른 언어로는 색감·구도가 어긋납니다")
        } label: {
            if appState.isGeneratingImage {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("생성 중…")
                }
            } else {
                Label(appState.generatedImages.isEmpty ? "이미지 생성" : "새로 생성",
                      systemImage: "photo.badge.plus")
            }
        } primaryAction: {
            appState.generateImage(prompt: promptForGeneration,
                                   language: generationLanguage, mode: .new)
        }
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .fixedSize()
        .disabled(appState.isGeneratingImage || appState.isSyncingPrompt)
        .help("영어 프롬프트로 생성합니다 (색감·구도가 가장 정확합니다). 결과는 이 항목에 쌓입니다")
    }

    /// 생성에는 **영어 프롬프트**를 쓴다.
    /// 실측 결과 한국어 프롬프트를 넘기면 모델이 색감·구도 지시를 놓쳐 전혀 다른 톤이 나온다.
    private var promptForGeneration: String? {
        appState.analysis?.prompt(for: defaultGenerationLanguage)
    }

    private var generationLanguage: PromptAnalysis.PromptLanguage {
        defaultGenerationLanguage
    }

    /// 보고 있는 탭이 영어가 아닐 때만 의미 있는 대안 (직접 고른 언어로 생성).
    private var currentTabLanguage: PromptAnalysis.PromptLanguage? {
        guard let language = selectedTab.editableLanguage,
              language != defaultGenerationLanguage else { return nil }
        return language
    }

    private var generationPromptLabel: String { "English" }

    private func copyImage(_ data: Data) {
        guard let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            showCopiedToast = false
        }
    }

    private func saveImage(_ data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // API가 png 외 형식을 줄 수도 있으므로 비트맵으로 재인코딩해 저장
        let pngData = NSBitmapImageRep(data: data)?
            .representation(using: .png, properties: [:]) ?? data
        try? pngData.write(to: url)
    }

    // MARK: - breakdown

    private func breakdownView(_ b: PromptAnalysis.Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { showBreakdown.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showBreakdown ? "분석 상세" : "분석 상세 더 보기")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(showBreakdown ? 90 : 0))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("이 프롬프트가 어떻게 구성됐는지 보여주는 참고 정보입니다 — 이미지 생성에는 위 프롬프트 문장이 쓰입니다")
                Spacer()
                if showBreakdown {
                    Button {
                        copy(metaText(b))
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("메타 전체 복사")
                }
            }

            // 인물이 있으면 포즈는 접어도 보인다 (검증용)
            if !b.pose.isEmpty {
                poseSection(b.pose)
                if showBreakdown { Divider().padding(.vertical, 2) }
            }

            if showBreakdown {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("주제", b.subject)
                row("스타일", b.style)
                row("구성", b.composition)
                row("조명", b.lighting)
                row("색감", b.colorPalette)
                row("분위기", b.mood)
                row("매체", b.medium)
            }
            .font(.callout)

            if !b.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(b.tags, id: \.self) { tag in
                                Button {
                                    copy(tag)
                                } label: {
                                    Text(tag)
                                        .font(.caption)
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .help("클릭해서 태그 복사")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            }  // if showBreakdown
        }
        .padding(14)
        .background(.ultraThinMaterial.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .contextMenu {
                    Button("복사") { copy(value) }
                }
        }
    }

    /// breakdown 전체를 붙여넣기 좋은 텍스트로 만든다.
    private func metaText(_ b: PromptAnalysis.Breakdown) -> String {
        """
        주제: \(b.subject)
        \(b.pose.isEmpty ? "" : "포즈: \(b.pose)\n")스타일: \(b.style)
        구성: \(b.composition)
        조명: \(b.lighting)
        색감: \(b.colorPalette)
        분위기: \(b.mood)
        매체: \(b.medium)
        태그: \(b.tags.joined(separator: ", "))
        """
    }

    // MARK: - 복사 & 토스트

    private var copiedToast: some View {
        Label("복사됨", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular.tint(.green.opacity(0.15)), in: .capsule)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func text(for analysis: PromptAnalysis) -> String {
        switch selectedTab {
        case .korean: return analysis.promptKo
        case .english: return analysis.promptEn
        case .japanese: return analysis.promptJa
        case .json: return analysis.prettyJSON()
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            showCopiedToast = false
        }
    }
}
