import ApplicationServices
import AppKit
import Foundation
import LoquiCore

@MainActor
package final class TextDeliveryService: TextDelivering {
    private let workspace: any WorkspaceServing
    private let accessibility: any AccessibilityServing
    private let pasteboard: any PasteboardServing
    private let eventPoster: any PasteEventPosting
    private let liveTextEditor: any LiveTextEditing
    private let sleeper: any DeliverySleeping
    private let activationAttempts: Int
    private let activationRetryDelay: TimeInterval
    private let restorationDelay: TimeInterval
    private var clipboardTransactionActive = false
    private struct ClipboardWaiter {
        let identifier: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var clipboardWaiters: [ClipboardWaiter] = []
    private var pendingClipboardWaiterRegistrations: Set<UUID> = []
    private var cancelledClipboardWaiters: Set<UUID> = []

    package init(
        workspace: any WorkspaceServing = SystemWorkspaceService(),
        accessibility: any AccessibilityServing = SystemAccessibilityService(),
        pasteboard: any PasteboardServing = SystemPasteboardService(),
        eventPoster: any PasteEventPosting = SystemPasteEventPoster(),
        liveTextEditor: any LiveTextEditing = SystemLiveTextEditor(),
        sleeper: any DeliverySleeping = SystemDeliverySleeper(),
        activationAttempts: Int = 7,
        activationRetryDelay: TimeInterval = 0.15,
        restorationDelay: TimeInterval = 0.75
    ) {
        self.workspace = workspace
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.liveTextEditor = liveTextEditor
        self.sleeper = sleeper
        self.activationAttempts = max(1, activationAttempts)
        self.activationRetryDelay = max(0, activationRetryDelay)
        self.restorationDelay = max(0, restorationDelay)
    }

    package func captureCurrentTarget(excludingBundleIdentifier: String?) -> PasteTarget? {
        workspace.currentExternalTarget(excludingBundleIdentifier: excludingBundleIdentifier)
    }

    package func updateLiveTranscript(_ text: String, in target: PasteTarget?) async -> Bool {
        guard let target else {
            liveTextLogger.debug("Live draft skipped; no target app")
            return false
        }
        guard workspace.availability(of: target) == .available else {
            liveTextLogger.debug("Live draft skipped; target app changed")
            return false
        }
        guard accessibility.ensurePermission(prompt: true) else {
            liveTextLogger.debug("Live draft skipped; Accessibility is not granted")
            return false
        }
        // Typing blind into a file list or a web page would trigger type-select
        // and shortcuts instead of entering text.
        guard accessibility.focusedInputKind(in: target) != .notText else {
            liveTextLogger.debug("Live draft skipped; no text field is focused")
            return false
        }
        return await liveTextEditor.update(text, in: target) == .updated
    }

    package func finalizeLiveTranscript(_ text: String, in target: PasteTarget?) async -> DeliveryOutcome {
        guard !Task.isCancelled else {
            return .cancelled(restoration: nil)
        }
        if let target,
           workspace.availability(of: target) == .available,
           accessibility.ensurePermission(prompt: true) {
            switch await liveTextEditor.finalize(text, in: target) {
            case .finalized:
                return .inserted
            case .noActiveDraft, .unavailable:
                break
            }
        }
        if await liveTextEditor.cancel() == .unavailable {
            let outcome = await deliver(text, to: nil)
            if case .copiedForManualPaste = outcome { return .copiedForManualPaste(.liveDraftChanged) }
            return outcome
        }
        if let target, workspace.availability(of: target) == .available,
           accessibility.focusedInputKind(in: target) == .notText {
            return .noTextInput
        }
        return await deliver(text, to: target)
    }

    package func cancelLiveTranscript() {
        let editor = liveTextEditor
        Task { _ = await editor.cancel() }
    }

    package func deliver(_ text: String, to target: PasteTarget?) async -> DeliveryOutcome {
        guard !Task.isCancelled else {
            return .cancelled(restoration: nil)
        }
        if let target,
           workspace.availability(of: target) == .available,
           accessibility.ensurePermission(prompt: true),
           accessibility.insert(text, into: target) == .inserted {
            return .inserted
        }
        guard await acquireClipboardTransaction() else {
            return .cancelled(restoration: nil)
        }
        defer { releaseClipboardTransaction() }
        guard !Task.isCancelled else {
            return .cancelled(restoration: nil)
        }
        let originalContents: PasteboardSnapshot
        switch pasteboard.snapshot() {
        case let .success(snapshot):
            originalContents = snapshot
        case let .failure(failure):
            return .failed(.pasteboardSnapshotFailed(failure))
        }
        let replacement = pasteboard.replaceContents(with: text)
        let transientChangeCount: Int
        switch replacement {
        case let .replaced(changeCount):
            transientChangeCount = changeCount
        case let .failed(failure, currentChangeCount):
            let restoration = pasteboard.restore(originalContents, ifUnchangedSince: currentChangeCount)
            return .failed(.pasteboardWriteFailed(failure, restoration: restoration))
        }

        if Task.isCancelled {
            return .cancelled(restoration: pasteboard.restore(originalContents, ifUnchangedSince: transientChangeCount))
        }
        guard let target else {
            return .copiedForManualPaste(.noSessionTarget)
        }

        switch workspace.availability(of: target) {
        case .exited:
            return .copiedForManualPaste(.targetExited)
        case .identityChanged:
            return .copiedForManualPaste(.targetIdentityChanged)
        case .available:
            break
        }
        guard accessibility.ensurePermission(prompt: true) else {
            return .copiedForManualPaste(.targetCouldNotBeVerified)
        }
        switch accessibility.windowAvailability(of: target) {
        case .closed:
            return .copiedForManualPaste(.targetHasNoWindow)
        case .unavailable:
            return .copiedForManualPaste(.targetCouldNotBeVerified)
        case .available:
            break
        }

        guard eventPoster.ensurePermission(prompt: true) else {
            return .copiedForManualPaste(.eventPermissionDenied)
        }

        var targetConfirmedFrontmost = false
        for _ in 0..<activationAttempts {
            if Task.isCancelled {
                return .cancelled(restoration: pasteboard.restore(originalContents, ifUnchangedSince: transientChangeCount))
            }

            switch workspace.availability(of: target) {
            case .exited:
                return .copiedForManualPaste(.targetExited)
            case .identityChanged:
                return .copiedForManualPaste(.targetIdentityChanged)
            case .available:
                break
            }

            let activationOutcome = workspace.activate(target)
            switch activationOutcome {
            case .targetExited:
                return .copiedForManualPaste(.targetExited)
            case .identityChanged:
                return .copiedForManualPaste(.targetIdentityChanged)
            case .requested, .rejected:
                break
            }
            guard await sleeper.sleep(for: activationRetryDelay) else {
                return .cancelled(restoration: pasteboard.restore(originalContents, ifUnchangedSince: transientChangeCount))
            }

            if activationOutcome == .requested,
               workspace.frontmostTarget() == target {
                targetConfirmedFrontmost = true
                break
            }
        }

        guard targetConfirmedFrontmost else {
            return .copiedForManualPaste(.activationFailed)
        }

        // Re-check every identity/window condition immediately before posting.
        guard workspace.availability(of: target) == .available,
              workspace.frontmostTarget() == target else {
            return .copiedForManualPaste(.activationFailed)
        }
        switch accessibility.windowAvailability(of: target) {
        case .closed:
            return .copiedForManualPaste(.targetHasNoWindow)
        case .unavailable:
            return .copiedForManualPaste(.targetCouldNotBeVerified)
        case .available:
            break
        }
        guard eventPoster.postPasteShortcut(to: target) else {
            return .copiedForManualPaste(.eventPostFailed)
        }

        guard await sleeper.sleep(for: restorationDelay) else {
            return .cancelled(restoration: pasteboard.restore(originalContents, ifUnchangedSince: transientChangeCount))
        }
        return .pasted(restoration: pasteboard.restore(originalContents, ifUnchangedSince: transientChangeCount))
    }

    private func acquireClipboardTransaction() async -> Bool {
        guard !Task.isCancelled else {
            return false
        }
        if !clipboardTransactionActive {
            clipboardTransactionActive = true
            return true
        }

        let identifier = UUID()
        pendingClipboardWaiterRegistrations.insert(identifier)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingClipboardWaiterRegistrations.remove(identifier)
                if Task.isCancelled || cancelledClipboardWaiters.remove(identifier) != nil {
                    continuation.resume(returning: false)
                } else {
                    clipboardWaiters.append(
                        ClipboardWaiter(
                            identifier: identifier,
                            continuation: continuation
                        )
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelClipboardWaiter(identifier)
            }
        }
    }

    private func releaseClipboardTransaction() {
        guard !clipboardWaiters.isEmpty else {
            clipboardTransactionActive = false
            return
        }
        let next = clipboardWaiters.removeFirst()
        next.continuation.resume(returning: true)
    }

    private func cancelClipboardWaiter(_ identifier: UUID) {
        if let index = clipboardWaiters.firstIndex(where: { $0.identifier == identifier }) {
            let waiter = clipboardWaiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else if pendingClipboardWaiterRegistrations.contains(identifier) {
            cancelledClipboardWaiters.insert(identifier)
        }
    }
}
