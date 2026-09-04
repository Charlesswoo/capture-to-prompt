import XCTest
import AppKit
@testable import CaptureToPrompt

@MainActor
final class AppStateTests: XCTestCase {
    private var tempDir: URL!
    private var store: HistoryStore!
    private var appState: AppState!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-appstate-tests-\(UUID().uuidString)")
        store = HistoryStore(directory: tempDir)
        appState = AppState(history: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        // @AppStorage는 UserDefaults.standard에 쓰므로 테스트 흔적 제거
        UserDefaults.standard.removeObject(forKey: "autoAnalyzeOnCapture")
    }

    private var sampleAnalysis: PromptAnalysis {
        PromptAnalysis(
            promptEn: "a cat", promptKo: "고양이", promptJa: "猫",
            breakdown: .init(subject: "cat", style: "photo", composition: "close-up",
                             lighting: "soft", colorPalette: "warm", mood: "calm",
                             medium: "photography", tags: ["cat"]))
    }

    /// 1x1 PNG — ImageProcessor.normalize를 통과하는 최소 이미지.
    private func tinyPNG() throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - 프롬프트 수정

    func testApplyEditedPromptUpdatesAnalysisAndHistory() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        appState.applyEditedPrompt("수정된 고양이", for: .korean)

        XCTAssertEqual(appState.analysis?.promptKo, "수정된 고양이")
        XCTAssertEqual(appState.analysis?.promptEn, "a cat")  // 다른 언어는 유지
        XCTAssertEqual(store.items.first?.analysis.promptKo, "수정된 고양이")

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.items.first?.analysis.promptKo, "수정된 고양이")
    }

    func testApplyEditedPromptPerLanguage() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        appState.applyEditedPrompt("an edited cat", for: .english)
        appState.applyEditedPrompt("編集された猫", for: .japanese)

        XCTAssertEqual(appState.analysis?.promptEn, "an edited cat")
        XCTAssertEqual(appState.analysis?.promptJa, "編集された猫")
        XCTAssertEqual(appState.analysis?.promptKo, "고양이")
    }

    // MARK: - 캡처 후 자동 분석 옵션

    func testHandleCapturedWithAutoAnalyzeOffStoresPendingWithoutAnalyzing() async throws {
        appState.autoAnalyzeOnCapture = false

        await appState.handleCaptured(rawImageData: try tinyPNG())

        XCTAssertFalse(appState.isAnalyzing)
        XCTAssertNil(appState.analysis)
        XCTAssertNotNil(appState.pendingImageData)
        XCTAssertNotNil(appState.currentImageData)  // 이미지는 화면에 표시
    }

    func testHandleCapturedWithInvalidImageReportsError() async {
        appState.autoAnalyzeOnCapture = false

        await appState.handleCaptured(rawImageData: Data([0, 1, 2]))

        XCTAssertNil(appState.pendingImageData)
        XCTAssertNotNil(appState.errorMessage)
    }

    // MARK: - 생성 이미지 보관 (히스토리 전환에도 유지)

    func testStoreGeneratedImageAppendsAndSelectsLatest() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.storeGeneratedImage(Data([8, 8]), for: item.id)

        XCTAssertEqual(appState.generatedImages, [Data([9, 9]), Data([8, 8])])
        XCTAssertEqual(appState.selectedGeneratedIndex, 1)
        XCTAssertEqual(appState.selectedGeneratedImage, Data([8, 8]))
    }

    func testGeneratedImagesSurviveHistorySwitch() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(a)
        appState.storeGeneratedImage(Data([9, 9]), for: a.id)

        appState.show(b)
        XCTAssertTrue(appState.generatedImages.isEmpty)
        XCTAssertNil(appState.selectedGeneratedIndex)

        appState.show(a)
        XCTAssertEqual(appState.generatedImages, [Data([9, 9])])
        // 생성본이 있으면 되돌아왔을 때 최신 생성본을 원본과 나란히 열어준다
        XCTAssertEqual(appState.selectedGeneratedIndex, 0)
        XCTAssertTrue(appState.isComparingWithOriginal)
    }

    func testGeneratedImagesReloadAfterRestart() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)

        let reloadedStore = HistoryStore(directory: tempDir)
        let reloadedState = AppState(history: reloadedStore)
        let reloadedItem = try XCTUnwrap(reloadedStore.items.first { $0.id == item.id })
        reloadedState.show(reloadedItem)

        XCTAssertEqual(reloadedState.generatedImages, [Data([9, 9])])
    }

    /// 생성(약 1분) 중에 다른 히스토리를 고르면, 결과는 원래 항목에만 저장돼야 한다.
    func testGeneratedImageGoesToOriginItemNotCurrentView() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(a)
        appState.show(b)  // 생성 중에 다른 항목으로 이동

        appState.storeGeneratedImage(Data([9, 9]), for: a.id)

        XCTAssertTrue(appState.generatedImages.isEmpty)  // 보고 있는 b 화면은 그대로
        appState.show(a)
        XCTAssertEqual(appState.generatedImages, [Data([9, 9])])
    }

    func testDeleteSelectedGeneratedImage() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.storeGeneratedImage(Data([8, 8]), for: item.id)
        appState.selectedGeneratedIndex = 0

        appState.deleteSelectedGeneratedImage()

        XCTAssertEqual(appState.generatedImages, [Data([8, 8])])
        XCTAssertEqual(store.items.first { $0.id == item.id }?.generatedImageFileNames.count, 1)
        XCTAssertEqual(appState.selectedGeneratedIndex, 0)

        appState.deleteSelectedGeneratedImage()
        XCTAssertTrue(appState.generatedImages.isEmpty)
        XCTAssertNil(appState.selectedGeneratedIndex)  // 남은 게 없으면 원본으로
    }

    func testStartNewCaptureClearsGeneratedImages() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)

        appState.startNewCapture()

        XCTAssertTrue(appState.generatedImages.isEmpty)
        XCTAssertNil(appState.selectedGeneratedIndex)
        // 화면만 비울 뿐 히스토리에 저장된 생성 이미지는 남는다
        XCTAssertEqual(store.items.first { $0.id == item.id }?.generatedImageFileNames.count, 1)
    }

    // MARK: - 항목별 동시 생성

    func testGenerationProgressIsPerHistoryItem() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")

        appState.beginGeneration(for: a.id)
        appState.beginGeneration(for: b.id)

        XCTAssertTrue(appState.isGenerating(for: a.id))
        XCTAssertTrue(appState.isGenerating(for: b.id))
        appState.show(a)
        XCTAssertTrue(appState.isGeneratingImage)  // 보고 있는 항목 기준

        appState.finishGeneration(for: a.id)
        XCTAssertFalse(appState.isGeneratingImage)
        XCTAssertTrue(appState.isGenerating(for: b.id))  // 다른 항목은 계속 진행
    }

    /// 생성 중인 항목으로 옮겨가면 그 항목의 경과 시간이 이어져 보여야 한다.
    func testGenerationStartTimeIsPerItem() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.beginGeneration(for: a.id)
        appState.show(a)

        XCTAssertNotNil(appState.generationStartedAt)
        appState.finishGeneration(for: a.id)
        XCTAssertNil(appState.generationStartedAt)
    }

    // MARK: - 탭 자리 교체 생성

    func testStoreGeneratedImageReplacingKeepsPositionAndSelection() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.storeGeneratedImage(Data([8, 8]), for: item.id)
        let names = try XCTUnwrap(store.items.first { $0.id == item.id }?.generatedImageFileNames)

        appState.storeGeneratedImage(Data([7, 7]), for: item.id, replacing: names[0])

        XCTAssertEqual(appState.generatedImages, [Data([7, 7]), Data([8, 8])])
        XCTAssertEqual(appState.selectedGeneratedIndex, 0)  // 교체한 자리를 계속 본다
    }

    // MARK: - 언어 탭 프롬프트

    func testPromptForLanguagePicksMatchingText() {
        let analysis = sampleAnalysis
        XCTAssertEqual(analysis.prompt(for: .korean), "고양이")
        XCTAssertEqual(analysis.prompt(for: .english), "a cat")
        XCTAssertEqual(analysis.prompt(for: .japanese), "猫")
    }

    // MARK: - 원본·생성본 나란히 보기

    func testCompareModeNeedsGeneratedSelection() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.isComparingWithOriginal = true
        XCTAssertFalse(appState.canCompare)  // 원본만 있으면 비교할 게 없다

        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        XCTAssertTrue(appState.canCompare)

        // 원본 탭으로 돌아가면 비교 상태는 자동으로 풀린다
        appState.selectedGeneratedIndex = nil
        XCTAssertFalse(appState.canCompare)
    }

    // MARK: - 생성본에서 프롬프트 추출

    func testGeneratedImageIsAnalyzableAsNewSource() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(try tinyPNG(), for: item.id)

        XCTAssertNotNil(appState.selectedGeneratedImage)
        XCTAssertTrue(appState.canExtractPromptFromSelection)

        appState.selectedGeneratedIndex = nil
        XCTAssertFalse(appState.canExtractPromptFromSelection)  // 원본은 이미 분석돼 있다
    }

    // MARK: - 생성 오류는 항목별로 (동시 생성 대응)

    func testGenerationErrorIsShownOnlyOnItsOwnItem() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(b)

        appState.setGenerationError("정책 위반", for: a.id)

        // b를 보고 있는 동안에는 a의 오류가 새어나오지 않는다
        XCTAssertNil(appState.visibleErrorMessage)
        XCTAssertTrue(appState.hasGenerationError(for: a.id))

        appState.show(a)
        XCTAssertEqual(appState.visibleErrorMessage, "정책 위반")
    }

    /// 두 항목이 동시에 실패해도 서로 덮어쓰지 않는다.
    func testGenerationErrorsDoNotOverwriteEachOther() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")

        appState.setGenerationError("A 실패", for: a.id)
        appState.setGenerationError("B 실패", for: b.id)

        appState.show(a)
        XCTAssertEqual(appState.visibleErrorMessage, "A 실패")
        appState.show(b)
        XCTAssertEqual(appState.visibleErrorMessage, "B 실패")
    }

    func testSuccessfulGenerationClearsThatItemsError() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.setGenerationError("일시 실패", for: item.id)

        appState.storeGeneratedImage(Data([9, 9]), for: item.id)

        XCTAssertNil(appState.visibleErrorMessage)
        XCTAssertFalse(appState.hasGenerationError(for: item.id))
    }

    func testDismissClearsOnlyTheVisibleError() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.setGenerationError("A 실패", for: a.id)
        appState.setGenerationError("B 실패", for: b.id)
        appState.show(a)

        appState.dismissVisibleError()

        XCTAssertNil(appState.visibleErrorMessage)
        XCTAssertFalse(appState.hasGenerationError(for: a.id))
        XCTAssertTrue(appState.hasGenerationError(for: b.id))  // 다른 항목 것은 남는다
    }

    /// 캡처·분석 같은 화면 전역 오류는 보고 있는 항목과 무관하게 그대로 보인다.
    func testGlobalErrorStillShows() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.errorMessage = "클립보드에 이미지가 없습니다."

        XCTAssertEqual(appState.visibleErrorMessage, "클립보드에 이미지가 없습니다.")
        appState.dismissVisibleError()
        XCTAssertNil(appState.visibleErrorMessage)
    }

    // MARK: - 정책 거부 → 프롬프트 개선 제안

    private var sampleRevision: PromptRevision {
        PromptRevision(
            summary: "실존 인물 이름이 문제입니다.",
            issues: [.init(phrase: "Emma Watson", reason: "실존 인물", suggestion: "young woman")],
            revisedPrompt: "a portrait of a young woman")
    }

    func testPolicyRejectionIsRecordedWithPromptAndLanguage() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        appState.recordGenerationFailure(AnalyzerError.contentPolicy("safety system"),
                                         prompt: "a cat with Emma Watson",
                                         language: .english, for: item.id)

        XCTAssertTrue(appState.hasGenerationError(for: item.id))
        let rejection = try XCTUnwrap(appState.policyRejection(for: item.id))
        XCTAssertEqual(rejection.prompt, "a cat with Emma Watson")
        XCTAssertEqual(rejection.detail, "safety system")
        XCTAssertEqual(rejection.language, .english)
    }

    /// 정책과 무관한 실패는 개선 제안 대상이 아니다.
    func testNonPolicyFailureIsNotOfferedForRevision() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")

        appState.recordGenerationFailure(AnalyzerError.apiError(status: 429, message: "slow down"),
                                         prompt: "a cat", language: .english, for: item.id)

        XCTAssertTrue(appState.hasGenerationError(for: item.id))
        XCTAssertNil(appState.policyRejection(for: item.id))
    }

    /// 개선 제안은 항목별로 남아, 다른 항목을 보다 돌아와도 그대로 있다.
    func testRevisionIsKeptPerItem() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.recordGenerationFailure(AnalyzerError.contentPolicy(nil),
                                         prompt: "p", language: .korean, for: a.id)
        appState.setRevision(sampleRevision, for: a.id)

        appState.show(b)
        XCTAssertNil(appState.currentRevision)
        appState.show(a)
        XCTAssertEqual(appState.currentRevision, sampleRevision)
    }

    /// 제안 적용: 거부됐던 언어의 프롬프트가 히스토리까지 갱신된다.
    func testApplyRevisionUpdatesThatLanguageAndHistory() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.recordGenerationFailure(AnalyzerError.contentPolicy(nil),
                                         prompt: "a cat", language: .english, for: item.id)
        appState.setRevision(sampleRevision, for: item.id)

        appState.applyCurrentRevision()

        XCTAssertEqual(appState.analysis?.promptEn, "a portrait of a young woman")
        XCTAssertEqual(appState.analysis?.promptKo, "고양이")  // 다른 언어는 그대로
        XCTAssertEqual(store.items.first { $0.id == item.id }?.analysis.promptEn,
                       "a portrait of a young woman")
        // 적용했으면 거부 상태와 배너는 정리된다
        XCTAssertNil(appState.policyRejection(for: item.id))
        XCTAssertFalse(appState.hasGenerationError(for: item.id))
    }

    /// 생성에 성공하면 그 항목의 거부 기록·제안도 함께 사라진다.
    func testSuccessClearsRejectionAndRevision() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.recordGenerationFailure(AnalyzerError.contentPolicy(nil),
                                         prompt: "a cat", language: .english, for: item.id)
        appState.setRevision(sampleRevision, for: item.id)

        appState.storeGeneratedImage(Data([9, 9]), for: item.id)

        XCTAssertNil(appState.policyRejection(for: item.id))
        XCTAssertNil(appState.currentRevision)
    }

    // MARK: - 수정한 프롬프트가 사라지는 문제 (2026-09-03 사용자 보고)

    /// 항목을 다시 열 때 오래된 스냅샷이 아니라 저장소의 최신 분석을 보여줘야 한다.
    /// (사이드바 셀이 리렌더되지 않으면 수정 전 HistoryItem이 그대로 넘어온다)
    func testShowUsesLatestAnalysisNotStaleSnapshot() throws {
        let stale = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                              fileExtension: "png")
        appState.show(stale)
        appState.applyEditedPrompt("내가 수정한 프롬프트", for: .korean)
        XCTAssertEqual(store.items.first?.analysis.promptKo, "내가 수정한 프롬프트")

        // 수정 전에 만들어진 스냅샷으로 다시 연다 (사이드바가 넘기는 값)
        appState.show(stale)

        XCTAssertEqual(appState.analysis?.promptKo, "내가 수정한 프롬프트",
                       "수정한 프롬프트가 옛 스냅샷으로 덮여 사라짐")
    }

    /// 옛 스냅샷으로 연 뒤 다른 언어를 고치면, 앞서 수정한 언어까지 되돌아가면 안 된다.
    func testEditAfterReopenDoesNotRevertEarlierEdit() throws {
        let stale = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                              fileExtension: "png")
        appState.show(stale)
        appState.applyEditedPrompt("한국어 수정본", for: .korean)

        appState.show(stale)                                   // 옛 스냅샷으로 재진입
        appState.applyEditedPrompt("english edit", for: .english)

        let saved = try XCTUnwrap(store.items.first?.analysis)
        XCTAssertEqual(saved.promptEn, "english edit")
        XCTAssertEqual(saved.promptKo, "한국어 수정본", "앞서 수정한 한국어가 되돌아감")
    }

    // MARK: - 원본 이미지 재분석

    func testOriginalImageDataReadsStoredFile() throws {
        let png = try tinyPNG()
        let item = store.add(analysis: sampleAnalysis, imageData: png, fileExtension: "png")

        XCTAssertEqual(appState.originalImageData(for: item), png)
    }

    /// 원본 파일이 사라졌으면 재분석할 수 없다고 알려야 한다.
    func testReanalyzeReportsMissingOriginal() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        try FileManager.default.removeItem(at: store.imageURL(for: item))

        XCTAssertNil(appState.originalImageData(for: item))
        appState.reanalyze(item)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertFalse(appState.isAnalyzing)
    }

    /// 보고 있는 항목이 없으면 재분석 대상도 없다.
    func testCurrentReanalyzableItemFollowsSelection() throws {
        XCTAssertNil(appState.currentHistoryItem)
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        XCTAssertEqual(appState.currentHistoryItem?.id, item.id)
        appState.startNewCapture()
        XCTAssertNil(appState.currentHistoryItem)
    }

    // MARK: - 생성 이미지 일괄 삭제

    func testDeleteAllGeneratedImagesClearsScreenState() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.storeGeneratedImage(Data([8, 8]), for: item.id)
        XCTAssertEqual(appState.selectedGeneratedIndex, 1)

        appState.deleteAllGeneratedImages()

        XCTAssertTrue(appState.generatedImages.isEmpty)
        XCTAssertNil(appState.selectedGeneratedIndex)   // 원본 보기로 돌아간다
        XCTAssertFalse(appState.isComparingWithOriginal)
        XCTAssertEqual(store.items.first { $0.id == item.id }?.generatedImageFileNames, [])
        XCTAssertNotNil(appState.analysis)              // 분석 결과는 그대로
    }

    /// 보고 있지 않은 항목의 생성본도 사이드바에서 정리할 수 있다.
    func testDeleteAllGeneratedImagesForOtherItemKeepsCurrentScreen() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(a)
        appState.storeGeneratedImage(Data([9, 9]), for: a.id)
        appState.storeGeneratedImage(Data([7, 7]), for: b.id)

        appState.deleteAllGeneratedImages(for: b.id)

        XCTAssertEqual(appState.generatedImages, [Data([9, 9])])  // 보고 있던 화면은 그대로
        XCTAssertEqual(store.items.first { $0.id == b.id }?.generatedImageFileNames, [])
    }

    func testGeneratedImageCountAndSizeForCurrentItem() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        XCTAssertEqual(appState.currentGeneratedImageCount, 0)

        appState.storeGeneratedImage(Data(repeating: 0, count: 1500), for: item.id)

        XCTAssertEqual(appState.currentGeneratedImageCount, 1)
        XCTAssertEqual(appState.currentGeneratedImagesByteSize, 1500)
    }

    // MARK: - 분석 병렬 실행 (2026-09-04 사용자 지적: 재추출이 전역으로 잠긴다)

    func testAnalysesRunInParallelPerItem() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")

        let jobA = appState.beginAnalysis(sourceHistoryID: a.id, takesOverScreen: false)
        let jobB = appState.beginAnalysis(sourceHistoryID: b.id, takesOverScreen: false)

        XCTAssertTrue(appState.isAnalyzing(for: a.id))
        XCTAssertTrue(appState.isAnalyzing(for: b.id))
        XCTAssertEqual(appState.runningAnalysisCount, 2)

        appState.finishAnalysis(jobA)
        XCTAssertFalse(appState.isAnalyzing(for: a.id))
        XCTAssertTrue(appState.isAnalyzing(for: b.id))   // 다른 항목은 계속 진행
        appState.finishAnalysis(jobB)
        XCTAssertEqual(appState.runningAnalysisCount, 0)
    }

    /// 재분석은 백그라운드 — 보고 있던 프롬프트가 스피너로 덮이면 안 된다.
    func testBackgroundAnalysisKeepsCurrentScreen() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        _ = appState.beginAnalysis(sourceHistoryID: item.id, takesOverScreen: false)

        XCTAssertNotNil(appState.analysis)              // 보던 결과 유지
        XCTAssertFalse(appState.isAnalyzingForeground)  // 전체 화면 스피너 없음
        XCTAssertTrue(appState.isAnalyzing(for: item.id))
    }

    /// 새 캡처는 화면을 점유해 스피너를 보여준다.
    func testForegroundAnalysisTakesOverScreen() throws {
        let job = appState.beginAnalysis(sourceHistoryID: nil, takesOverScreen: true)
        XCTAssertTrue(appState.isAnalyzingForeground)
        appState.finishAnalysis(job)
        XCTAssertFalse(appState.isAnalyzingForeground)
    }

    /// 재분석 도중 다른 항목으로 옮겨갔으면 결과가 화면을 가로채면 안 된다.
    func testBackgroundResultDoesNotHijackScreenAfterNavigatingAway() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(a)
        let job = appState.beginAnalysis(sourceHistoryID: a.id, takesOverScreen: false)

        appState.show(b)                                  // 사용자가 다른 항목으로 이동
        XCTAssertFalse(appState.shouldPresentResult(of: job))

        appState.show(a)                                  // 원래 항목으로 돌아오면
        XCTAssertTrue(appState.shouldPresentResult(of: job))
    }

    /// 진행 중 분석이 있어도 새 분석을 걸 수 있다 (분석 대기 버튼은 예외 없이).
    func testCanStartAnotherAnalysisWhileOneRuns() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        _ = appState.beginAnalysis(sourceHistoryID: item.id, takesOverScreen: false)
        let second = appState.beginAnalysis(sourceHistoryID: nil, takesOverScreen: true)
        XCTAssertEqual(appState.runningAnalysisCount, 2)
        appState.finishAnalysis(second)
        XCTAssertEqual(appState.runningAnalysisCount, 1)
    }

    // MARK: - 히스토리 항목 삭제 (2026-09-04 사용자 버그 리포트)

    /// 보고 있던 항목을 지우면 화면(이미지·프롬프트)도 함께 비워져야 한다.
    func testDeletingShownItemClearsScreen() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        XCTAssertNotNil(appState.analysis)

        appState.deleteHistoryItem(item)

        XCTAssertNil(appState.analysis, "삭제했는데 프롬프트가 남아 있음")
        XCTAssertNil(appState.currentImageData, "삭제했는데 이미지가 남아 있음")
        XCTAssertNil(appState.currentHistoryItem)
        XCTAssertTrue(appState.generatedImages.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
    }

    /// 다른 항목을 보는 중에 지우면 보던 화면은 그대로여야 한다.
    func testDeletingOtherItemKeepsScreen() throws {
        let a = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(), fileExtension: "png")
        appState.show(a)

        appState.deleteHistoryItem(b)

        XCTAssertNotNil(appState.analysis)
        XCTAssertEqual(appState.currentHistoryItem?.id, a.id)
        XCTAssertEqual(store.items.count, 1)
    }

    /// 삭제한 항목에 매달린 상태(오류·거부 기록·개선안·진행 표시)도 함께 정리된다.
    func testDeletingItemClearsItsPendingState() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.recordGenerationFailure(AnalyzerError.contentPolicy("safety"),
                                         prompt: "p", language: .english, for: item.id)
        appState.setRevision(PromptRevision(summary: "s", issues: [], revisedPrompt: "r"),
                             for: item.id)
        appState.beginGeneration(for: item.id)

        appState.deleteHistoryItem(item)

        XCTAssertFalse(appState.hasGenerationError(for: item.id))
        XCTAssertNil(appState.policyRejection(for: item.id))
        XCTAssertFalse(appState.isGenerating(for: item.id))
    }

    // MARK: - 항목을 열 때 생성본이 있으면 바로 비교 (2026-09-04 사용자 요청)

    func testShowOpensComparisonWhenGeneratedImagesExist() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.storeGeneratedImage(Data([8, 8]), for: item.id)

        appState.show(item)   // 다시 열기

        XCTAssertEqual(appState.selectedGeneratedIndex, 1, "가장 최근 생성본을 골라야 한다")
        XCTAssertTrue(appState.isComparingWithOriginal, "생성본이 있으면 바로 비교로 연다")
        XCTAssertTrue(appState.canCompare)
    }

    /// 생성본이 없으면 원본만 — 비교할 대상이 없다.
    func testShowStaysOnOriginalWithoutGeneratedImages() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)

        XCTAssertNil(appState.selectedGeneratedIndex)
        XCTAssertFalse(appState.isComparingWithOriginal)
    }

    /// 새 분석·새 캡처는 비교할 생성본이 없으므로 원본 보기로 시작한다.
    func testStartNewCaptureLeavesComparisonOff() throws {
        let item = store.add(analysis: sampleAnalysis, imageData: try tinyPNG(),
                             fileExtension: "png")
        appState.show(item)
        appState.storeGeneratedImage(Data([9, 9]), for: item.id)
        appState.show(item)
        XCTAssertTrue(appState.isComparingWithOriginal)

        appState.startNewCapture()

        XCTAssertFalse(appState.isComparingWithOriginal)
        XCTAssertNil(appState.selectedGeneratedIndex)
    }
}
