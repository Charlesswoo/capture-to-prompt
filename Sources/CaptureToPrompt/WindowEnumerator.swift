import Foundation
import ScreenCaptureKit

/// 창 선택 그리드에 표시할 창 하나.
struct PickableWindow: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let thumbnail: CGImage?
}

/// ScreenCaptureKit으로 화면의 일반 창 목록 + 썸네일을 수집한다.
/// (화면 기록 권한 필요 — 캡처 기능과 동일 권한이라 추가 요청은 없음)
enum WindowEnumerator {
    static func pickableWindows() async -> [PickableWindow] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let candidates = content.windows.filter { w in
            w.windowLayer == 0
                && w.isOnScreen
                && w.frame.width >= 120 && w.frame.height >= 90
                && w.owningApplication?.processID != pid_t(myPID)
        }

        var result: [PickableWindow] = []
        for window in candidates {
            let thumb = await thumbnail(for: window)
            result.append(PickableWindow(
                id: window.windowID,
                title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "알 수 없음",
                thumbnail: thumb))
        }
        return result
    }

    private static func thumbnail(for window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(1, 480 / max(window.frame.width, 1))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
    }
}
