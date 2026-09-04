import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var history: HistoryStore
    @State private var isDropTargeted = false
    @AppStorage("windowOpacity") private var windowOpacity = 0.85
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        // 전체 비율 1(사이드바) : 5(이미지) : 2(결과) — 기본 창 폭 ~1300 기준 164:820:330.
        // HSplitView는 idealWidth를 무시하고 반반 분할하는 문제가 있어(실측 확인),
        // 결과 패널은 ideal 폭을 존중하는 .inspector(우측 패널 정식 API)로 배치한다.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebar()
                .navigationSplitViewColumnWidth(min: 150, ideal: 164, max: 340)
                .background(.ultraThinMaterial)
        } detail: {
            imagePane
                .frame(minWidth: 220)
                .inspector(isPresented: .constant(true)) {
                    ResultPane()
                        // maxWidth 제한: 초광폭 창에서 프롬프트 한 줄이 무한정
                        // 길어지는 것 방지 (가독 폭 유지)
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 640)
                }
        }
        // 창 배경 자체를 유리 재질로. (별도 glass 판을 얹는 방식은 사이드바
        // 리사이즈 시 렌더링이 깨져 창이 통째로 투명해지는 문제가 있었음)
        .containerBackground(.ultraThinMaterial.opacity(windowOpacity), for: .window)
        .toolbar {
            // 히스토리 열람 중에도 "새로 시작"이 한눈에 보이도록 맨 앞에 배치
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.startNewCapture()
                } label: {
                    Label("새 캡처", systemImage: "plus")
                }
                .disabled(appState.analysis == nil && appState.currentImageData == nil)
                .help("현재 결과를 닫고 시작 화면으로 돌아갑니다 (⌘N)")
            }
            // 재분석은 "이 항목"에 대한 동작이라 캡처 그룹과 떼어 앞쪽에 둔다
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.reanalyzeCurrent()
                } label: {
                    Label("다시 분석", systemImage: "arrow.clockwise")
                }
                // 다른 이미지가 분석 중이어도 걸 수 있다 — 같은 항목만 중복 방지
                .disabled(appState.currentHistoryItem == nil
                          || appState.isAnalyzing(for: appState.currentHistoryID))
                .help("원본 캡처 이미지로 프롬프트를 다시 뽑습니다 — 결과는 새 항목 (⌘R)")
            }
            // 캡처 계열(주 동작)과 가져오기 계열을 그룹으로 분리해 시각적 과밀 완화
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.captureWindowUnderMouseAndAnalyze()
                } label: {
                    Label("창 캡처", systemImage: "macwindow.badge.plus")
                }
                .help("마우스 아래 창을 자동 인식해 캡처·분석합니다 (⌘1, 전역 \(currentHotKeyLabel))")

                Button {
                    appState.captureSelectedWindowAndAnalyze()
                } label: {
                    Label("창 선택", systemImage: "macwindow.on.rectangle")
                }
                .help("열린 창 그리드에서 클릭해 캡처·분석합니다 (⌘2)")

                Button {
                    appState.captureAndAnalyze()
                } label: {
                    Label("영역 캡처", systemImage: "camera.viewfinder")
                }
                .help("화면 영역을 직접 선택해 캡처하고 분석합니다 (⌘3)")
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    appState.analyzeFromClipboard()
                } label: {
                    Label("클립보드", systemImage: "doc.on.clipboard")
                }
                .help("클립보드의 이미지를 분석합니다 (⌘⇧V)")

                Button {
                    appState.showFileImporter = true
                } label: {
                    Label("파일 열기", systemImage: "folder")
                }
                .help("이미지 파일을 선택해 분석합니다 (⌘O)")
            }
        }
        .sheet(isPresented: $appState.showingRevision) {
            PromptRevisionSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showWindowPicker) {
            WindowPickerSheet()
                .environmentObject(appState)
        }
        .fileImporter(isPresented: $appState.showFileImporter,
                      allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let accessing = url.startAccessingSecurityScopedResource()
                appState.analyzeFile(at: url)
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
        }
        .frame(minWidth: 800, minHeight: 480)
        .task { appState.checkForUpdatesInBackground() }
    }

    // MARK: - 왼쪽: 이미지 영역

    /// 원본/생성본 중 현재 선택된 이미지 데이터.
    private var displayedImageData: Data? {
        appState.selectedGeneratedImage ?? appState.currentImageData
    }

    /// 원본 + 생성본 N장 전환 세그먼트와 비교 토글. 선택 상태는 AppState에 있어
    /// 화면이 다시 그려져도 유지된다.
    private var imageSourceBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $appState.selectedGeneratedIndex) {
                Text("원본").tag(Int?.none)
                ForEach(Array(appState.generatedImages.indices), id: \.self) { index in
                    Text("생성 \(index + 1)").tag(Int?.some(index))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if appState.canCompare {
                Toggle(isOn: $appState.isComparingWithOriginal) {
                    Label("원본과 비교", systemImage: "rectangle.split.2x1")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("원본과 이 생성본을 나란히 놓고 봅니다")
            }
        }
        .padding(.top, 12)
    }

    /// 비교 보기: 원본과 선택한 생성본을 나란히.
    private func compareView(original: Data, generated: Data) -> some View {
        HStack(spacing: 12) {
            labeledImage(original, caption: "원본")
            labeledImage(generated,
                         caption: "생성 \((appState.selectedGeneratedIndex ?? 0) + 1)")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func labeledImage(_ data: Data, caption: String) -> some View {
        VStack(spacing: 6) {
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imagePane: some View {
        VStack(spacing: 0) {
            if !appState.generatedImages.isEmpty {
                imageSourceBar
            }
            if appState.isComparingWithOriginal, appState.canCompare,
               let original = appState.currentImageData,
               let generated = appState.selectedGeneratedImage {
                compareView(original: original, generated: generated)
            } else if let data = displayedImageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if appState.analysis != nil || appState.isAnalyzing {
                // 분석은 있는데 원본 이미지 파일이 없는 경우 (온보딩과 구분)
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("원본 이미지를 찾을 수 없습니다")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }

            if let update = appState.availableUpdate {
                updateBanner(update)
            }
            if let error = appState.visibleErrorMessage {
                errorBanner(error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if appState.isGeneratingImage { generatingOverlay }
        }
        .overlay {
            if isDropTargeted { dropHighlight }
        }
        .animation(.smooth(duration: 0.25), value: isDropTargeted)
        .animation(.smooth(duration: 0.3), value: appState.currentImageData)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// 빈 상태: 온보딩 겸 퀵 액션.
    private var emptyState: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("이미지에서 프롬프트 만들기")
                    .font(.title3.weight(.semibold))
                Text("이미지를 드래그하거나, 아래 버튼으로 시작하세요")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // 창 폭에 따라 가로 한 줄 ↔ 세로 스택으로 재배치
            ViewThatFits(in: .horizontal) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) { quickActionButtons }
                }
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) { quickActionButtons }
                }
            }
            .controlSize(.large)

            Text("어느 앱에서든 \(currentHotKeyLabel) 를 누르면 마우스 아래 창을 바로 분석합니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        Button {
            appState.captureWindowUnderMouseAndAnalyze()
        } label: {
            Label("창 캡처", systemImage: "macwindow.badge.plus")
                .padding(.horizontal, 4)
        }
        .buttonStyle(.glassProminent)

        Button {
            appState.captureSelectedWindowAndAnalyze()
        } label: {
            Label("창 선택", systemImage: "macwindow.on.rectangle")
        }
        .buttonStyle(.glass)

        Button {
            appState.captureAndAnalyze()
        } label: {
            Label("영역 캡처", systemImage: "camera.viewfinder")
        }
        .buttonStyle(.glass)

        Button {
            appState.analyzeFromClipboard()
        } label: {
            Label("클립보드", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.glass)
    }

    private var currentHotKeyLabel: String {
        let raw = UserDefaults.standard.string(forKey: "hotKeyPreset") ?? ""
        return (HotKeyManager.Preset(rawValue: raw) ?? HotKeyManager.defaultPreset).label
    }

    /// 이미지 생성은 1분 가까이 걸리므로 원본 위에 진행 상태를 크게 보여준다.
    private var generatingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("이미지 생성 중…")
                .font(.headline)
            if let startedAt = appState.generationStartedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(startedAt))
                    Text("경과 \(elapsed)초 · 보통 1분 정도 걸립니다")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(26)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .transition(.opacity)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8]))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay {
                Label("놓아서 분석", systemImage: "arrow.down.circle")
                    .font(.title3.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
            }
            .padding(12)
            .allowsHitTesting(false)
    }

    /// 새 버전 알림 — 확인은 자동, 설치는 이 버튼을 누를 때만.
    private func updateBanner(_ update: UpdateChecker.Release) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("새 버전 \(update.version.description)이 있습니다 "
                     + "(현재 \(appState.currentAppVersion))")
                    .font(.callout.weight(.medium))
                if !update.notes.isEmpty {
                    Text(update.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                appState.installAvailableUpdate()
            } label: {
                if appState.isInstallingUpdate {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("설치 중…")
                    }
                } else {
                    Text("설치하고 다시 열기")
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(appState.isInstallingUpdate)
            .help("새 버전을 내려받아 교체하고 앱을 다시 엽니다 (약 \(updateSizeText(update)))")
            Button {
                appState.dismissUpdate()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(appState.isInstallingUpdate)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.blue.opacity(0.12)), in: .rect(cornerRadius: 12))
        .padding([.horizontal, .bottom], 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func updateSizeText(_ update: UpdateChecker.Release) -> String {
        ByteCountFormatter.string(fromByteCount: update.byteSize, countStyle: .file)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            // 정책 거부일 때만: 어느 구절이 걸렸는지 진단하고 수정본을 받아온다
            if appState.currentPolicyRejection != nil {
                Button {
                    if appState.currentRevision != nil {
                        appState.showingRevision = true
                    } else {
                        appState.requestPromptRevision()
                    }
                } label: {
                    if appState.isRevisingPrompt {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("진단 중…")
                        }
                    } else {
                        Label(appState.currentRevision == nil ? "개선점 보기" : "개선안 열기",
                              systemImage: "wand.and.sparkles")
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(appState.isRevisingPrompt)
                .help("프롬프트의 어느 부분이 정책에 걸렸는지 진단하고 수정본을 제안합니다")
            }
            Button {
                appState.dismissVisibleError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.red.opacity(0.12)), in: .rect(cornerRadius: 12))
        .padding([.horizontal, .bottom], 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    Task { @MainActor in appState.analyzeFile(at: url) }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data {
                    Task { @MainActor in await appState.analyze(rawImageData: data) }
                }
            }
            return true
        }
        return false
    }
}
