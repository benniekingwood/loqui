import XCTest
import LoquiTestSupport
@testable import LoquiCore

final class DictationShortcutTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "DictationShortcutTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultHintsKeepTheOriginalRightOptionWording() {
        XCTAssertEqual(DictationShortcut.default.readyHint, "Hold Right Option to record, double-tap to lock")
        XCTAssertEqual(DictationShortcut.default.menuHint, "Hold Right Option to dictate · double-tap to lock")
        XCTAssertEqual(DictationShortcut.default.retryHint, "Hold Right Option to try again.")
        XCTAssertEqual(DictationShortcut.default.recordingHint, "Recording… Release or tap Right Option to stop")
    }

    func testHintsNameTheChosenKeyAndDropDoubleTapWhenHandsFreeIsOff() {
        let shortcut = DictationShortcut(key: .function, doubleTapLocks: false)
        XCTAssertEqual(shortcut.readyHint, "Hold Fn (Globe) to record")
        XCTAssertEqual(shortcut.menuHint, "Hold Fn (Globe) to dictate")
    }

    func testStoreRoundTripsShortcut() {
        let store = DictationShortcutStore(defaultsSuiteName: suiteName)
        let shortcut = DictationShortcut(key: .rightControl, doubleTapLocks: false)

        store.save(shortcut)

        XCTAssertEqual(store.load(), shortcut)
    }

    func testStoreFallsBackToDefaultForMissingOrUnknownValues() {
        let store = DictationShortcutStore(defaultsSuiteName: suiteName)
        XCTAssertEqual(store.load(), .default)

        UserDefaults(suiteName: suiteName)?.set("leftShift", forKey: DictationShortcutStore.keyDefaultsKey)
        XCTAssertEqual(store.load(), .default)
    }

    func testKeysMapFromTheirKeyCodes() {
        for key in DictationKey.allCases {
            XCTAssertEqual(DictationKey(keyCode: key.keyCode), key)
        }
        XCTAssertNil(DictationKey(keyCode: 0x3A), "Left Option is not offered")
    }

    @MainActor
    func testStatusTextNamesTheChosenKey() {
        let shortcut = DictationShortcut(key: .rightCommand, doubleTapLocks: true)
        XCTAssertEqual(
            TranscriptionEngine.presentation(for: .inserted, shortcut: shortcut).statusText,
            "Inserted! Hold Right Command to record, double-tap to lock"
        )
    }
}

final class DictationKeyModelTests: XCTestCase {
    func testRawModifierBitsIdentifyEachPhysicalKey() {
        XCTAssertTrue(DictationKey.rightOption.isDown(modifierFlags: 0x80000 | 0x40))
        XCTAssertFalse(DictationKey.rightOption.isDown(modifierFlags: 0x80000 | 0x20), "Left Option alone is not the dictation key")
        XCTAssertTrue(DictationKey.rightCommand.isDown(modifierFlags: 0x100000 | 0x10))
        XCTAssertTrue(DictationKey.rightControl.isDown(modifierFlags: 0x40000 | 0x2000))
        XCTAssertTrue(DictationKey.function.isDown(modifierFlags: 1 << 23))
        XCTAssertFalse(DictationKey.function.isDown(modifierFlags: 0))
    }

    func testEveryKeyHasADistinctKeyCodeAndLabel() {
        XCTAssertEqual(Set(DictationKey.allCases.map(\.keyCode)).count, DictationKey.allCases.count)
        XCTAssertEqual(Set(DictationKey.allCases.map(\.displayName)).count, DictationKey.allCases.count)
    }
}
