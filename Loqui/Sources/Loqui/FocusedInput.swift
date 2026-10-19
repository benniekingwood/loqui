import ApplicationServices
import Foundation
import os

private let focusLogger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "delivery")

/// Whether the target app's focused element can take dictated text. `unknown`
/// keeps the existing delivery path: GPU terminals and some editors expose no
/// readable focus at all, yet accept typed text at the cursor.
enum FocusedInputKind: Equatable, Sendable {
    case text
    case notText
    case unknown

    private static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]

    /// Roles that never hold a text cursor. Containers such as AXGroup,
    /// AXScrollArea, and AXWindow are deliberately absent: some editors report
    /// them for a real text cursor.
    private static let nonTextRoles: Set<String> = [
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXRow", "AXCell",
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXSlider", "AXImage", "AXLink", "AXWebArea", "AXTabGroup",
        "AXDisclosureTriangle", "AXColorWell", "AXMenuItem", "AXToolbar",
    ]

    /// Editable web content (contenteditable, rich editors) reports an editable
    /// ancestor or a settable text selection, whatever its role.
    static func classify(
        role: String?,
        hasEditableAncestor: Bool,
        selectedTextRangeSettable: Bool
    ) -> FocusedInputKind {
        if let role, textRoles.contains(role) {
            return .text
        }
        if hasEditableAncestor || selectedTextRangeSettable {
            return .text
        }
        if let role, nonTextRoles.contains(role) {
            return .notText
        }
        return .unknown
    }

    /// Reads the system-wide focused element and classifies it, but only when it
    /// belongs to the target app. Focus in another app stays `unknown`, so the
    /// paste path can still bring the target forward.
    @MainActor
    static func focused(in target: PasteTarget) -> FocusedInputKind {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .unknown
        }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success,
              processIdentifier == target.processIdentifier else {
            return .unknown
        }

        var roleValue: CFTypeRef?
        let role = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success
            ? roleValue as? String
            : nil
        var ancestor: CFTypeRef?
        let hasEditableAncestor = AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success
            && ancestor != nil
        var settable = DarwinBoolean(false)
        let selectedTextRangeSettable = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &settable
        ) == .success && settable.boolValue

        let kind = classify(role: role, hasEditableAncestor: hasEditableAncestor, selectedTextRangeSettable: selectedTextRangeSettable)
        focusLogger.debug("Focused element role: \(role ?? "none", privacy: .public); input: \(String(describing: kind), privacy: .public)")
        return kind
    }
}

/// A finished transcript that did not land at a cursor.
struct UnplacedTranscript: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// Nothing was copied; the card's Copy button is the only way to use it.
        case noTextInput
        /// Already on the clipboard because automatic paste was not possible.
        case copiedToClipboard
    }

    let text: String
    let reason: Reason

    init(text: String, reason: Reason) {
        self.text = text
        self.reason = reason
    }

    init?(text: String, outcome: DeliveryOutcome) {
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
