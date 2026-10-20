import AppKit

/// Shared behavior for Loqui's floating panels, the recording indicator and the
/// transcript card: above every app and Space, never activating Loqui, and
/// placed just above the Dock on the screen the pointer is on.
@MainActor
package enum FloatingPanel {
    package static let bottomMargin: CGFloat = 12

    package static func configure(_ panel: NSPanel) {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    /// Centers a panel of `size` at the bottom of the pointer's screen, above the Dock.
    package static func frameAboveDock(size: NSSize, pointer: NSPoint = NSEvent.mouseLocation) -> NSRect? {
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return nil }
        return frameAboveDock(size: size, in: visibleFrame)
    }

    package static func frameAboveDock(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            origin: NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + bottomMargin),
            size: size
        )
    }
}
