import AppKit
import Combine
import LoquiAudio
import LoquiCore
import LoquiInterface
import LoquiShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let transcriptionEngine: TranscriptionEngine
    let hotKeyController: HotKeyController
    let audioInputSelection: AudioInputSelection
    private var engineStateObservation: AnyCancellable?
    private var shortcutObservation: AnyCancellable?
    private lazy var recordingOverlay = RecordingOverlayController(engine: transcriptionEngine)
    private lazy var transcriptCard = TranscriptCardController(engine: transcriptionEngine)
    private lazy var settingsWindowController = SettingsWindowController(
        transcriptionEngine: transcriptionEngine,
        hotKeyController: hotKeyController,
        audioInputSelection: audioInputSelection
    )

    override convenience init() {
        self.init(environment: .live())
    }

    init(environment: AppEnvironment) {
        transcriptionEngine = environment.transcriptionEngine
        hotKeyController = environment.hotKeyController
        audioInputSelection = environment.audioInputSelection
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutObservation = hotKeyController.$shortcut
            .sink { [weak self] shortcut in
                self?.transcriptionEngine.shortcut = shortcut
            }
        hotKeyController.register { [weak self] intent in
            switch intent {
            case .start:
                self?.transcriptionEngine.startRecording()
            case .stop:
                self?.transcriptionEngine.stopRecording()
            }
        }
        engineStateObservation = transcriptionEngine.$state
            .removeDuplicates()
            .sink { [weak self] state in
                switch state {
                case .idle, .stopping, .transcribing, .delivering, .failed:
                    self?.hotKeyController.recordingSessionDidEnd()
                case .requestingPermission, .starting, .recording:
                    break
                }
            }
        recordingOverlay.start()
        transcriptCard.start()
        transcriptionEngine.prepareDependencies()
    }

    /// Loqui has no main window, so clicking its Dock icon opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        settingsWindowController.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engineStateObservation?.cancel()
        engineStateObservation = nil
        shortcutObservation?.cancel()
        shortcutObservation = nil
        recordingOverlay.stop()
        transcriptCard.stop()
        hotKeyController.unregister()
        // This call is intentionally synchronous: it does not return until an
        // active transcription has been cancelled.
        transcriptionEngine.cleanup()
    }
}
