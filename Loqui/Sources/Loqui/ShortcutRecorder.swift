import AppKit
import Combine

/// What one key event means while Settings records a new dictation key.
enum ShortcutCaptureResult: Equatable, Sendable {
    case selected(DictationKey)
    case unsupported(String)
    case cancelled
    case ignored
}

enum ShortcutCapture {
    static let supportedKeysSentence = "Choose Right Option, Right Command, Right Control, or Fn (Globe)."

    /// Modifier keys that are reported by name when pressed but cannot be used,
    /// with the device bit that is set while each one is down.
    private static let unsupportedModifiers: [UInt16: (name: String, downMask: UInt)] = [
        0x3A: ("Left Option", 0x20),
        0x37: ("Left Command", 0x08),
        0x3B: ("Left Control", 0x01),
        0x38: ("Left Shift", 0x02),
        0x3C: ("Right Shift", 0x04),
    ]

    private static let escapeKeyCode: UInt16 = 0x35
    private static let capsLockKeyCode: UInt16 = 0x39

    static func interpret(
        isKeyDown: Bool,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutCaptureResult {
        if isKeyDown {
            if keyCode == escapeKeyCode {
                return .cancelled
            }
            return .unsupported("Use a modifier key, so dictation doesn’t type a character. \(supportedKeysSentence)")
        }
        if let key = DictationKey(keyCode: keyCode) {
            return key.isDown(in: modifierFlags) ? .selected(key) : .ignored
        }
        if keyCode == capsLockKeyCode {
            return .unsupported("Caps Lock can’t be held for dictation. \(supportedKeysSentence)")
        }
        if let modifier = unsupportedModifiers[keyCode], modifierFlags.rawValue & modifier.downMask != 0 {
            return .unsupported("\(modifier.name) is part of everyday shortcuts and typing. \(supportedKeysSentence)")
        }
        return .ignored
    }
}

/// Records the next dictation key pressed while the Settings window is key.
/// The live shortcut is suspended meanwhile, so pressing the current key here
/// does not start a recording.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    private let hotKeyController: HotKeyController
    private var monitor: Any?

    init(hotKeyController: HotKeyController) {
        self.hotKeyController = hotKeyController
    }

    func start() {
        guard !isRecording else { return }
        message = nil
        isRecording = true
        hotKeyController.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let isKeyDown = event.type == .keyDown
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                self?.handle(isKeyDown: isKeyDown, keyCode: keyCode, modifierFlags: modifierFlags) ?? false
            }
            return consumed ? nil : event
        }
    }

    func cancel() {
        guard isRecording else { return }
        message = nil
        finish()
    }

    /// Returns whether the event was consumed, so typed keys don't beep.
    private func handle(isKeyDown: Bool, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch ShortcutCapture.interpret(isKeyDown: isKeyDown, keyCode: keyCode, modifierFlags: modifierFlags) {
        case let .selected(key):
            var shortcut = hotKeyController.shortcut
            shortcut.key = key
            message = nil
            hotKeyController.update(shortcut)
            finish()
            return true
        case let .unsupported(explanation):
            message = explanation
            return isKeyDown
        case .cancelled:
            cancel()
            return true
        case .ignored:
            return false
        }
    }

    private func finish() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        hotKeyController.resume()
    }
}
