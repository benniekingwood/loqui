import Foundation
import os

package struct PasteTarget: Equatable, Sendable {
    package let processIdentifier: pid_t
    package let bundleIdentifier: String?
    package let launchDate: Date
    package let bundleURL: URL?

    package init?(processIdentifier: pid_t, bundleIdentifier: String?, launchDate: Date?, bundleURL: URL?) {
        guard let launchDate else {
            return nil
        }
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.launchDate = launchDate
        self.bundleURL = bundleURL
    }
}

package enum PasteboardSnapshotFailure: Error, Equatable, Sendable {
    case clipboardChanged
    case representationReadFailed(type: String)
}

package enum PasteboardMutationFailure: Equatable, Sendable {
    case clearFailed
    case writeFailed
    case verificationFailed
    case representationWriteFailed(type: String)
}

package enum ClipboardRestorationOutcome: Equatable, Sendable {
    case restored
    case skippedBecauseClipboardChanged
    case failed(PasteboardMutationFailure)
}

package enum ManualPasteReason: Equatable, Sendable {
    case noSessionTarget
    case targetExited
    case targetIdentityChanged
    case targetHasNoWindow
    case targetCouldNotBeVerified
    case eventPermissionDenied
    case activationFailed
    case eventPostFailed
    case liveDraftChanged
}

package enum DeliveryFailure: Equatable, Sendable {
    case pasteboardSnapshotFailed(PasteboardSnapshotFailure)
    case pasteboardWriteFailed(PasteboardMutationFailure, restoration: ClipboardRestorationOutcome)
}

package enum DeliveryOutcome: Equatable, Sendable {
    case inserted
    case pasted(restoration: ClipboardRestorationOutcome)
    case copiedForManualPaste(ManualPasteReason)
    /// The target app's focus is clearly not a text field. Nothing was typed,
    /// pasted, or copied; the transcript is offered on screen instead.
    case noTextInput
    case failed(DeliveryFailure)
    case cancelled(restoration: ClipboardRestorationOutcome?)
}

@MainActor
package protocol TextDelivering: AnyObject {
    func captureCurrentTarget(excludingBundleIdentifier: String?) -> PasteTarget?
    func updateLiveTranscript(_ text: String, in target: PasteTarget?) async -> Bool
    func finalizeLiveTranscript(_ text: String, in target: PasteTarget?) async -> DeliveryOutcome
    func cancelLiveTranscript()
    func deliver(_ text: String, to target: PasteTarget?) async -> DeliveryOutcome
}

package extension TextDelivering {
    func updateLiveTranscript(_ text: String, in target: PasteTarget?) async -> Bool {
        false
    }

    func finalizeLiveTranscript(_ text: String, in target: PasteTarget?) async -> DeliveryOutcome {
        await deliver(text, to: target)
    }

    func cancelLiveTranscript() {}
}

/// A finished transcript that did not land at a cursor.
package struct UnplacedTranscript: Equatable, Sendable {
    package enum Reason: Equatable, Sendable {
        /// Nothing was copied; the card's Copy button is the only way to use it.
        case noTextInput
        /// Already on the clipboard because automatic paste was not possible.
        case copiedToClipboard
    }

    package let text: String
    package let reason: Reason

    package init(text: String, reason: Reason) {
        self.text = text
        self.reason = reason
    }

    package init?(text: String, outcome: DeliveryOutcome) {
        switch outcome {
        case .noTextInput:
            self.init(text: text, reason: .noTextInput)
        case .copiedForManualPaste:
            self.init(text: text, reason: .copiedToClipboard)
        case .inserted, .pasted, .failed, .cancelled:
            return nil
        }
    }
}
