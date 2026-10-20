import AppKit
import SwiftUI
import LoquiAudio
import LoquiCore
import LoquiShortcuts

/// Owns Loqui's single Settings window. The window is created once and reused,
/// and it brings Loqui forward because a menu bar app is rarely active.
@MainActor
package final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let transcriptionEngine: TranscriptionEngine
    private let hotKeyController: HotKeyController
    private let audioInputSelection: AudioInputSelection
    private let shortcutRecorder: ShortcutRecorder
    private var window: NSWindow?

    package init(
        transcriptionEngine: TranscriptionEngine,
        hotKeyController: HotKeyController,
        audioInputSelection: AudioInputSelection
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.hotKeyController = hotKeyController
        self.audioInputSelection = audioInputSelection
        shortcutRecorder = ShortcutRecorder(hotKeyController: hotKeyController)
        super.init()
    }

    package func show() {
        let window = window ?? makeWindow()
        self.window = window
        audioInputSelection.refreshDevices()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    package func windowWillClose(_ notification: Notification) {
        shortcutRecorder.cancel()
    }

    private func makeWindow() -> NSWindow {
        let rootView = SettingsView(recorder: shortcutRecorder)
            .environmentObject(transcriptionEngine)
            .environmentObject(hotKeyController)
            .environmentObject(audioInputSelection)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        // Size to the form before centering, or the window grows off-center
        // when SwiftUI lays it out.
        window.setContentSize(hostingController.view.fittingSize)
        window.title = "Loqui Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("LoquiSettings")
        if !window.setFrameUsingName("LoquiSettings") {
            window.center()
        }
        return window
    }
}
