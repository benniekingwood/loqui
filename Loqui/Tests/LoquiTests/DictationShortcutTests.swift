import AppKit
import XCTest
@testable import Loqui

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

    func testCapturePressingASupportedKeySelectsIt() {
        let rightOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x40)
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3D, modifierFlags: rightOption), .selected(.rightOption))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3F, modifierFlags: .function), .selected(.function))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3D, modifierFlags: []), .ignored)
    }

    func testCaptureExplainsUnsupportedKeysAndIgnoresTheirRelease() {
        let leftOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)
        guard case let .unsupported(message) = ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3A, modifierFlags: leftOption) else {
            return XCTFail("Left Option should be explained")
        }
        XCTAssertTrue(message.hasPrefix("Left Option"))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3A, modifierFlags: []), .ignored)
        guard case .unsupported = ShortcutCapture.interpret(isKeyDown: true, keyCode: 0x00, modifierFlags: []) else {
            return XCTFail("Letter keys should be explained")
        }
    }

    func testCaptureEscapeCancels() {
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: true, keyCode: 0x35, modifierFlags: []), .cancelled)
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
