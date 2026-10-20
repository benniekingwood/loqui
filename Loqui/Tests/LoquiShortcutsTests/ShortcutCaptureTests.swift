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
}
