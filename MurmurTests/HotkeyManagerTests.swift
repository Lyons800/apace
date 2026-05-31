import XCTest
import Carbon.HIToolbox
@testable import Murmur

/// Regression test for the bug where holding the Right Option hotkey "sometimes stops
/// working when the app is running": the modifier-key path installed only a GLOBAL
/// event monitor, which never fires while Murmur itself is frontmost. The fix pairs it
/// with a LOCAL monitor (as the regular-key path already does).
final class HotkeyManagerTests: XCTestCase {
    @MainActor
    func test_modifierHotkey_installsBothGlobalAndLocalMonitors() {
        let hm = HotkeyManager(keyCode: UInt16(kVK_RightOption), modifiers: 0, mode: .hold)
        hm.start()
        defer { hm.stop() }

        // The local monitor is the fix: without it the hotkey is dead whenever Murmur
        // is the active app. (We don't assert on the global monitor because
        // addGlobalMonitorForEvents can return nil in a permission-less test runner.)
        XCTAssertTrue(hm.hasLocalMonitorForTesting, "local flagsChanged monitor must be installed so the hotkey works when Murmur is frontmost")
    }

    @MainActor
    func test_stop_removesMonitors() {
        let hm = HotkeyManager(keyCode: UInt16(kVK_RightOption), modifiers: 0, mode: .hold)
        hm.start()
        hm.stop()
        XCTAssertFalse(hm.hasLocalMonitorForTesting)
        XCTAssertFalse(hm.hasFlagsMonitorForTesting)
    }
}
