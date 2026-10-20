import LoquiCore

/// Plays after the microphone closes without delaying final transcription.
@MainActor
package final class SystemRecordingStoppedCuePlayer: RecordingStoppedCuePlaying {
    private let audio = RecordingCueAudio(ascending: false)
    private let isEnabled: @MainActor () -> Bool
    private var task: Task<Void, Never>?

    package init(isEnabled: @escaping @MainActor () -> Bool = { RecordingCuePreference.isEnabled() }) {
        self.isEnabled = isEnabled
    }

    package func play() {
        task?.cancel()
        guard isEnabled() else { return }
        task = Task { await audio.play() }
    }

    package func stop() {
        task?.cancel()
        task = nil
        audio.stop()
    }
}
