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
        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandDown.postToPid(target.processIdentifier)
        keyDown.postToPid(target.processIdentifier)
        keyUp.postToPid(target.processIdentifier)
        commandUp.postToPid(target.processIdentifier)
        return true
    }
}
