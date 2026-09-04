import XCTest
import Carbon.HIToolbox
@testable import CaptureToPrompt

final class HotKeyManagerTests: XCTestCase {

    func testPresetKeyMapping() {
        let optShiftC = HotKeyManager.Preset.optShiftC.carbonKey
        XCTAssertEqual(optShiftC.keyCode, UInt32(kVK_ANSI_C))
        XCTAssertEqual(optShiftC.modifiers, UInt32(optionKey | shiftKey))

        let cmdShift2 = HotKeyManager.Preset.cmdShift2.carbonKey
        XCTAssertEqual(cmdShift2.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(cmdShift2.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testPresetRoundTripFromStoredValue() {
        for preset in HotKeyManager.Preset.allCases {
            XCTAssertEqual(HotKeyManager.Preset(rawValue: preset.rawValue), preset)
        }
        XCTAssertNil(HotKeyManager.Preset(rawValue: "unknown"))
    }
}
