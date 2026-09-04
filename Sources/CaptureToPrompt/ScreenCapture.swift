import Foundation
import AppKit

/// macOS 기본 `screencapture -i` (영역 선택 캡처) 래퍼.
enum ScreenCapture {
    /// 인터랙티브 영역 캡처를 실행하고 PNG 데이터를 반환한다.
    /// 사용자가 ESC로 취소하면 nil.
    static func captureInteractive() async -> Data? {
        await run(arguments: ["-i", "-x"])  // -x: 셔터음 없음
    }

    /// 창 선택 모드: 카메라 커서로 원하는 창을 클릭해 캡처한다. ESC로 취소 시 nil.
    static func captureWindowInteractive() async -> Data? {
        await run(arguments: ["-i", "-W", "-x", "-o"])  // -W: 창 선택 모드로 시작
    }

    /// 특정 창(CGWindowID)을 클릭 없이 바로 캡처한다.
    static func captureWindow(id: CGWindowID) async -> Data? {
        await run(arguments: ["-x", "-o", "-l", String(id)])  // -o: 그림자 제외
    }

    private static func run(arguments: [String]) async -> Data? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("c2p-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments + [tmpURL.path]

        do {
            try process.run()
        } catch {
            return nil
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard let data = try? Data(contentsOf: tmpURL), !data.isEmpty else { return nil }
        return data
    }
}
