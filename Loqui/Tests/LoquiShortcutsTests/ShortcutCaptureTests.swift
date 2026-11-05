import AppKit
import XCTest
@testable import LoquiCore
@testable import LoquiShortcuts

final class ShortcutCaptureTests: XCTestCase {
    func testCapturePressingASupportedKeySelectsIt() {
        let rightOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x40)
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3D, modifierFlags: rightOption), .selected(.rightOption))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3F, modifierFlags: .function), .selected(.function))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3D, modifierFlags: []), .ignored)
    }

    func testCaptureSelectsLeftHandModifiers() {
        let leftControl = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.control.rawValue | 0x01)
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3B, modifierFlags: leftControl), .selected(.leftControl))
        let leftShift = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x02)
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x38, modifierFlags: leftShift), .selected(.leftShift))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x3B, modifierFlags: []), .ignored)
    }

    func testCaptureSelectsAnyOtherKeyOnItsFirstPress() {
        let result = ShortcutCapture.interpret(isKeyDown: true, keyCode: 0x00, characters: "a", modifierFlags: [])
        XCTAssertEqual(result, .selected(DictationKey(keyCode: 0x00)))
        guard case let .selected(key) = result else { return }
        XCTAssertEqual(key.displayName, "A")
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: true, keyCode: 0x69, modifierFlags: []), .selected(DictationKey(keyCode: 0x69)))
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: true, isRepeat: true, keyCode: 0x00, modifierFlags: []), .ignored)
    }

    func testCaptureExplainsWhyCapsLockCannotBeHeld() {
        guard case let .unsupported(message) = ShortcutCapture.interpret(isKeyDown: false, keyCode: 0x39, modifierFlags: .capsLock) else {
            return XCTFail("Caps Lock should be explained")
        }
        XCTAssertTrue(message.hasPrefix("Caps Lock"))
    }

    func testCaptureEscapeCancels() {
        XCTAssertEqual(ShortcutCapture.interpret(isKeyDown: true, keyCode: 0x35, modifierFlags: []), .cancelled)
    }
}
