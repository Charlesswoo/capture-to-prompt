import Foundation
import AppKit

/// 내려받은 새 버전을 설치한다.
///
/// 실행 중인 자기 자신을 덮어쓸 수는 없으므로, 교체는 별도 셸 스크립트에 맡긴다.
/// 스크립트는 앱이 완전히 끝날 때까지 기다렸다가 번들을 바꾸고 다시 연다.
enum UpdateInstaller {

    /// 교체 스크립트. 새 번들이 실제로 있을 때만 기존 것을 지운다
    /// (중간에 실패해도 앱이 사라지지 않도록).
    static func replaceScript(newAppPath: String, installedPath: String, pid: Int32) -> String {
        """
        #!/bin/bash
        set -u
        NEW="\(newAppPath)"
        DEST="\(installedPath)"

        # 앱이 완전히 종료될 때까지 대기 (최대 30초)
        for _ in $(seq 1 150); do
          kill -0 \(pid) 2>/dev/null || break
          sleep 0.2
        done

        [ -d "$NEW" ] || exit 1
        rm -rf "$DEST"
        cp -R "$NEW" "$DEST" || exit 1
        # 내려받은 파일에 붙는 격리 속성 제거 — 없으면 첫 실행이 차단된다
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        rm -rf "$(dirname "$NEW")"
        open "$DEST"
        """
    }

    /// zip을 받아 풀고, 앱 번들을 꺼낸다. 반환값은 임시 폴더 안의 .app 경로.
    static func downloadAndUnpack(from url: URL) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        let (downloaded, response) = try await URLSession(configuration: config).download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AnalyzerError.apiError(status: status, message: "새 버전을 내려받지 못했습니다.")
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zipURL = workDir.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zipURL)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, workDir.path]
        unzip.standardInput = FileHandle.nullDevice
        try unzip.run()
        await Task.detached { unzip.waitUntilExit() }.value
        guard unzip.terminationStatus == 0 else {
            throw AnalyzerError.apiError(status: Int(unzip.terminationStatus),
                                         message: "내려받은 파일의 압축을 풀지 못했습니다.")
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: workDir, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw AnalyzerError.apiError(status: 0, message: "압축 안에서 앱을 찾지 못했습니다.")
        }
        return app
    }

    /// 교체 스크립트를 띄우고 앱을 종료한다. 스크립트가 새 버전을 다시 연다.
    static func replaceAndRelaunch(newApp: URL) throws {
        let installed = Bundle.main.bundleURL
        let scriptURL = newApp.deletingLastPathComponent()
            .appendingPathComponent("install.sh")
        let script = replaceScript(newAppPath: newApp.path,
                                   installedPath: installed.path,
                                   pid: ProcessInfo.processInfo.processIdentifier)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        try process.run()   // 앱이 죽어도 계속 돈다

        NSApp.terminate(nil)
    }
}
