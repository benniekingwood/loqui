import ApplicationServices
import AppKit
import Foundation
import LoquiCore

@MainActor
package final class SystemAccessibilityService: AccessibilityServing {
    package func ensurePermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    package func insert(_ text: String, into target: PasteTarget) -> AccessibilityInsertionOutcome {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )

        guard focusError == .success, let focusedElementValue else {
            return focusError == .success
                ? .noFocusedElement
                : .failed(errorCode: focusError.rawValue)
        }

        let focusedElement = unsafeDowncast(focusedElementValue, to: AXUIElement.self)
        var focusedProcessIdentifier: pid_t = 0
        let pidError = AXUIElementGetPid(focusedElement, &focusedProcessIdentifier)
        guard pidError == .success else {
            return .failed(errorCode: pidError.rawValue)
        }
        guard focusedProcessIdentifier == target.processIdentifier else {
            return .targetNotFocused
        }

        var valueSettable = DarwinBoolean(false)
        let valueSettableError = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueSettable
        )
        guard valueSettableError == .success else {
            return .failed(errorCode: valueSettableError.rawValue)
        }
        guard valueSettable.boolValue else {
            return .valueNotWritable
        }

        var currentValueRef: CFTypeRef?
        let currentValueError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValueRef
        )
        guard currentValueError == .success else {
            return .failed(errorCode: currentValueError.rawValue)
        }

        let currentValue = (currentValueRef as? String) ?? ""
        let currentNSString = currentValue as NSString
        let insertedNSString = text as NSString
        var selectedRange = copySelectedTextRange(from: focusedElement)
            ?? CFRange(location: currentNSString.length, length: 0)
        selectedRange.location = max(0, min(selectedRange.location, currentNSString.length))
        selectedRange.length = max(
            0,
            min(selectedRange.length, currentNSString.length - selectedRange.location)
        )
        let replacementRange = NSRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        let updatedValue = currentNSString.replacingCharacters(
            in: replacementRange,
            with: text
        )
        let setValueError = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        )
        guard setValueError == .success else {
            return .failed(errorCode: setValueError.rawValue)
        }
        var insertionRange = CFRange(
            location: selectedRange.location + insertedNSString.length,
            length: 0
        )
        if let insertionValue = AXValueCreate(.cfRange, &insertionRange) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                insertionValue
            )
        }
        return .inserted
    }

    package func focusedInputKind(in target: PasteTarget) -> FocusedInputKind {
        FocusedInputKind.focused(in: target)
    }

    package func windowAvailability(of target: PasteTarget) -> TargetWindowAvailability {
        let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        guard result == .success else {
            return .unavailable(errorCode: result.rawValue)
        }
        guard let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            return .closed
        }
        return .available
    }

    private func copySelectedTextRange(from element: AXUIElement) -> CFRange? {
        var selectedRangeRef: CFTypeRef?
        let selectionError = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        )
        guard selectionError == .success,
              let selectedRangeRef,
              CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = unsafeDowncast(selectedRangeRef, to: AXValue.self)
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        return AXValueGetValue(rangeValue, .cfRange, &range) ? range : nil
    }
}
