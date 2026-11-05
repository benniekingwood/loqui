import AppKit
import Combine
import LoquiCore

/// What one key event means while Settings records a new dictation key.
package enum ShortcutCaptureResult: Equatable, Sendable {
    case selected(DictationKey)
    case unsupported(String)
    case cancelled
    case ignored
}

package enum ShortcutCapture {
    private static let escapeKeyCode: UInt16 = 0x35
    private static let capsLockKeyCode: UInt16 = 0x39

    /// Any key can be chosen except Escape, which cancels, and Caps Lock,
    /// which macOS reports only as a toggle, so its release can't be seen.
    /// A modifier is chosen as it goes down; any other key on its first key
    /// down, with `characters` naming it in the current keyboard layout.
    package static func interpret(
        isKeyDown: Bool,
        isRepeat: Bool = false,
        keyCode: UInt16,
        characters: String? = nil,
        modifierFlags: NSEvent.ModifierFlags
    ) -> ShortcutCaptureResult {
        if isKeyDown {
            if keyCode == escapeKeyCode {
                return .cancelled
            }
            return isRepeat ? .ignored : .selected(DictationKey(keyCode: keyCode, name: characters))
        }
        if keyCode == capsLockKeyCode {
            return .unsupported("Caps Lock can’t be held for dictation: macOS reports only that it toggled, not when it’s released. Choose another key.")
        }
        let key = DictationKey(keyCode: keyCode)
        return key.isModifier && key.isDown(in: modifierFlags) ? .selected(key) : .ignored
    }
}

/// Records the next dictation key pressed while the Settings window is key.
/// The live shortcut is suspended meanwhile, so pressing the current key here
/// does not start a recording.
@MainActor
package final class ShortcutRecorder: ObservableObject {
    @Published package private(set) var isRecording = false
    @Published package private(set) var message: String?

    private let hotKeyController: HotKeyController
    private var monitor: Any?

    package init(hotKeyController: HotKeyController) {
        self.hotKeyController = hotKeyController
    }

    package func start() {
        guard !isRecording else { return }
        message = nil
        isRecording = true
        hotKeyController.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let isKeyDown = event.type == .keyDown
            let isRepeat = isKeyDown && event.isARepeat
            let keyCode = event.keyCode
            let characters = isKeyDown ? event.charactersIgnoringModifiers : nil
            let modifierFlags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                self?.handle(
                    isKeyDown: isKeyDown,
                    isRepeat: isRepeat,
                    keyCode: keyCode,
                    characters: characters,
                    modifierFlags: modifierFlags
                ) ?? false
            }
            return consumed ? nil : event
        }
    }

    package func cancel() {
        guard isRecording else { return }
        message = nil
        finish()
    }

    /// Returns whether the event was consumed, so typed keys don't beep.
    private func handle(
        isKeyDown: Bool,
        isRepeat: Bool,
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch ShortcutCapture.interpret(
            isKeyDown: isKeyDown,
            isRepeat: isRepeat,
            keyCode: keyCode,
            characters: characters,
            modifierFlags: modifierFlags
        ) {
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
            return isKeyDown
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
