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

    func testStoreRoundTripsAnyKeyWithItsCapturedName() {
        let store = DictationShortcutStore(defaultsSuiteName: suiteName)

        store.save(DictationShortcut(key: .leftControl, doubleTapLocks: true))
        XCTAssertEqual(store.load().key.displayName, "Left Control")

        store.save(DictationShortcut(key: DictationKey(keyCode: 0x0C, name: "a"), doubleTapLocks: true))
        XCTAssertEqual(store.load().key, DictationKey(keyCode: 0x0C))
        XCTAssertEqual(store.load().key.displayName, "A", "The captured layout name survives a relaunch")
    }

    func testStoreFallsBackToDefaultForMissingOrUnknownValues() {
        let store = DictationShortcutStore(defaultsSuiteName: suiteName)
        XCTAssertEqual(store.load(), .default)

        UserDefaults(suiteName: suiteName)?.set("leftShift", forKey: DictationShortcutStore.legacyKeyDefaultsKey)
        XCTAssertEqual(store.load(), .default)

        UserDefaults(suiteName: suiteName)?.set(-1, forKey: DictationShortcutStore.keyCodeDefaultsKey)
        XCTAssertEqual(store.load(), .default)
    }

    func testStoreReadsKeysSavedBeforeAnyKeySupport() {
        let store = DictationShortcutStore(defaultsSuiteName: suiteName)
        UserDefaults(suiteName: suiteName)?.set("rightControl", forKey: DictationShortcutStore.legacyKeyDefaultsKey)

        XCTAssertEqual(store.load().key, .rightControl)
    }

    func testKeysAreIdentifiedByKeyCodeAlone() {
        XCTAssertEqual(DictationKey(keyCode: 0x3B), .leftControl)
        XCTAssertEqual(DictationKey(keyCode: 0x00, name: "q"), DictationKey(keyCode: 0x00))
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

    func testLeftModifiersUseTheirOwnDeviceBits() {
        XCTAssertTrue(DictationKey.leftControl.isDown(modifierFlags: 0x40000 | 0x01))
        XCTAssertFalse(DictationKey.leftControl.isDown(modifierFlags: 0x40000 | 0x2000), "Right Control alone is not Left Control")
        XCTAssertTrue(DictationKey.leftCommand.isDown(modifierFlags: 0x100000 | 0x08))
        XCTAssertTrue(DictationKey.leftShift.isDown(modifierFlags: 0x20000 | 0x02))
        XCTAssertTrue(DictationKey.rightShift.isDown(modifierFlags: 0x20000 | 0x04))
    }

    func testEveryModifierHasADistinctKeyCodeAndLabel() {
        let modifiers: [DictationKey] = [
            .rightOption, .leftOption, .rightCommand, .leftCommand,
            .rightControl, .leftControl, .rightShift, .leftShift, .function,
        ]
        XCTAssertTrue(modifiers.allSatisfy(\.isModifier))
        XCTAssertEqual(Set(modifiers).count, modifiers.count)
        XCTAssertEqual(Set(modifiers.map(\.displayName)).count, modifiers.count)
    }

    func testOtherKeysAreNamedFromTheLayoutOrTheirLabel() {
        XCTAssertFalse(DictationKey(keyCode: 0x69).isModifier)
        XCTAssertEqual(DictationKey(keyCode: 0x69).displayName, "F13")
        XCTAssertEqual(DictationKey(keyCode: 0x31, name: " ").displayName, "Space")
        XCTAssertEqual(DictationKey(keyCode: 0x00, name: "q").displayName, "Q", "AZERTY prints Q on this key")
        XCTAssertEqual(DictationKey(keyCode: 0x00).displayName, "A")
        XCTAssertEqual(DictationKey(keyCode: 0x6E, name: "\u{F710}").displayName, "Key 110", "Private-use characters are not names")
        XCTAssertFalse(DictationKey(keyCode: 0x00).isDown(modifierFlags: .max))
    }
}
