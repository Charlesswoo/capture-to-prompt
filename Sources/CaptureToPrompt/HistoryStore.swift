import Foundation

/// 분석 히스토리 저장소.
/// <디렉터리>/history.json 에 메타데이터, <디렉터리>/images/ 에 이미지 원본,
/// <디렉터리>/generated/ 에 항목별 생성 이미지를 둔다.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [HistoryItem] = []

    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var imagesDirectory: URL { directory.appendingPathComponent("images") }
    private var generatedDirectory: URL { directory.appendingPathComponent("generated") }

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CaptureToPrompt")
    }

    init(directory: URL = HistoryStore.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? Self.decoder().decode([HistoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    @discardableResult
    func add(analysis: PromptAnalysis, imageData: Data, fileExtension: String = "jpg") -> HistoryItem {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension)"
        do {
            try imageData.write(to: imagesDirectory.appendingPathComponent(fileName))
        } catch {
            NSLog("HistoryStore: 이미지 저장 실패 %@ — %@", fileName, error.localizedDescription)
        }
        let item = HistoryItem(id: id, createdAt: Date(), imageFileName: fileName, analysis: analysis)
        items.insert(item, at: 0)
        persist()
        return item
    }

    /// 항목의 분석 결과를 교체한다 (프롬프트 수정 반영). 없는 id면 무시.
    func update(id: UUID, analysis: PromptAnalysis) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].analysis = analysis
        persist()
    }

    /// 이 항목에서 생성한 이미지를 파일로 저장하고 목록 끝에 추가한다.
    /// 저장에 성공하면 파일명을, 없는 id거나 쓰기 실패면 nil을 돌려준다.
    @discardableResult
    func addGeneratedImage(id: UUID, data: Data) -> String? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let fileName = "\(id.uuidString)-\(UUID().uuidString).png"
        do {
            try data.write(to: generatedImageURL(fileName: fileName))
        } catch {
            NSLog("HistoryStore: 생성 이미지 저장 실패 %@ — %@", fileName, error.localizedDescription)
            return nil
        }
        items[index].generatedImageFileNames.append(fileName)
        persist()
        return fileName
    }

    /// 생성 이미지 한 장을 같은 자리에서 새 이미지로 바꾼다 (탭 자리 교체 생성).
    /// 인덱스가 아니라 파일명으로 찾으므로 다른 항목이 동시에 생성돼도 어긋나지 않는다.
    /// 대상이 이미 사라졌으면 nil.
    @discardableResult
    func replaceGeneratedImage(id: UUID, fileName: String, data: Data) -> String? {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let slot = items[index].generatedImageFileNames.firstIndex(of: fileName) else {
            return nil
        }
        let newName = "\(id.uuidString)-\(UUID().uuidString).png"
        do {
            try data.write(to: generatedImageURL(fileName: newName))
        } catch {
            NSLog("HistoryStore: 생성 이미지 교체 실패 %@ — %@", newName, error.localizedDescription)
            return nil
        }
        items[index].generatedImageFileNames[slot] = newName
        try? FileManager.default.removeItem(at: generatedImageURL(fileName: fileName))
        persist()
        return newName
    }

    /// 생성 이미지 한 장을 목록과 디스크에서 지운다.
    func removeGeneratedImage(id: UUID, fileName: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].generatedImageFileNames.removeAll { $0 == fileName }
        try? FileManager.default.removeItem(at: generatedImageURL(fileName: fileName))
        persist()
    }

    /// 항목의 생성 이미지를 모두 지운다 (히스토리 항목과 원본 이미지는 남는다).
    /// 지운 장수를 돌려준다.
    @discardableResult
    func removeAllGeneratedImages(id: UUID) -> Int {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return 0 }
        let names = items[index].generatedImageFileNames
        guard !names.isEmpty else { return 0 }
        for name in names {
            try? FileManager.default.removeItem(at: generatedImageURL(fileName: name))
        }
        items[index].generatedImageFileNames = []
        persist()
        return names.count
    }

    /// 항목의 생성 이미지가 차지하는 디스크 용량 (삭제 전 안내용).
    func generatedImagesByteSize(id: UUID) -> Int64 {
        guard let item = items.first(where: { $0.id == id }) else { return 0 }
        return item.generatedImageFileNames.reduce(into: Int64(0)) { total, name in
            let path = generatedImageURL(fileName: name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int64
            total += size ?? 0
        }
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: imageURL(for: item))
        for fileName in item.generatedImageFileNames {
            try? FileManager.default.removeItem(at: generatedImageURL(fileName: fileName))
        }
        persist()
    }

    func imageURL(for item: HistoryItem) -> URL {
        imagesDirectory.appendingPathComponent(item.imageFileName)
    }

    func generatedImageURL(fileName: String) -> URL {
        generatedDirectory.appendingPathComponent(fileName)
    }

    private func persist() {
        guard let data = try? Self.encoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
