import ApplicationServices
import AppKit
import Foundation
import LoquiCore

package enum TargetProcessAvailability: Equatable, Sendable {
    case available
    case exited
    case identityChanged
}

package enum TargetActivationOutcome: Equatable, Sendable {
    case requested
    case targetExited
    case identityChanged
    case rejected
}

@MainActor
package protocol WorkspaceServing: AnyObject {
    func currentExternalTarget(excludingBundleIdentifier: String?) -> PasteTarget?
    func availability(of target: PasteTarget) -> TargetProcessAvailability
    func activate(_ target: PasteTarget) -> TargetActivationOutcome
    func frontmostTarget() -> PasteTarget?
}

package enum AccessibilityInsertionOutcome: Equatable, Sendable {
    case inserted
    case targetNotFocused
    case noFocusedElement
    case valueNotWritable
    case failed(errorCode: Int32)
}

package enum TargetWindowAvailability: Equatable, Sendable {
    case available
    case closed
    case unavailable(errorCode: Int32)
}

@MainActor
package protocol AccessibilityServing: AnyObject {
    func ensurePermission(prompt: Bool) -> Bool
    func insert(_ text: String, into target: PasteTarget) -> AccessibilityInsertionOutcome
    func windowAvailability(of target: PasteTarget) -> TargetWindowAvailability
    func focusedInputKind(in target: PasteTarget) -> FocusedInputKind
}

package extension AccessibilityServing {
    func focusedInputKind(in target: PasteTarget) -> FocusedInputKind { .unknown }
}

@MainActor
package protocol PasteEventPosting: AnyObject {
    func ensurePermission(prompt: Bool) -> Bool
    func postPasteShortcut(to target: PasteTarget) -> Bool
}

package struct PasteboardItemSnapshot: Equatable, Sendable {
    package let representations: [String: Data]
}

package struct PasteboardSnapshot: Equatable, Sendable {
    package let items: [PasteboardItemSnapshot]
}

package enum PasteboardReplacementResult: Equatable, Sendable {
    case replaced(changeCount: Int)
    case failed(PasteboardMutationFailure, currentChangeCount: Int)
}

@MainActor
package protocol PasteboardServing: AnyObject {
    var changeCount: Int { get }
    func snapshot() -> Result<PasteboardSnapshot, PasteboardSnapshotFailure>
    func replaceContents(with text: String) -> PasteboardReplacementResult
    func restore(_ snapshot: PasteboardSnapshot, ifUnchangedSince changeCount: Int) -> ClipboardRestorationOutcome
}
