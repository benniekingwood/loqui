import Foundation
import LoquiAudio
import LoquiCore
import LoquiDelivery
import LoquiParakeet
import LoquiShortcuts

/// The composition root: the one place that picks concrete implementations.
/// Every module above talks to the others through `LoquiCore` contracts, so
/// swapping the speech backend or the delivery strategy is a change here only.
@MainActor
struct AppEnvironment {
    let audioInputSelection: AudioInputSelection
    let transcriptionEngine: TranscriptionEngine
    let hotKeyController: HotKeyController

    static func live() -> AppEnvironment {
        let audioInputSelection = AudioInputSelection()
        let speech = ParakeetSpeechBackend.make()

        let recordingFileStore: any RecordingFileStoring
        let startupPresentation: TranscriptionEngine.Presentation?
        do {
            recordingFileStore = try TemporaryRecordingFileStore()
            startupPresentation = nil
        } catch {
            recordingFileStore = UnavailableRecordingFileStore()
            startupPresentation = TranscriptionEngine.Presentation(
                state: .failed,
                statusText: "Temporary recording storage is unavailable. Restart Loqui."
            )
        }

        let engine = TranscriptionEngine(
            permissionProvider: SystemMicrophonePermissionProvider(),
            recorderFactory: SystemAudioRecorderFactory(inputResolver: audioInputSelection),
            recordingReadyCue: SystemRecordingReadyCuePlayer(),
            recordingStoppedCue: SystemRecordingStoppedCuePlayer(),
            recordingFileStore: recordingFileStore,
            dependencyPreflight: speech,
            transcriber: speech,
            textDelivery: TextDeliveryService(),
            speechModelName: ParakeetSpeechBackend.displayName,
            applicationBundleIdentifier: Bundle.main.bundleIdentifier,
            startupPresentation: startupPresentation
        )
        return AppEnvironment(
            audioInputSelection: audioInputSelection,
            transcriptionEngine: engine,
            hotKeyController: HotKeyController()
        )
    }
}
