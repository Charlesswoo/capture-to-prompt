import Foundation
import SwiftUI
import AppKit

/// 앱 전역 상태: 현재 이미지, 분석 결과, 진행 상태.
@MainActor
final class AppState: ObservableObject {
    @Published var currentImageData: Data?
    @Published var analysis: PromptAnalysis?
    /// 진행 중인 분석들 — 이미지마다 병렬로 돌 수 있다.
    @Published private(set) var runningAnalyses: [UUID: AnalysisJob] = [:]

    /// 분석 한 건. 재분석은 출처 항목을 기억해 두고, 결과를 화면에 띄울지 판단한다.
    struct AnalysisJob: Identifiable, Equatable {
        let id: UUID
        let startedAt: Date
        /// 재분석이면 원본 항목, 새 캡처·파일·클립보드면 nil.
        let sourceHistoryID: UUID?
        /// 시작할 때 화면을 점유했는지 (새 캡처는 점유, 재분석은 백그라운드).
        let takesOverScreen: Bool
    }
    /// 캡처·분석 등 화면 전역 오류 (보고 있는 항목과 무관).
    @Published var errorMessage: String?
    /// 이미지 생성 오류는 항목별로 남긴다 — 여러 항목이 동시에 생성될 수 있으므로
    /// 실패가 엉뚱한 항목 화면에 새어나오거나 서로 덮어쓰면 안 된다.
    @Published private(set) var generationErrors: [UUID: String] = [:]
    /// 정책 거부로 실패한 항목만 — 어느 프롬프트가 어떤 사유로 막혔는지 (개선 제안 입력).
    @Published private(set) var policyRejections: [UUID: PolicyRejection] = [:]
    /// 받아 둔 프롬프트 개선안 (항목별).
    @Published private(set) var revisions: [UUID: PromptRevision] = [:]
    /// 개선안을 요청 중인 항목들.
    @Published private(set) var revisingHistoryIDs: Set<UUID> = []
    /// 개선안 시트 표시 여부.
    @Published var showingRevision = false

    // MARK: - 자동 업데이트 (확인 자동 / 설치 수동)

    /// 새 버전이 있으면 여기에 담긴다 — 배너로 알리고, 설치는 사용자가 누를 때만.
    @Published private(set) var availableUpdate: UpdateChecker.Release?
    @Published private(set) var isInstallingUpdate = false
    @AppStorage("checkForUpdatesOnLaunch") var checkForUpdatesOnLaunch = true

    var currentAppVersion: String { UpdateChecker.currentVersion }

    /// "최신 버전입니다" 같은 안내 — 오류가 아니므로 오류 배너와 분리한다.
    @Published var updateNotice: String?
    private var lastUpdateCheck: Date?
    private var periodicCheckTask: Task<Void, Never>?

    /// 조용히 확인한다 (실패해도 화면에 오류를 띄우지 않는다 —
    /// 네트워크가 없다고 사용이 막히면 안 되므로).
    /// 이미 알림이 떠 있거나 확인 간격이 안 지났으면 건너뛴다.
    func checkForUpdatesInBackground(force: Bool = false) {
        guard checkForUpdatesOnLaunch else { return }
        guard availableUpdate == nil else { return }
        guard force || UpdateChecker.shouldCheck(lastCheck: lastUpdateCheck) else { return }
        lastUpdateCheck = Date()
        Task {
            availableUpdate = try? await UpdateChecker.checkForUpdate()
        }
    }

    /// 앱이 켜져 있는 동안 주기적으로 확인한다 (시작 시 1회 + 이후 1시간마다).
    /// 창이 다시 활성화될 때도 확인하지만, 간격이 지나지 않았으면 조회하지 않는다.
    func startPeriodicUpdateChecks() {
        guard periodicCheckTask == nil else { return }
        checkForUpdatesInBackground(force: true)
        periodicCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(UpdateChecker.checkInterval))
                guard !Task.isCancelled else { break }
                self?.checkForUpdatesInBackground()
            }
        }
    }

    /// 메뉴에서 직접 확인 — 결과를 반드시 알려준다 (최신이면 최신이라고).
    func checkForUpdatesNow() {
        lastUpdateCheck = Date()
        Task {
            do {
                if let release = try await UpdateChecker.checkForUpdate() {
                    availableUpdate = release
                } else {
                    availableUpdate = nil
                    updateNotice = "최신 버전을 쓰고 계십니다 (\(currentAppVersion))."
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        updateNotice = nil
                    }
                }
            } catch {
                errorMessage = "업데이트 확인 실패: \(error.localizedDescription)"
            }
        }
    }

    /// 새 버전을 내려받아 교체하고 앱을 다시 연다.
    func installAvailableUpdate() {
        guard let release = availableUpdate, !isInstallingUpdate else { return }
        isInstallingUpdate = true
        Task {
            do {
                let newApp = try await UpdateInstaller.downloadAndUnpack(from: release.downloadURL)
                try UpdateInstaller.replaceAndRelaunch(newApp: newApp)  // 여기서 앱이 종료된다
            } catch {
                isInstallingUpdate = false
                errorMessage = "업데이트 설치 실패: \(error.localizedDescription)"
            }
        }
    }

    func dismissUpdate() { availableUpdate = nil }

    /// 정책에 걸린 생성 시도의 기록.
    struct PolicyRejection: Equatable {
        var prompt: String                          // 거부된 프롬프트 원문
        var detail: String?                         // 제공자가 준 사유
        var language: PromptAnalysis.PromptLanguage // 어느 언어 탭으로 시도했는지
    }
    /// 현재 항목에서 생성한 이미지들(오래된 순). 히스토리에 파일로 함께 보관된다.
    @Published var generatedImages: [Data] = []
    /// 왼쪽 패널에서 보고 있는 생성 이미지 인덱스. nil이면 원본을 본다.
    @Published var selectedGeneratedIndex: Int?
    /// 원본과 생성본을 나란히 놓고 볼지 (생성본 탭을 보고 있을 때만 의미 있다).
    @Published var isComparingWithOriginal = false
    /// 지금 이미지 생성이 돌고 있는 히스토리 항목들 — 항목마다 따로 걸 수 있다.
    @Published private(set) var generatingHistoryIDs: Set<UUID> = []
    private var generationStartedAtByID: [UUID: Date] = [:]
    /// 지금 화면을 차지한 분석. 캡처를 잇따라 걸면 마지막 것이 화면의 주인이 되고,
    /// 앞서 걸린 분석이 먼저 끝나도 화면을 빼앗지 않는다.
    private var foregroundAnalysisID: UUID?
    /// 현재 화면의 분석이 히스토리 어느 항목에서 왔는지 — 프롬프트 수정 반영용.
    private(set) var currentHistoryID: UUID?

    @AppStorage("apiKey") private var storedAPIKey = ""
    @AppStorage("model") var model = PromptAnalyzer.defaultModel
    @AppStorage("backend") var backend = Backend.claudeCLI.rawValue
    @AppStorage("claudePath") var claudePath = ""
    @AppStorage("imageGenEngine") var imageGenEngine = ImageGenEngine.codexCLI.rawValue
    @AppStorage("imageGenBaseURL") var imageGenBaseURL = ImageGenerator.defaultBaseURL
    @AppStorage("imageGenAPIKey") private var storedImageGenKey = ""
    @AppStorage("imageGenModel") var imageGenModel = ImageGenerator.defaultModel
    @AppStorage("autoAnalyzeOnCapture") var autoAnalyzeOnCapture = false

    enum Backend: String {
        case claudeCLI = "cli"   // 로컬 Claude Code 구독 로그인 사용 (키 불필요)
        case codexCLI = "codex"  // 로컬 OpenAI Codex CLI (ChatGPT 구독, 키 불필요)
        case apiKey = "api"      // Anthropic API 키 직접 호출
    }

    /// 분석 중 화면 등 UI에 표시할 현재 백엔드 이름.
    var analyzerDisplayName: String {
        switch Backend(rawValue: backend) ?? .claudeCLI {
        case .claudeCLI: return "Claude"
        case .codexCLI: return "Codex"
        case .apiKey: return "Claude"
        }
    }

    /// 이미지 생성 방식 — 하단 액션 바의 메뉴에 대응.
    enum GenerationMode: Equatable {
        /// 프롬프트만으로 새로 만들어 목록 끝에 추가.
        case new
        /// 지금 보고 있는 이미지를 참조로 변형해 목록 끝에 추가.
        case variation
        /// 지금 보고 있는 생성본을 새 결과로 교체.
        case replaceCurrent
    }

    enum ImageGenEngine: String {
        case codexCLI = "codex"  // codex image_generation — 키 불필요 (기본값)
        case openAIAPI = "api"   // OpenAI 호환 Images API — 키 필요
    }

    let history: HistoryStore

    init(history: HistoryStore) {
        self.history = history
    }

    /// 설정값 → 환경변수 순으로 API 키를 해석한다.
    var resolvedAPIKey: String {
        if !storedAPIKey.isEmpty { return storedAPIKey }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    /// 이미지 생성 키: 설정값 → OPENAI_API_KEY 환경변수.
    var resolvedImageGenKey: String {
        if !storedImageGenKey.isEmpty { return storedImageGenKey }
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }

    /// 영역 캡처 후 바로 분석.
    func captureAndAnalyze() {
        Task {
            NSApp.hide(nil)  // 우리 창 뒤 화면도 캡처할 수 있도록 잠시 숨김
            try? await Task.sleep(for: .milliseconds(300))
            let captured = await ScreenCapture.captureInteractive()
            NSApp.activate(ignoringOtherApps: true)
            guard let captured else { return }
            await handleCaptured(rawImageData: captured)
        }
    }

    @Published var showWindowPicker = false
    @Published var showFileImporter = false

    /// 창 선택 캡처: 열린 창들을 썸네일 그리드로 펼쳐 보여주고 클릭으로 선택.
    func captureSelectedWindowAndAnalyze() {
        bringToFront()
        showWindowPicker = true
    }

    /// 그리드에서 선택된 창을 캡처 후 분석. (-l 캡처는 창이 가려져 있어도 내용을 떠온다)
    func captureKnownWindowAndAnalyze(id: CGWindowID) {
        Task {
            guard let data = await ScreenCapture.captureWindow(id: id) else {
                errorMessage = "창 캡처에 실패했습니다. 창이 닫혔거나 화면 기록 권한을 확인하세요."
                return
            }
            await handleCaptured(rawImageData: data)
        }
    }

    /// 전역 단축키용: 마우스 커서 아래 창을 자동 인식해 그 창만 캡처 후 분석.
    /// 창을 못 찾으면 인터랙티브 영역 선택으로 폴백.
    func captureWindowUnderMouseAndAnalyze() {
        Task {
            let data: Data?
            if let windowID = WindowPicker.windowUnderMouse() {
                data = await ScreenCapture.captureWindow(id: windowID)
            } else {
                data = await ScreenCapture.captureInteractive()
            }
            guard let data else { return }
            bringToFront()
            await handleCaptured(rawImageData: data)
        }
    }

    /// "새 캡처" (⌘N): 보고 있던 결과·히스토리를 닫고 시작 화면으로 돌아간다.
    /// (히스토리 항목 자체는 삭제되지 않는다)
    func startNewCapture() {
        analysis = nil
        currentImageData = nil
        clearGeneratedImages()
        errorMessage = nil
        currentHistoryID = nil
    }

    /// 결과를 보여주기 위해 앱과 메인 창을 앞으로 가져온다.
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// 클립보드 이미지 분석.
    /// Finder에서 파일을 복사하면 클립보드에 '파일 아이콘' 이미지도 함께 들어가므로,
    /// 파일 URL이 있으면 반드시 원본 파일 내용을 먼저 읽는다.
    func analyzeFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            analyzeFile(at: url)
            return
        }
        guard let data = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff).flatMap(Self.tiffToPNG) else {
            errorMessage = "클립보드에 이미지가 없습니다."
            return
        }
        Task { await analyze(rawImageData: data) }
    }

    /// 파일/드롭 이미지 분석.
    func analyzeFile(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "파일을 읽을 수 없습니다: \(url.lastPathComponent)"
            return
        }
        Task { await analyze(rawImageData: data) }
    }

    /// 캡처 결과 공통 진입점: 옵션에 따라 바로 분석하거나, 이미지만 띄우고 대기한다.
    /// (파일 열기·클립보드·드롭은 사용자가 이미 본 이미지이므로 항상 즉시 분석)
    func handleCaptured(rawImageData: Data) async {
        errorMessage = nil
        guard let normalized = ImageProcessor.normalize(rawImageData) else {
            errorMessage = AnalyzerError.invalidImage.localizedDescription
            return
        }
        // 분석 여부와 상관없이 항목을 먼저 만든다 — 그래야 사이드바에서 언제든 되돌아올 수
        // 있고, 다른 화면을 보다가 캡처를 잃어버리지 않는다. 분석은 이 항목에 붙는다.
        let item = store(normalized)
        show(item)
        guard autoAnalyzeOnCapture else { return }
        await analyze(rawImageData: normalized.data, sourceHistoryID: item.id,
                      targetHistoryID: item.id)
    }

    /// 정규화한 이미지를 히스토리에 보관한다 (분석 전).
    private func store(_ normalized: (data: Data, mediaType: String)) -> HistoryItem {
        let ext = normalized.mediaType == "image/png" ? "png" : "jpg"
        return history.add(imageData: normalized.data, fileExtension: ext)
    }

    /// 보고 있는 항목이 아직 분석되지 않았는지 ('분석 시작' 화면 조건).
    var currentItemNeedsAnalysis: Bool {
        analysis == nil && currentImageData != nil && currentHistoryID != nil
    }

    /// '분석 시작' 버튼: 보고 있는(아직 분석 안 된) 항목의 프롬프트를 뽑는다.
    /// 다른 분석이 돌고 있어도 함께 진행된다.
    func analyzePending() {
        guard let data = currentImageData, let id = currentHistoryID, analysis == nil,
              !isAnalyzing(for: id) else { return }
        Task { await analyze(rawImageData: data, sourceHistoryID: id, targetHistoryID: id) }
    }

    /// 사이드바에서 아직 분석되지 않은 항목을 바로 분석한다.
    func analyzeItem(_ item: HistoryItem) {
        guard item.analysis == nil, !isAnalyzing(for: item.id),
              let data = originalImageData(for: item) else { return }
        let takesOver = currentHistoryID == item.id
        Task {
            await analyze(rawImageData: data, sourceHistoryID: item.id,
                          targetHistoryID: item.id, takesOverScreen: takesOver)
        }
    }

    /// 이미지를 분석해 새 히스토리 항목을 만든다.
    /// - sourceHistoryID: 재분석이면 원본 항목 (백그라운드로 돌며 화면을 비우지 않는다).
    /// - takesOverScreen: 새 캡처처럼 화면을 점유하고 스피너를 띄울지.
    /// 여러 건이 동시에 돌 수 있다 — 이미지마다 병렬.
    /// - targetHistoryID: 캡처 때 미리 만들어 둔 항목 (분석 결과를 여기에 붙인다).
    func analyze(rawImageData: Data, sourceHistoryID: UUID? = nil,
                 targetHistoryID: UUID? = nil,
                 takesOverScreen: Bool = true) async {
        errorMessage = nil
        guard let normalized = ImageProcessor.normalize(rawImageData) else {
            errorMessage = AnalyzerError.invalidImage.localizedDescription
            return
        }
        let selected = Backend(rawValue: backend) ?? .claudeCLI
        switch selected {
        case .claudeCLI, .codexCLI:
            break
        case .apiKey where resolvedAPIKey.isEmpty:
            errorMessage = AnalyzerError.missingAPIKey.localizedDescription
            return
        default:
            break
        }
        // 화면을 점유하는 분석만 현재 화면을 새 대상으로 갈아끼운다.
        // 재분석은 보고 있던 결과를 그대로 두고 뒤에서 돈다.
        if takesOverScreen {
            currentImageData = normalized.data
            analysis = nil
            clearGeneratedImages()
            currentHistoryID = targetHistoryID   // 캡처로 만들어 둔 항목이면 그대로 유지
        }
        let job = beginAnalysis(sourceHistoryID: sourceHistoryID,
                                takesOverScreen: takesOverScreen)
        defer { finishAnalysis(job) }
        do {
            let result: PromptAnalysis
            switch selected {
            case .claudeCLI:
                result = try await ClaudeCLIAnalyzer(claudePath: claudePath).analyze(
                    imageData: normalized.data, mediaType: normalized.mediaType)
            case .codexCLI:
                result = try await CodexCLIAnalyzer().analyze(
                    imageData: normalized.data, mediaType: normalized.mediaType)
            case .apiKey:
                let analyzer = PromptAnalyzer(apiKey: resolvedAPIKey, model: model)
                result = try await analyzer.analyze(imageData: normalized.data,
                                                    mediaType: normalized.mediaType)
            }
            // 캡처 때 만들어 둔 항목이 있으면 거기에 분석을 붙이고, 없으면 새로 만든다
            let item: HistoryItem
            if let target = targetHistoryID,
               let existing = history.items.first(where: { $0.id == target }) {
                history.update(id: target, analysis: result)
                item = existing
            } else {
                let ext = normalized.mediaType == "image/png" ? "png" : "jpg"
                item = history.add(imageData: normalized.data, fileExtension: ext,
                                   analysis: result)
            }
            // 그 사이 사용자가 다른 항목으로 옮겨갔으면 화면을 가로채지 않는다
            // (히스토리에는 이미 있으므로 사이드바에서 바로 열 수 있다)
            if shouldPresentResult(of: job) {
                show(item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 히스토리 항목을 현재 화면으로 불러온다. 그 항목에서 생성했던 이미지도 함께 되살린다.
    /// 넘겨받은 HistoryItem은 값 타입 스냅샷이라 수정 전 내용일 수 있으므로
    /// (사이드바 셀이 리렌더되지 않은 경우) 저장소의 최신 항목을 진실로 삼는다.
    func show(_ item: HistoryItem) {
        let latest = history.items.first(where: { $0.id == item.id }) ?? item
        analysis = latest.analysis
        currentImageData = try? Data(contentsOf: history.imageURL(for: item))
        errorMessage = nil
        // 대기 중인 캡처는 남겨 둔다 — 분석 전이라 히스토리에 없고,
        // 여기서 지우면 되찾을 방법이 없다 (배너로 돌아갈 수 있게 한다)
        currentHistoryID = item.id
        loadGeneratedImages(for: item.id)
    }

    /// 항목에 저장된 생성 이미지를 디스크에서 읽어 화면 상태에 채운다.
    /// 넘겨받은 HistoryItem은 값 타입 스냅샷이라 오래됐을 수 있으므로 저장소에서 다시 조회한다.
    /// 생성본이 있으면 **가장 최근 것을 원본과 나란히** 열어준다 —
    /// 이 항목을 다시 여는 이유는 대개 결과를 원본과 견주어 보기 위해서다.
    private func loadGeneratedImages(for id: UUID) {
        let fileNames = history.items.first(where: { $0.id == id })?.generatedImageFileNames ?? []
        generatedImages = fileNames.compactMap {
            try? Data(contentsOf: history.generatedImageURL(fileName: $0))
        }
        selectedGeneratedIndex = generatedImages.isEmpty ? nil : generatedImages.count - 1
        isComparingWithOriginal = !generatedImages.isEmpty
    }

    /// 화면의 생성 이미지 상태만 비운다 (디스크의 히스토리는 건드리지 않는다).
    private func clearGeneratedImages() {
        generatedImages = []
        selectedGeneratedIndex = nil
        isComparingWithOriginal = false
    }

    // MARK: - 분석 진행 상태 (병렬)

    var runningAnalysisCount: Int { runningAnalyses.count }

    /// 해당 히스토리 항목을 원본으로 하는 재분석이 돌고 있는지 (사이드바 표시용).
    func isAnalyzing(for id: UUID?) -> Bool {
        guard let id else { return false }
        return runningAnalyses.values.contains { $0.sourceHistoryID == id }
    }

    /// 화면을 점유한 분석이 돌고 있는지 (전체 화면 스피너용).
    var isAnalyzingForeground: Bool {
        runningAnalyses.values.contains { $0.takesOverScreen }
    }

    /// 기존 화면 코드와의 호환 — 화면에 스피너를 띄울 조건.
    var isAnalyzing: Bool { isAnalyzingForeground }

    /// 화면을 점유한 분석의 시작 시각 (경과 시간 표시용).
    var analysisStartedAt: Date? {
        runningAnalyses.values.filter(\.takesOverScreen).map(\.startedAt).min()
    }

    @discardableResult
    func beginAnalysis(sourceHistoryID: UUID?, takesOverScreen: Bool) -> AnalysisJob {
        let job = AnalysisJob(id: UUID(), startedAt: Date(),
                              sourceHistoryID: sourceHistoryID,
                              takesOverScreen: takesOverScreen)
        runningAnalyses[job.id] = job
        if takesOverScreen { foregroundAnalysisID = job.id }
        return job
    }

    func finishAnalysis(_ job: AnalysisJob) {
        runningAnalyses[job.id] = nil
        if foregroundAnalysisID == job.id, !runningAnalyses.values.contains(where: \.takesOverScreen) {
            foregroundAnalysisID = nil
        }
    }

    /// 결과를 화면에 띄워도 되는지 — 화면을 점유했던 분석이거나,
    /// 재분석을 시작한 그 항목을 사용자가 아직 보고 있을 때만.
    /// (그 사이 다른 항목으로 옮겨갔다면 화면을 가로채지 않는다)
    func shouldPresentResult(of job: AnalysisJob) -> Bool {
        // 화면을 점유했더라도, 그 사이 다른 캡처가 화면의 주인이 됐으면 물러난다
        if job.takesOverScreen { return job.id == foregroundAnalysisID }
        return job.sourceHistoryID != nil && job.sourceHistoryID == currentHistoryID
    }

    // MARK: - 생성 진행 상태 (항목별)

    /// 해당 히스토리 항목에서 이미지 생성이 돌고 있는지.
    func isGenerating(for id: UUID?) -> Bool {
        guard let id else { return false }
        return generatingHistoryIDs.contains(id)
    }

    /// 지금 보고 있는 항목이 생성 중인지 (하단 버튼·오버레이용).
    var isGeneratingImage: Bool { isGenerating(for: currentHistoryID) }

    /// 보고 있는 항목의 생성 시작 시각 — 생성 중인 항목으로 돌아와도 경과 시간이 이어진다.
    var generationStartedAt: Date? {
        guard let id = currentHistoryID else { return nil }
        return generationStartedAtByID[id]
    }

    func beginGeneration(for id: UUID) {
        generatingHistoryIDs.insert(id)
        generationStartedAtByID[id] = Date()
    }

    func finishGeneration(for id: UUID) {
        generatingHistoryIDs.remove(id)
        generationStartedAtByID[id] = nil
    }

    // MARK: - 오류 표시

    /// 지금 화면에 띄울 오류 — 전역 오류가 우선, 없으면 보고 있는 항목의 생성 오류.
    var visibleErrorMessage: String? {
        if let errorMessage { return errorMessage }
        guard let id = currentHistoryID else { return nil }
        return generationErrors[id]
    }

    func hasGenerationError(for id: UUID?) -> Bool {
        guard let id else { return false }
        return generationErrors[id] != nil
    }

    func setGenerationError(_ message: String, for id: UUID) {
        generationErrors[id] = message
    }

    // MARK: - 정책 거부 → 프롬프트 개선 제안

    func policyRejection(for id: UUID?) -> PolicyRejection? {
        guard let id else { return nil }
        return policyRejections[id]
    }

    /// 보고 있는 항목이 정책 거부 상태인지 (배너의 "개선점 보기" 노출 조건).
    var currentPolicyRejection: PolicyRejection? { policyRejection(for: currentHistoryID) }

    /// 보고 있는 항목의 개선안.
    var currentRevision: PromptRevision? {
        guard let id = currentHistoryID else { return nil }
        return revisions[id]
    }

    var isRevisingPrompt: Bool {
        guard let id = currentHistoryID else { return false }
        return revisingHistoryIDs.contains(id)
    }

    /// 생성 실패를 기록한다. 정책 거부면 어떤 프롬프트가 막혔는지도 남겨
    /// 나중에 "개선점 보기"를 누를 수 있게 한다.
    func recordGenerationFailure(_ error: Error, prompt: String,
                                 language: PromptAnalysis.PromptLanguage, for id: UUID) {
        setGenerationError(error.localizedDescription, for: id)
        if case AnalyzerError.contentPolicy(let detail) = error {
            policyRejections[id] = PolicyRejection(prompt: prompt, detail: detail,
                                                   language: language)
        }
    }

    func setRevision(_ revision: PromptRevision, for id: UUID) {
        revisions[id] = revision
    }

    /// 거부된 프롬프트를 분석 백엔드에 보내 문제 구절과 수정본을 받아온다.
    func requestPromptRevision() {
        guard let id = currentHistoryID, let rejection = policyRejections[id],
              !revisingHistoryIDs.contains(id) else { return }
        revisingHistoryIDs.insert(id)
        Task {
            defer { revisingHistoryIDs.remove(id) }
            do {
                let request = PromptRevisionAdvisor.prompt(originalPrompt: rejection.prompt,
                                                           rejection: rejection.detail)
                let raw = try await completeText(request)
                revisions[id] = try PromptRevisionAdvisor.parse(raw)
                if id == currentHistoryID { showingRevision = true }
            } catch {
                setGenerationError("개선안을 받지 못했습니다: \(error.localizedDescription)", for: id)
            }
        }
    }

    /// 개선안의 수정 프롬프트를 거부됐던 언어에 반영하고 거부 상태를 정리한다.
    func applyCurrentRevision() {
        guard let id = currentHistoryID, let revision = revisions[id],
              let rejection = policyRejections[id] else { return }
        applyEditedPrompt(revision.revisedPrompt, for: rejection.language)
        policyRejections[id] = nil
        generationErrors[id] = nil
        revisions[id] = nil
        showingRevision = false
    }

    /// 교체하고 곧바로 그 언어로 다시 생성한다.
    func applyCurrentRevisionAndRegenerate() {
        guard let id = currentHistoryID, let rejection = policyRejections[id],
              let revision = revisions[id] else { return }
        let language = rejection.language
        let prompt = revision.revisedPrompt
        applyCurrentRevision()
        generateImage(prompt: prompt, language: language, mode: .new)
    }

    /// 분석에 쓰는 백엔드로 텍스트 요청 1회.
    private func completeText(_ prompt: String,
                              schema: [String: Any] = PromptRevisionAdvisor.outputSchema) async throws -> String {
        switch Backend(rawValue: backend) ?? .claudeCLI {
        case .claudeCLI:
            return try await ClaudeCLIAnalyzer(claudePath: claudePath).complete(prompt: prompt)
        case .codexCLI:
            return try await CodexCLIAnalyzer().complete(prompt: prompt, schema: schema)
        case .apiKey:
            guard !resolvedAPIKey.isEmpty else { throw AnalyzerError.missingAPIKey }
            return try await PromptAnalyzer(apiKey: resolvedAPIKey, model: model)
                .complete(prompt: prompt, schema: schema)
        }
    }

    /// 배너의 닫기 버튼 — 지금 보이는 오류 하나만 지운다.
    func dismissVisibleError() {
        if errorMessage != nil {
            errorMessage = nil
            return
        }
        if let id = currentHistoryID { generationErrors[id] = nil }
    }

    // MARK: - 보기 모드

    /// 원본과 나란히 볼 수 있는 상태인지 (생성본 탭을 보고 있을 때만).
    var canCompare: Bool { selectedGeneratedImage != nil && currentImageData != nil }

    /// 보고 있는 생성본으로 프롬프트를 새로 뽑을 수 있는지 (원본은 이미 분석돼 있다).
    var canExtractPromptFromSelection: Bool { selectedGeneratedImage != nil }

    /// 현재 선택된 생성 이미지 (없으면 nil — 원본 보기 중).
    var selectedGeneratedImage: Data? {
        guard let index = selectedGeneratedIndex, generatedImages.indices.contains(index) else {
            return nil
        }
        return generatedImages[index]
    }

    /// 생성 결과를 만들어낸 히스토리 항목에 보관하고, 그 항목을 보고 있으면 화면에도 반영한다.
    /// (생성은 1분 가까이 걸리므로 그 사이 다른 항목으로 옮겨갔을 수 있다)
    /// replacing에 파일명을 주면 목록 끝에 추가하는 대신 그 자리를 교체한다.
    func storeGeneratedImage(_ data: Data, for historyID: UUID?, replacing fileName: String? = nil) {
        if let historyID {  // 성공했으니 지난 실패·거부 기록은 지운다
            generationErrors[historyID] = nil
            policyRejections[historyID] = nil
            revisions[historyID] = nil
        }
        guard let historyID else {
            // 히스토리에 없는 분석(있을 수 없지만 방어) — 메모리에만 유지한다
            generatedImages.append(data)
            selectedGeneratedIndex = generatedImages.count - 1
            return
        }
        if let fileName {
            // 교체 대상 자리를 파일명으로 찾는다 (다른 항목이 동시에 생성돼도 안 어긋난다)
            let slot = history.items.first(where: { $0.id == historyID })?
                .generatedImageFileNames.firstIndex(of: fileName)
            guard history.replaceGeneratedImage(id: historyID, fileName: fileName,
                                                data: data) != nil else {
                // 그 사이 지워졌으면 새 장으로 추가한다
                storeGeneratedImage(data, for: historyID)
                return
            }
            guard historyID == currentHistoryID, let slot,
                  generatedImages.indices.contains(slot) else { return }
            generatedImages[slot] = data
            selectedGeneratedIndex = slot
            return
        }
        history.addGeneratedImage(id: historyID, data: data)
        guard historyID == currentHistoryID else { return }
        generatedImages.append(data)
        selectedGeneratedIndex = generatedImages.count - 1
    }

    /// 보고 있는 생성본의 파일명 (교체 생성 대상 지정용).
    private var selectedGeneratedFileName: String? {
        guard let index = selectedGeneratedIndex, let id = currentHistoryID,
              let names = history.items.first(where: { $0.id == id })?.generatedImageFileNames,
              names.indices.contains(index) else { return nil }
        return names[index]
    }

    /// 보고 있는 항목의 생성 이미지 장수·용량 (삭제 전 안내용).
    var currentGeneratedImageCount: Int {
        currentHistoryItem?.generatedImageFileNames.count ?? 0
    }

    var currentGeneratedImagesByteSize: Int64 {
        guard let id = currentHistoryID else { return 0 }
        return history.generatedImagesByteSize(id: id)
    }

    /// 항목의 생성 이미지를 모두 지운다 (분석 결과와 원본 이미지는 남는다).
    /// id를 생략하면 보고 있는 항목.
    func deleteAllGeneratedImages(for id: UUID? = nil) {
        guard let target = id ?? currentHistoryID else { return }
        history.removeAllGeneratedImages(id: target)
        guard target == currentHistoryID else { return }  // 다른 항목이면 화면은 그대로
        generatedImages = []
        selectedGeneratedIndex = nil
        isComparingWithOriginal = false
    }

    /// 보고 있는 생성 이미지를 히스토리와 디스크에서 지운다.
    func deleteSelectedGeneratedImage() {
        guard let index = selectedGeneratedIndex, generatedImages.indices.contains(index) else {
            return
        }
        if let id = currentHistoryID,
           let item = history.items.first(where: { $0.id == id }),
           item.generatedImageFileNames.indices.contains(index) {
            history.removeGeneratedImage(id: id, fileName: item.generatedImageFileNames[index])
        }
        generatedImages.remove(at: index)
        selectedGeneratedIndex = generatedImages.isEmpty
            ? nil : Swift.min(index, generatedImages.count - 1)
    }

    /// 히스토리 항목을 지운다.
    /// 보고 있던 항목이면 화면(이미지·프롬프트·생성본)도 함께 비운다 —
    /// 저장소만 지우면 사라진 항목의 내용이 화면에 남는다.
    func deleteHistoryItem(_ item: HistoryItem) {
        let wasShowing = currentHistoryID == item.id
        history.delete(item)
        // 그 항목에 매달려 있던 상태도 함께 정리
        generationErrors[item.id] = nil
        policyRejections[item.id] = nil
        revisions[item.id] = nil
        finishGeneration(for: item.id)
        if wasShowing { startNewCapture() }
    }

    // MARK: - 원본 재분석

    /// 보고 있는 히스토리 항목 (재분석 대상).
    var currentHistoryItem: HistoryItem? {
        guard let id = currentHistoryID else { return nil }
        return history.items.first(where: { $0.id == id })
    }

    /// 항목에 저장된 원본 캡처 이미지.
    func originalImageData(for item: HistoryItem) -> Data? {
        try? Data(contentsOf: history.imageURL(for: item))
    }

    /// 원본 캡처 이미지로 프롬프트를 다시 뽑는다.
    /// 결과는 **새 히스토리 항목**이 된다 — 기존 분석과 사용자가 수정한 프롬프트는 그대로 남는다.
    func reanalyze(_ item: HistoryItem) {
        guard let data = originalImageData(for: item) else {
            errorMessage = "원본 이미지를 찾을 수 없어 다시 분석할 수 없습니다."
            return
        }
        // 재분석은 백그라운드 — 보고 있던 프롬프트를 스피너로 덮지 않는다.
        // 끝났을 때 그 항목을 계속 보고 있으면 새 결과로 전환된다.
        Task { await analyze(rawImageData: data, sourceHistoryID: item.id,
                             takesOverScreen: false) }
    }

    /// 보고 있는 항목을 다시 분석한다 (⌘R).
    func reanalyzeCurrent() {
        guard let item = currentHistoryItem else { return }
        reanalyze(item)
    }

    /// 편집한 프롬프트를 나머지 언어에 맞추는 중인 항목들.
    @Published private(set) var syncingPromptIDs: Set<UUID> = []

    var isSyncingPrompt: Bool {
        guard let id = currentHistoryID else { return false }
        return syncingPromptIDs.contains(id)
    }

    /// 프롬프트를 고치면 나머지 두 언어를 같은 내용으로 맞춘다.
    /// 이미지 생성은 영어 프롬프트를 쓰므로, 한국어로 고친 내용이 생성에 반영되려면
    /// 이 동기화가 필요하다.
    func syncEditedPrompt(_ text: String, from language: PromptAnalysis.PromptLanguage) {
        guard let id = currentHistoryID, !syncingPromptIDs.contains(id) else { return }
        syncingPromptIDs.insert(id)
        Task {
            defer { syncingPromptIDs.remove(id) }
            do {
                let raw = try await completeText(
                    PromptSync.prompt(edited: text, language: language),
                    schema: PromptSync.outputSchema)
                // 그 사이 사용자가 또 고쳤을 수 있으므로 저장소의 최신을 기준으로 반영한다
                guard let stored = history.items.first(where: { $0.id == id })?.analysis,
                      stored.prompt(for: language) == text else { return }
                let updated = try PromptSync.apply(raw, to: stored, edited: language)
                history.update(id: id, analysis: updated)
                if id == currentHistoryID { analysis = updated }
            } catch {
                setGenerationError(
                    "다른 언어 프롬프트를 맞추지 못했습니다: \(error.localizedDescription)", for: id)
            }
        }
    }

    /// 사용자가 수정한 프롬프트를 현재 분석과 히스토리에 반영한다.
    /// 저장소에 있는 최신 분석을 기준으로 **해당 언어만** 갈아끼운다 —
    /// 화면의 analysis가 낡았을 때 그것을 통째로 써서 다른 언어의 수정을
    /// 되돌려버리는 사고를 막는다.
    func applyEditedPrompt(_ prompt: String, for language: PromptAnalysis.PromptLanguage) {
        guard let analysis else { return }
        guard let id = currentHistoryID,
              let stored = history.items.first(where: { $0.id == id })?.analysis else {
            self.analysis = analysis.updating(prompt: prompt, for: language)
            return
        }
        let updated = stored.updating(prompt: prompt, for: language)
        history.update(id: id, analysis: updated)
        self.analysis = updated
    }

    /// 분석 결과로 이미지를 생성한다.
    /// - prompt: 결과 패널에서 보고 있는 언어의 프롬프트 (nil이면 영문).
    /// - mode: 새로 만들기 / 보고 있는 이미지 변형 / 보고 있는 생성본 교체.
    func generateImage(prompt: String? = nil,
                       language: PromptAnalysis.PromptLanguage = .english,
                       mode: GenerationMode = .new) {
        guard let analysis, let historyID = currentHistoryID else { return }
        guard !isGenerating(for: historyID) else { return }
        let text = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? prompt! : analysis.promptEn
        // 변형은 보고 있는 이미지(원본 또는 생성본)를, 교체는 대상 파일명을 지금 확정한다.
        let reference: Data? = mode == .variation
            ? (selectedGeneratedImage ?? currentImageData) : nil
        if mode == .variation && reference == nil { return }
        let replacingFileName: String? = mode == .replaceCurrent ? selectedGeneratedFileName : nil
        if mode == .replaceCurrent && replacingFileName == nil { return }

        errorMessage = nil
        generationErrors[historyID] = nil
        policyRejections[historyID] = nil
        beginGeneration(for: historyID)
        Task {
            defer { finishGeneration(for: historyID) }
            do {
                let data: Data
                let engine = ImageGenEngine(rawValue: imageGenEngine) ?? .codexCLI
                switch engine {
                case .codexCLI:
                    data = try await CodexImageGenerator()
                        .generate(prompt: text, referenceImage: reference)
                case .openAIAPI:
                    let generator = ImageGenerator(baseURL: imageGenBaseURL,
                                                   apiKey: resolvedImageGenKey,
                                                   model: imageGenModel)
                    data = try await generator.generate(prompt: text, referenceImage: reference)
                }
                storeGeneratedImage(data, for: historyID, replacing: replacingFileName)
            } catch {
                // 다른 항목을 보고 있어도 엉뚱한 화면에 뜨지 않도록 항목에 붙여 두고,
                // 정책 거부면 어떤 프롬프트가 막혔는지도 남겨 개선안을 요청할 수 있게 한다
                recordGenerationFailure(error, prompt: text, language: language, for: historyID)
            }
        }
    }

    /// 보고 있는 생성본을 새 입력 이미지로 삼아 프롬프트를 다시 뽑는다.
    /// 결과는 별도 히스토리 항목이 된다 (원본 분석은 그대로 남는다).
    func extractPromptFromSelection() {
        guard let data = selectedGeneratedImage else { return }
        Task { await analyze(rawImageData: data) }
    }

    private static func tiffToPNG(_ tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
