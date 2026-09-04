import Foundation

/// 앱 버전 — "v1.2.3", "1.2" 같은 표기를 모두 숫자 비교로 다룬다.
struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    let components: [Int]

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop { $0 == "v" }
        var parsed = trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        while parsed.count < 3 { parsed.append(0) }   // "1.2" → 1.2.0
        components = parsed
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (l, r) in zip(lhs.components, rhs.components) where l != r { return l < r }
        return lhs.components.count < rhs.components.count
    }
}

/// GitHub 공개 저장소의 최신 릴리스를 확인한다 (공개라 토큰이 필요 없다).
enum UpdateChecker {
    static let repository = "Charlesswoo/capture-to-prompt"

    struct Release: Equatable {
        let version: AppVersion
        let downloadURL: URL
        let byteSize: Int64
        let notes: String
        let pageURL: URL?
    }

    /// 현재 실행 중인 앱의 버전 (Info.plist).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func latestReleaseRequest(repository: String = UpdateChecker.repository) -> URLRequest {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    /// 릴리스 응답 파싱 — 설치에 쓸 zip 자산이 있어야 유효하다.
    static func parseRelease(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: String
                let size: Int64
                enum CodingKeys: String, CodingKey {
                    case name, size
                    case browserDownloadURL = "browser_download_url"
                }
            }
            let tagName: String
            let body: String?
            let htmlURL: String?
            let assets: [Asset]
            enum CodingKeys: String, CodingKey {
                case body, assets
                case tagName = "tag_name"
                case htmlURL = "html_url"
            }
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw AnalyzerError.apiError(status: 0, message: "릴리스 정보를 해석하지 못했습니다.")
        }
        guard let asset = payload.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
              let url = URL(string: asset.browserDownloadURL) else {
            throw AnalyzerError.apiError(
                status: 0, message: "릴리스에 설치할 zip 파일이 없습니다 (\(payload.tagName)).")
        }
        return Release(version: AppVersion(payload.tagName),
                       downloadURL: url,
                       byteSize: asset.size,
                       notes: payload.body ?? "",
                       pageURL: payload.htmlURL.flatMap(URL.init(string:)))
    }

    /// 확인 주기 — 앱을 켜둔 채로도 새 릴리스를 알아채되, 활성화될 때마다 조회하지는 않는다.
    static let checkInterval: TimeInterval = 3600   // 1시간

    /// 마지막 확인 이후 간격이 지났는지. 시계가 뒤로 간 경우에도 멈추지 않는다.
    static func shouldCheck(lastCheck: Date?, now: Date = Date(),
                            interval: TimeInterval = UpdateChecker.checkInterval) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }

    static func isUpdateAvailable(current: String, release: Release) -> Bool {
        release.version > AppVersion(current)
    }

    /// 최신 릴리스를 조회한다. 새 버전이 없으면 nil.
    static func checkForUpdate(current: String = UpdateChecker.currentVersion) async throws -> Release? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        let (data, response) = try await URLSession(configuration: config)
            .data(for: latestReleaseRequest())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // 릴리스가 하나도 없으면 404 — 오류가 아니라 "새 버전 없음"으로 다룬다
            if status == 404 { return nil }
            throw AnalyzerError.apiError(status: status, message: "업데이트 확인에 실패했습니다.")
        }
        let release = try parseRelease(data)
        return isUpdateAvailable(current: current, release: release) ? release : nil
    }
}
