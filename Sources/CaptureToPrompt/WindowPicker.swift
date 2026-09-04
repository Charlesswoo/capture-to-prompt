import Foundation
import AppKit
import CoreGraphics

/// 마우스 커서 아래에 있는 (다른 앱의) 최상위 일반 창을 찾는다.
enum WindowPicker {
    /// 커서 아래 창의 CGWindowID. 없으면 nil.
    static func windowUnderMouse() -> CGWindowID? {
        let mouse = NSEvent.mouseLocation  // 좌하단 원점 (y 위로 증가)
        // CGWindowList 좌표계는 주 디스플레이 좌상단 원점 (y 아래로 증가)
        guard let primary = NSScreen.screens.first else { return nil }
        let cgPoint = CGPoint(x: mouse.x, y: primary.frame.maxY - mouse.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        // 리스트는 앞→뒤 순서이므로 처음 매칭되는 창이 커서 아래 최상위 창이다.
        for info in list {
            guard let layer = info[kCGWindowLayer] as? Int, layer == 0,  // 일반 창만 (메뉴바/독 제외)
                  let pid = info[kCGWindowOwnerPID] as? Int32, pid != myPID,
                  let alpha = info[kCGWindowAlpha] as? Double, alpha > 0,
                  let boundsDict = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 50, bounds.height >= 50,  // 아주 작은 유틸리티 창 제외
                  bounds.contains(cgPoint),
                  let number = info[kCGWindowNumber] as? Int else { continue }
            return CGWindowID(number)
        }
        return nil
    }
}
