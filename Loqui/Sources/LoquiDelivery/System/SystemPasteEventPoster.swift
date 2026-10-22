import ApplicationServices
import AppKit
import Foundation
import LoquiCore

@MainActor
package final class SystemPasteEventPoster: PasteEventPosting {
    package func ensurePermission(prompt: Bool) -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }
        return prompt ? CGRequestPostEventAccess() : false
    }

    package func postPasteShortcut(to target: PasteTarget) -> Bool {
        guard let events = Self.pasteShortcutEvents() else {
            return false
        }
        for event in events {
            event.postToPid(target.processIdentifier)
        }
        return true
    }

    package func postPasteShortcutToFrontmostApp() -> Bool {
        guard let events = Self.pasteShortcutEvents() else {
            return false
        }
        for event in events {
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func pasteShortcutEvents() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return nil
        }
        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        return [commandDown, keyDown, keyUp, commandUp]
    }
}
