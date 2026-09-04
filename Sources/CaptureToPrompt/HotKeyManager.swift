import Foundation
import AppKit
import Carbon.HIToolbox

/// 전역 단축키 (Carbon RegisterEventHotKey — 접근성 권한 불필요, 비활성 상태에서도 동작).
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// 설정에서 고를 수 있는 프리셋. rawValue가 UserDefaults에 저장된다.
    enum Preset: String, CaseIterable, Identifiable {
        case optShiftC = "opt-shift-c"
        case cmdShift2 = "cmd-shift-2"
        case ctrlShiftS = "ctrl-shift-s"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .optShiftC: return "⌥⇧C"
            case .cmdShift2: return "⌘⇧2"
            case .ctrlShiftS: return "⌃⇧S"
            }
        }

        /// (Carbon 키코드, Carbon 수정자 마스크)
        var carbonKey: (keyCode: UInt32, modifiers: UInt32) {
            switch self {
            case .optShiftC: return (UInt32(kVK_ANSI_C), UInt32(optionKey | shiftKey))
            case .cmdShift2: return (UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey))
            case .ctrlShiftS: return (UInt32(kVK_ANSI_S), UInt32(controlKey | shiftKey))
            }
        }
    }

    static let defaultPreset: Preset = .optShiftC

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func apply(preset: Preset) {
        installHandlerIfNeeded()
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        let key = preset.carbonKey
        let hotKeyID = EventHotKeyID(signature: OSType(0x43325054), id: 1)  // 'C2PT'
        RegisterEventHotKey(key.keyCode, key.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                HotKeyManager.shared.onHotKey?()
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }
}
