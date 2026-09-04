import XCTest
@testable import CaptureToPrompt

final class UpdateCheckerTests: XCTestCase {

    // MARK: - 버전 비교

    func testVersionComparison() {
        XCTAssertTrue(AppVersion("0.2.0") > AppVersion("0.1.0"))
        XCTAssertTrue(AppVersion("0.1.10") > AppVersion("0.1.9"))   // 사전순이 아니라 숫자순
        XCTAssertTrue(AppVersion("1.0.0") > AppVersion("0.9.9"))
        XCTAssertFalse(AppVersion("0.1.0") > AppVersion("0.1.0"))
        XCTAssertFalse(AppVersion("0.1.0") > AppVersion("0.2.0"))
    }

    /// 태그의 v 접두사와 자리 수가 다른 표기도 받아들인다.
    func testVersionParsingTolerance() {
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion("1.2.3"))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        XCTAssertTrue(AppVersion("v0.2") > AppVersion("0.1.9"))
    }

    // MARK: - 릴리스 응답 파싱

    private let releaseJSON = """
    {
      "tag_name": "v0.2.0",
      "name": "0.2.0",
      "body": "- 포즈 추출 추가\\n- 병렬 분석",
      "html_url": "https://github.com/Charlesswoo/capture-to-prompt/releases/tag/v0.2.0",
      "assets": [
        {"name": "notes.txt",
         "browser_download_url": "https://example.com/notes.txt", "size": 12},
        {"name": "CaptureToPrompt.zip",
         "browser_download_url": "https://example.com/CaptureToPrompt.zip", "size": 7340032}
      ]
    }
    """

    func testParseReleasePicksZipAsset() throws {
        let release = try UpdateChecker.parseRelease(Data(releaseJSON.utf8))

        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.downloadURL.absoluteString,
                       "https://example.com/CaptureToPrompt.zip")
        XCTAssertEqual(release.byteSize, 7_340_032)
        XCTAssertTrue(release.notes.contains("포즈 추출"))
    }

    /// zip 자산이 없는 릴리스는 설치할 수 없으므로 실패로 본다.
    func testParseReleaseWithoutZipThrows() {
        let json = #"{"tag_name":"v0.2.0","assets":[{"name":"a.txt","browser_download_url":"https://e/a.txt","size":1}]}"#
        XCTAssertThrowsError(try UpdateChecker.parseRelease(Data(json.utf8)))
    }

    // MARK: - 업데이트 필요 여부

    func testUpdateOfferedOnlyWhenNewer() throws {
        let release = try UpdateChecker.parseRelease(Data(releaseJSON.utf8))
        XCTAssertTrue(UpdateChecker.isUpdateAvailable(current: "0.1.0", release: release))
        XCTAssertFalse(UpdateChecker.isUpdateAvailable(current: "0.2.0", release: release))
        XCTAssertFalse(UpdateChecker.isUpdateAvailable(current: "0.3.0", release: release))
    }

    // MARK: - 요청 구성

    func testLatestReleaseRequestUsesPublicAPI() throws {
        let request = UpdateChecker.latestReleaseRequest(repository: "Charlesswoo/capture-to-prompt")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.github.com/repos/Charlesswoo/capture-to-prompt/releases/latest")
        // 공개 저장소라 토큰이 필요 없다
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"),
                       "application/vnd.github+json")
    }

    // MARK: - 설치 스크립트

    /// 교체 스크립트는 앱이 완전히 끝난 뒤에 덮어써야 한다 (실행 중 번들 교체 방지).
    func testInstallScriptWaitsForExitAndClearsQuarantine() {
        let script = UpdateInstaller.replaceScript(
            newAppPath: "/tmp/new/CaptureToPrompt.app",
            installedPath: "/Applications/CaptureToPrompt.app",
            pid: 4242)

        XCTAssertTrue(script.contains("kill -0 4242"))
        XCTAssertTrue(script.contains("/Applications/CaptureToPrompt.app"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("open"))
        // 지우기 전에 새 번들이 있는지 확인해야 한다 — 실패 시 앱이 사라지면 안 된다
        XCTAssertTrue(script.contains("[ -d \"$NEW\" ]"))
    }

    // MARK: - 주기적 확인 (2026-09-04)

    func testShouldCheckRespectsInterval() {
        let now = Date()
        // 한 번도 확인하지 않았으면 바로 확인한다
        XCTAssertTrue(UpdateChecker.shouldCheck(lastCheck: nil, now: now, interval: 3600))
        // 간격이 지나지 않았으면 건너뛴다 (앱 활성화마다 조회하지 않도록)
        XCTAssertFalse(UpdateChecker.shouldCheck(lastCheck: now.addingTimeInterval(-60),
                                                 now: now, interval: 3600))
        // 간격이 지났으면 다시 확인한다
        XCTAssertTrue(UpdateChecker.shouldCheck(lastCheck: now.addingTimeInterval(-3601),
                                                now: now, interval: 3600))
    }

    /// 시계가 뒤로 간 경우(수동 변경·절전 복귀)에도 멈추지 않아야 한다.
    func testShouldCheckHandlesFutureLastCheck() {
        let now = Date()
        XCTAssertTrue(UpdateChecker.shouldCheck(lastCheck: now.addingTimeInterval(3600),
                                                now: now, interval: 3600))
    }
}
