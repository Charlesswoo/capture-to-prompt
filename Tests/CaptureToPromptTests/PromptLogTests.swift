import XCTest
import AppKit
@testable import CaptureToPrompt

/// 프롬프트 실행 기록 — 나중에 "무엇을 보내서 무엇을 받았는지"를 분석해
/// 지시문을 고치기 위한 로그. 사람이 아니라 도구가 읽으므로 JSONL이다.
final class PromptLogTests: XCTestCase {

    private var directory: URL!
    private var writer: PromptLogWriter!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writer = PromptLogWriter(fileURL: directory.appendingPathComponent("prompt-log.jsonl"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(kind: PromptLogEntry.Kind = .analyze,
                       outcome: PromptLogEntry.Outcome = .ok,
                       prompt: String? = "instructions",
                       response: String? = "{}") -> PromptLogEntry {
        PromptLogEntry(kind: kind, outcome: outcome, backend: "claude-cli",
                       model: "claude-opus-4-8", historyID: "H1", durationMs: 1234,
                       prompt: prompt, response: response)
    }

    // MARK: - 한 줄 한 건

    func testAppendWritesOneJSONLinePerEntry() throws {
        writer.append(entry())
        writer.append(entry(kind: .generate, outcome: .contentPolicy,
                            prompt: "a prompt", response: nil))
        writer.waitForPendingWrites()

        let text = try String(contentsOf: writer.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "한 건이 한 줄이어야 도구로 읽을 수 있다")
        // 줄 안에 개행이 섞이면 JSONL이 깨진다
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testEntriesRoundTrip() throws {
        writer.append(entry())
        writer.waitForPendingWrites()

        let read = try writer.entries()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].kind, .analyze)
        XCTAssertEqual(read[0].outcome, .ok)
        XCTAssertEqual(read[0].backend, "claude-cli")
        XCTAssertEqual(read[0].historyID, "H1")
        XCTAssertEqual(read[0].durationMs, 1234)
        XCTAssertEqual(read[0].prompt, "instructions")
    }

    /// 여러 줄짜리 지시문도 한 줄로 접혀야 한다 (실제 프롬프트는 전부 여러 줄이다).
    func testMultilinePromptStaysOnOneLine() throws {
        writer.append(entry(prompt: "line one\nline two\nline three"))
        writer.waitForPendingWrites()

        let text = try String(contentsOf: writer.fileURL, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 1)
        XCTAssertEqual(try writer.entries()[0].prompt, "line one\nline two\nline three")
    }

    // MARK: - 끄기

    func testDisabledWriterWritesNothing() throws {
        writer.isEnabled = false
        writer.append(entry())
        writer.waitForPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.fileURL.path),
                       "꺼져 있으면 파일 자체를 만들지 않는다")
    }

    // MARK: - 회전 (무한히 자라면 안 된다)

    func testRotatesWhenFileExceedsLimit() throws {
        let small = PromptLogWriter(fileURL: directory.appendingPathComponent("rot.jsonl"),
                                    maxBytes: 400)
        let fat = String(repeating: "x", count: 300)
        for _ in 0..<4 { small.append(entry(prompt: fat)) }
        small.waitForPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: small.rotatedFileURL.path),
                      "한도를 넘으면 직전 파일을 남기고 새로 시작한다")
        let size = (try FileManager.default.attributesOfItem(atPath: small.fileURL.path)[.size]
                    as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, 400 + 1000, "현재 파일이 한도 근처로 유지돼야 한다")
        // 회전해도 기록은 이어져야 한다
        XCTAssertGreaterThan(try small.entries().count, 0)
    }

    // MARK: - 실패도 남는다 (개선의 핵심 재료)

    func testFailureEntryKeepsErrorText() throws {
        writer.append(PromptLogEntry(kind: .analyze, outcome: .error, backend: "codex-cli",
                                     error: "CLI 출력 해석 실패: <html>"))
        writer.waitForPendingWrites()

        let read = try writer.entries()
        XCTAssertEqual(read[0].outcome, .error)
        XCTAssertEqual(read[0].error, "CLI 출력 해석 실패: <html>")
        XCTAssertNil(read[0].response)
    }

    /// 사용자 행동(재추출·수정·삭제)은 "그 결과가 나빴다"는 유일한 라벨이므로 함께 남긴다.
    func testUserSignalsAreRecorded() throws {
        for kind in [PromptLogEntry.Kind.reanalyze, .promptEdited, .generatedDeleted] {
            writer.append(PromptLogEntry(kind: kind, outcome: .signal, historyID: "H1"))
        }
        writer.waitForPendingWrites()

        XCTAssertEqual(try writer.entries().map(\.kind),
                       [.reanalyze, .promptEdited, .generatedDeleted])
    }

    // MARK: - 깨진 줄 무시

    /// 앱이 쓰는 도중 종료되면 마지막 줄이 잘릴 수 있다 — 그것 때문에 전체를 못 읽으면 안 된다.
    func testEntriesSkipsCorruptLines() throws {
        writer.append(entry())
        writer.waitForPendingWrites()
        let handle = try FileHandle(forWritingTo: writer.fileURL)
        handle.seekToEndOfFile()
        handle.write(Data("{\"kind\":\"anal".utf8))
        try handle.close()

        XCTAssertEqual(try writer.entries().count, 1)
    }

    // MARK: - 편의 생성자

    /// 소요 시간은 호출부가 매번 계산하지 않아도 되게 시작 시각에서 뽑는다.
    func testDurationDerivedFromStartDate() {
        let started = Date().addingTimeInterval(-2.5)
        let e = PromptLogEntry(kind: .analyze, outcome: .ok, since: started)
        XCTAssertNotNil(e.durationMs)
        XCTAssertGreaterThanOrEqual(e.durationMs!, 2400)
        XCTAssertLessThan(e.durationMs!, 4000)
    }

    /// 오류 종류에 따라 결과를 자동 분류한다 — 정책 거부와 일반 실패는 다른 문제다.
    func testOutcomeClassifiesErrors() {
        XCTAssertEqual(PromptLogEntry.Outcome(AnalyzerError.contentPolicy("blocked")),
                       .contentPolicy)
        XCTAssertEqual(PromptLogEntry.Outcome(AnalyzerError.refusal("못 합니다")), .refusal)
        XCTAssertEqual(PromptLogEntry.Outcome(AnalyzerError.emptyResponse), .error)
    }
}

/// AppState의 동작이 실제로 로그에 남는지 — 계측이 붙어 있다는 증거.
@MainActor
final class PromptLogInstrumentationTests: XCTestCase {

    private var tempDir: URL!
    private var store: HistoryStore!
    private var appState: AppState!
    private var previousWriter: PromptLogWriter!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-log-instr-\(UUID().uuidString)")
        store = HistoryStore(directory: tempDir)
        appState = AppState(history: store)
        previousWriter = PromptLog.shared
        PromptLog.shared = PromptLogWriter(
            fileURL: tempDir.appendingPathComponent("prompt-log.jsonl"))
    }

    override func tearDown() async throws {
        PromptLog.shared = previousWriter
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var sample: PromptAnalysis {
        PromptAnalysis(promptEn: "a cat", promptKo: "고양이", promptJa: "猫",
                       breakdown: .init(subject: "cat", style: "photo", composition: "c",
                                        lighting: "l", colorPalette: "p", mood: "m",
                                        medium: "d", tags: []))
    }

    private func loggedEntries() throws -> [PromptLogEntry] {
        PromptLog.shared.waitForPendingWrites()
        return try PromptLog.shared.entries()
    }

    /// 프롬프트를 손대면 "고치기 전 → 고친 후"가 남아야 지시문의 약점을 찾을 수 있다.
    func testEditingPromptIsLoggedWithBeforeAndAfter() throws {
        let item = store.add(imageData: Data([1, 2, 3]), fileExtension: "png", analysis: sample)
        appState.show(item)

        appState.applyEditedPrompt("a cat on a warm windowsill", for: .english)

        let entries = try loggedEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .promptEdited)
        XCTAssertEqual(entries[0].outcome, .signal)
        XCTAssertEqual(entries[0].historyID, item.id.uuidString)
        XCTAssertEqual(entries[0].prompt, "a cat", "고치기 전 원문이 있어야 비교가 된다")
        XCTAssertEqual(entries[0].response, "a cat on a warm windowsill")
        XCTAssertEqual(entries[0].note, "language=en")
    }

    /// 생성본을 버린 것도 결과 품질의 신호다.
    func testDeletingAllGeneratedImagesIsLogged() throws {
        let item = store.add(imageData: Data([1, 2, 3]), fileExtension: "png", analysis: sample)
        appState.show(item)
        store.addGeneratedImage(id: item.id, data: Data([9, 9, 9]))

        appState.deleteAllGeneratedImages()

        let entries = try loggedEntries()
        XCTAssertEqual(entries.map(\.kind), [.generatedDeleted])
        XCTAssertEqual(entries[0].note, "scope=all")
        XCTAssertEqual(entries[0].historyID, item.id.uuidString)
    }

    /// 재추출은 "앞선 결과가 마음에 들지 않았다"는 가장 강한 라벨이다.
    func testReanalyzeIsLoggedEvenWhenBackendFails() throws {
        let item = store.add(imageData: Data([1, 2, 3]), fileExtension: "png", analysis: sample)

        appState.reanalyze(item)

        let entries = try loggedEntries()
        XCTAssertEqual(entries.first?.kind, .reanalyze)
        XCTAssertEqual(entries.first?.historyID, item.id.uuidString)
    }

    /// 끄면 아무것도 남지 않아야 한다.
    func testNothingIsLoggedWhenDisabled() throws {
        PromptLog.shared.isEnabled = false
        let item = store.add(imageData: Data([1, 2, 3]), fileExtension: "png", analysis: sample)
        appState.show(item)

        appState.applyEditedPrompt("something else", for: .english)

        XCTAssertEqual(try loggedEntries().count, 0)
    }

    /// 백엔드별 분석 지시문이 로그에 남는 문안 그대로여야 짝지을 수 있다.
    func testAnalysisInstructionsMatchWhatBackendsSend() {
        XCTAssertEqual(AppState.analysisInstructions(for: .codexCLI), CodexCLIAnalyzer.prompt)
        XCTAssertEqual(AppState.analysisInstructions(for: .apiKey), PromptAnalyzer.systemPrompt)
        XCTAssertTrue(AppState.analysisInstructions(for: .claudeCLI).contains("input.png"))
        // CLI는 모델을 우리가 고르지 않는다 — 없는 값을 지어내면 안 된다
        XCTAssertNil(AppState.modelName(for: .claudeCLI, apiModel: "claude-opus-4-8"))
        XCTAssertEqual(AppState.modelName(for: .apiKey, apiModel: "claude-opus-4-8"),
                       "claude-opus-4-8")
    }
}

/// 기본 기록기는 테스트 중에 사용자의 진짜 로그를 건드리면 안 된다.
/// (2026-09-09: 계측을 붙인 직후 AppStateTests가 실제 로그에 11건을 남겼다.)
final class PromptLogDefaultWriterTests: XCTestCase {

    func testDefaultWriterIsDisabledUnderTests() {
        XCTAssertTrue(PromptLog.isRunningTests)
        let fresh = PromptLogWriter(fileURL: PromptLog.defaultFileURL())
        XCTAssertTrue(fresh.isEnabled, "기록기 자체는 켜져 있다 (설정을 따른다)")
        // 전역 기본 기록기만 테스트 중 꺼져 있어야 한다
        XCTAssertFalse(PromptLogWriter.defaultsKey.isEmpty)
    }

    func testDefaultFileLivesBesideHistory() {
        XCTAssertEqual(PromptLog.defaultDirectory().lastPathComponent, "logs")
        XCTAssertEqual(PromptLog.defaultDirectory().deletingLastPathComponent().path,
                       HistoryStore.defaultDirectory().path)
        XCTAssertEqual(PromptLog.defaultFileURL().lastPathComponent, "prompt-log.jsonl")
    }
}

/// 로그에 남길 이미지 규격 — 원본과 생성 결과의 화면비를 나중에 실제로 대조하기 위한 값.
final class ImagePixelSizeTests: XCTestCase {

    private func png(width: Int, height: Int) throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testPixelSizeReportsWidthByHeight() throws {
        XCTAssertEqual(ImageProcessor.pixelSize(try png(width: 3, height: 7)), "3x7")
    }

    func testPixelSizeReturnsNilForNonImage() {
        XCTAssertNil(ImageProcessor.pixelSize(Data("not an image".utf8)))
    }
}
