import XCTest
@testable import CaptureToPrompt

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var sampleAnalysis: PromptAnalysis {
        PromptAnalysis(
            promptEn: "a cat", promptKo: "고양이", promptJa: "猫",
            breakdown: .init(subject: "cat", style: "photo", composition: "close-up",
                             lighting: "soft", colorPalette: "warm", mood: "calm",
                             medium: "photography", tags: ["cat"]))
    }

    func testAddPersistsAndReloads() throws {
        let store = HistoryStore(directory: tempDir)
        let imageData = Data([1, 2, 3, 4])
        let item = store.add(analysis: sampleAnalysis, imageData: imageData, fileExtension: "png")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: item)), imageData)

        // 새 인스턴스로 로드해도 유지되는지 (ISO8601 저장으로 밀리초는 잘림)
        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.items.count, 1)
        let loaded = try XCTUnwrap(reloaded.items.first)
        XCTAssertEqual(loaded.id, item.id)
        XCTAssertEqual(loaded.imageFileName, item.imageFileName)
        XCTAssertEqual(loaded.analysis, item.analysis)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970,
                       item.createdAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testDeleteRemovesItemAndImage() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([9]), fileExtension: "png")
        let imageURL = store.imageURL(for: item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))

        store.delete(item)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertTrue(reloaded.items.isEmpty)
    }

    func testUpdateAnalysisPersists() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")

        var edited = sampleAnalysis
        edited.promptKo = "수정된 고양이"
        store.update(id: item.id, analysis: edited)

        XCTAssertEqual(store.items.first?.analysis.promptKo, "수정된 고양이")

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.items.first?.analysis.promptKo, "수정된 고양이")
    }

    func testUpdateUnknownIDIsNoOp() {
        let store = HistoryStore(directory: tempDir)
        store.add(analysis: sampleAnalysis, imageData: Data([1]))
        store.update(id: UUID(), analysis: sampleAnalysis)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.analysis, sampleAnalysis)
    }

    func testNewestFirstOrdering() {
        let store = HistoryStore(directory: tempDir)
        store.add(analysis: sampleAnalysis, imageData: Data([1]))
        let second = store.add(analysis: sampleAnalysis, imageData: Data([2]))
        XCTAssertEqual(store.items.first?.id, second.id)
    }

    // MARK: - 생성 이미지 보관

    func testAddGeneratedImagePersistsAndReloads() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1, 2, 3]),
                             fileExtension: "png")

        let first = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([9, 9])))
        let second = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([8, 8])))

        XCTAssertEqual(store.items.first?.generatedImageFileNames, [first, second])
        XCTAssertEqual(try Data(contentsOf: store.generatedImageURL(fileName: first)), Data([9, 9]))

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.items.first?.generatedImageFileNames, [first, second])
    }

    func testRemoveGeneratedImageDeletesFileAndEntry() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        let first = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([9])))
        let second = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([8])))

        store.removeGeneratedImage(id: item.id, fileName: first)

        XCTAssertEqual(store.items.first?.generatedImageFileNames, [second])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.generatedImageURL(fileName: first).path))
    }

    func testDeleteItemRemovesGeneratedImageFiles() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        let generated = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([9])))
        let stored = try XCTUnwrap(store.items.first)

        store.delete(stored)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.generatedImageURL(fileName: generated).path))
    }

    /// 구버전 history.json(생성 이미지 필드 없음)도 그대로 읽혀야 한다.
    func testLegacyIndexWithoutGeneratedFieldDecodes() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let legacyItem: [String: Any] = [
            "id": UUID().uuidString,
            "createdAt": "2026-01-01T00:00:00Z",
            "imageFileName": "a.png",
            "analysis": [
                "prompt_en": "a cat", "prompt_ko": "고양이", "prompt_ja": "猫",
                "breakdown": ["subject": "cat", "style": "photo", "composition": "close-up",
                              "lighting": "soft", "color_palette": "warm", "mood": "calm",
                              "medium": "photography", "tags": ["cat"]],
            ],
        ]
        let json = try JSONSerialization.data(withJSONObject: [legacyItem])
        try json.write(to: tempDir.appendingPathComponent("history.json"))

        let store = HistoryStore(directory: tempDir)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.generatedImageFileNames, [])
    }

    /// 탭 자리 교체: 목록 순서를 유지한 채 그 자리 파일만 바뀐다.
    func testReplaceGeneratedImageKeepsPosition() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        let first = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([9])))
        let second = try XCTUnwrap(store.addGeneratedImage(id: item.id, data: Data([8])))

        let replaced = try XCTUnwrap(
            store.replaceGeneratedImage(id: item.id, fileName: first, data: Data([7])))

        let names = try XCTUnwrap(store.items.first?.generatedImageFileNames)
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(names[0], replaced)          // 같은 자리
        XCTAssertEqual(names[1], second)            // 뒤 항목은 그대로
        XCTAssertNotEqual(replaced, first)
        XCTAssertEqual(try Data(contentsOf: store.generatedImageURL(fileName: replaced)), Data([7]))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.generatedImageURL(fileName: first).path))
    }

    /// 교체 대상이 이미 사라졌으면(다른 곳에서 삭제) 조용히 무시한다.
    func testReplaceGeneratedImageReturnsNilForUnknownFile() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        XCTAssertNil(store.replaceGeneratedImage(id: item.id, fileName: "없음.png",
                                                 data: Data([7])))
    }

    // MARK: - 생성 이미지 일괄 삭제

    func testRemoveAllGeneratedImagesClearsFilesButKeepsItem() throws {
        let store = HistoryStore(directory: tempDir)
        let a = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        let b = store.add(analysis: sampleAnalysis, imageData: Data([2]), fileExtension: "png")
        let a1 = try XCTUnwrap(store.addGeneratedImage(id: a.id, data: Data([9])))
        let a2 = try XCTUnwrap(store.addGeneratedImage(id: a.id, data: Data([8])))
        let b1 = try XCTUnwrap(store.addGeneratedImage(id: b.id, data: Data([7])))

        let removed = store.removeAllGeneratedImages(id: a.id)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(store.items.first { $0.id == a.id }?.generatedImageFileNames, [])
        // 히스토리 항목과 원본 이미지는 남는다
        XCTAssertNotNil(store.items.first { $0.id == a.id })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.imageURL(for: a).path))
        for name in [a1, a2] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: store.generatedImageURL(fileName: name).path))
        }
        // 다른 항목의 생성본은 그대로
        XCTAssertEqual(store.items.first { $0.id == b.id }?.generatedImageFileNames, [b1])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.generatedImageURL(fileName: b1).path))

        let reloaded = HistoryStore(directory: tempDir)
        XCTAssertEqual(reloaded.items.first { $0.id == a.id }?.generatedImageFileNames, [])
    }

    func testRemoveAllGeneratedImagesOnEmptyItemIsNoOp() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        XCTAssertEqual(store.removeAllGeneratedImages(id: item.id), 0)
    }

    /// 삭제 전 사용자에게 보여줄 용량.
    func testGeneratedImagesByteSize() throws {
        let store = HistoryStore(directory: tempDir)
        let item = store.add(analysis: sampleAnalysis, imageData: Data([1]), fileExtension: "png")
        XCTAssertEqual(store.generatedImagesByteSize(id: item.id), 0)

        store.addGeneratedImage(id: item.id, data: Data(repeating: 0, count: 1000))
        store.addGeneratedImage(id: item.id, data: Data(repeating: 0, count: 2000))

        XCTAssertEqual(store.generatedImagesByteSize(id: item.id), 3000)
    }
}
