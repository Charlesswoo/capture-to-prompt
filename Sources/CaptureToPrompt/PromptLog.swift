import Foundation

/// 모델 호출 한 건, 또는 그 결과에 대한 사용자의 반응 한 건.
///
/// 프롬프트를 고치려면 "무엇을 보내서 무엇을 받았는지"와 "그 결과가 좋았는지"가 함께
/// 있어야 한다. 앞의 둘은 호출부가, 마지막 하나는 사용자 행동(재추출·수정·삭제)이 알려준다.
struct PromptLogEntry: Codable, Equatable {

    enum Kind: String, Codable {
        // 모델 호출
        case analyze              // 이미지 → 프롬프트 추출
        case generate             // 프롬프트 → 이미지 생성
        case revise               // 정책 거부 프롬프트 개선 제안
        case sync                 // 한 언어 수정 → 나머지 언어 맞추기
        // 사용자 반응 (결과 품질의 유일한 라벨)
        case reanalyze                                  // 같은 이미지를 다시 뽑음 = 결과 불만
        case promptEdited = "prompt_edited"             // 뽑힌 프롬프트를 손댐
        case generatedDeleted = "generated_deleted"     // 생성 결과를 버림
        case itemDeleted = "item_deleted"               // 항목을 통째로 버림
    }

    enum Outcome: String, Codable {
        case ok
        case error
        case refusal                                    // 모델이 분석 자체를 거절
        case contentPolicy = "content_policy"           // 생성이 정책에 막힘
        case signal                                     // 호출이 아닌 사용자 행동
    }

    var timestamp: Date
    var kind: Kind
    var outcome: Outcome
    /// "claude-cli" | "codex-cli" | "api" | "codex-image" | "openai-image"
    var backend: String?
    var model: String?
    var historyID: String?
    var durationMs: Int?
    /// 모델에 실제로 보낸 지시문 전문.
    var prompt: String?
    /// 받은 결과 (구조화 결과는 JSON, 그 외는 원문).
    var response: String?
    var error: String?
    /// 다룬 이미지의 픽셀 크기 ("1024x1536"). analyze는 입력, generate는 결과 기준 —
    /// 둘을 history_id로 짝지으면 원본 화면비가 재현됐는지 실제로 셀 수 있다.
    var imageSize: String?
    /// 분류에 도움이 되는 짧은 부가정보 (언어, 생성 모드 등).
    var note: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, kind, outcome, backend, model, prompt, response, error, note
        case historyID = "history_id"
        case durationMs = "duration_ms"
        case imageSize = "image_size"
    }

    init(timestamp: Date = Date(), kind: Kind, outcome: Outcome,
         backend: String? = nil, model: String? = nil, historyID: String? = nil,
         durationMs: Int? = nil, prompt: String? = nil, response: String? = nil,
         error: String? = nil, imageSize: String? = nil, note: String? = nil) {
        self.timestamp = timestamp
        self.kind = kind
        self.outcome = outcome
        self.backend = backend
        self.model = model
        self.historyID = historyID
        self.durationMs = durationMs
        self.prompt = prompt
        self.response = response
        self.error = error
        self.imageSize = imageSize
        self.note = note
    }

    /// 소요 시간을 시작 시각에서 뽑는 편의 생성자 — 호출부마다 계산하지 않도록.
    init(kind: Kind, outcome: Outcome, since started: Date,
         backend: String? = nil, model: String? = nil, historyID: String? = nil,
         prompt: String? = nil, response: String? = nil,
         error: String? = nil, imageSize: String? = nil, note: String? = nil) {
        self.init(kind: kind, outcome: outcome, backend: backend, model: model,
                  historyID: historyID,
                  durationMs: Int(Date().timeIntervalSince(started) * 1000),
                  prompt: prompt, response: response, error: error,
                  imageSize: imageSize, note: note)
    }
}

extension PromptLogEntry.Outcome {
    /// 실패를 종류별로 갈라 둔다 — 정책 거부와 파싱 실패는 전혀 다른 개선 과제다.
    init(_ error: Error) {
        guard let analyzer = error as? AnalyzerError else { self = .error; return }
        switch analyzer {
        case .contentPolicy: self = .contentPolicy
        case .refusal: self = .refusal
        default: self = .error
        }
    }
}

/// JSONL 한 줄에 한 건씩 덧붙이는 기록기. 사람이 아니라 도구(jq·스크립트)가 읽는다.
/// 앱 동작을 막지 않도록 전용 직렬 큐에서 쓰고, 실패해도 조용히 넘어간다.
final class PromptLogWriter {
    let fileURL: URL
    /// 한도를 넘으면 직전 파일 하나만 남기고 새로 시작한다 (무한히 자라지 않도록).
    let maxBytes: Int
    /// 설정 키 — 사용자가 끄면 아무것도 기록하지 않는다.
    static let defaultsKey = "promptLogEnabled"

    /// 기본값은 설정을 따르고, 테스트에서는 직접 지정해 덮어쓴다.
    var isEnabled: Bool {
        get {
            enabledOverride
                ?? (UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true)
        }
        set { enabledOverride = newValue }
    }
    private var enabledOverride: Bool?

    var rotatedFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("1.jsonl")
    }

    private let queue = DispatchQueue(label: "capture-to-prompt.prompt-log")

    init(fileURL: URL, maxBytes: Int = 5_000_000) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]   // 절대 prettyPrinted 금지
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func append(_ entry: PromptLogEntry) {
        guard isEnabled else { return }
        guard let line = try? Self.encoder().encode(entry) else { return }
        queue.async { [self] in
            var data = line
            data.append(0x0A)   // \n
            rotateIfNeeded(adding: data.count)
            write(data)
        }
    }

    /// 테스트·종료 시점에 큐를 비운다.
    func waitForPendingWrites() {
        queue.sync {}
    }

    /// 현재 파일의 기록을 읽는다. 깨진 줄(쓰는 도중 종료)은 건너뛴다.
    func entries() throws -> [PromptLogEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = Self.decoder()
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            try? decoder.decode(PromptLogEntry.self, from: Data($0.utf8))
        }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: rotatedFileURL)
        }
    }

    // MARK: - 파일 조작 (큐 안에서만)

    private func currentSize() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    private func rotateIfNeeded(adding bytes: Int) {
        guard currentSize() > 0, currentSize() + bytes > maxBytes else { return }
        try? FileManager.default.removeItem(at: rotatedFileURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedFileURL)
    }

    private func write(_ data: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: data)
    }
}

/// 앱 전역 기록기. 히스토리 옆에 두어 "이 앱이 무엇을 했는지"가 한 곳에 모이게 한다.
enum PromptLog {
    /// 테스트는 임시 폴더 기록기로 갈아끼운다 (진짜 로그를 더럽히지 않도록).
    nonisolated(unsafe) static var shared: PromptLogWriter = {
        let writer = PromptLogWriter(fileURL: defaultFileURL())
        // 테스트가 사용자의 실제 로그에 섞여 들어가면 통계가 통째로 못 쓰게 된다.
        // (2026-09-09에 실제로 오염시켰다 — AppStateTests가 여기에 11건을 남겼다.)
        if isRunningTests { writer.isEnabled = false }
        return writer
    }()

    /// XCTest 프로세스 안에서 도는 중인지.
    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func defaultDirectory() -> URL {
        HistoryStore.defaultDirectory().appendingPathComponent("logs")
    }

    static func defaultFileURL() -> URL {
        defaultDirectory().appendingPathComponent("prompt-log.jsonl")
    }

    static func record(_ entry: PromptLogEntry) {
        shared.append(entry)
    }

    /// 설정 화면에 보여줄 현재 기록 크기 (회전된 파일 포함).
    static func currentByteSize() -> Int {
        [shared.fileURL, shared.rotatedFileURL].reduce(0) { total, url in
            total + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
                      as? Int) ?? 0)
        }
    }

    /// 설정 키를 한 곳에서만 정의한다.
    static var defaultsKey: String { PromptLogWriter.defaultsKey }
}
