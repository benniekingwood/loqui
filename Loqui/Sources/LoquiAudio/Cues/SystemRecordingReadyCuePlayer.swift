import Foundation
import LoquiCore

/// Plays the complete ready cue before microphone capture begins.
@MainActor
package final class SystemRecordingReadyCuePlayer: RecordingReadyCuePlaying {
    private let audio = RecordingCueAudio(ascending: true)
    private let isEnabled: @MainActor () -> Bool

    package init(isEnabled: @escaping @MainActor () -> Bool = { RecordingCuePreference.isEnabled() }) {
        self.isEnabled = isEnabled
    }

    package func play() async {
        guard isEnabled() else { return }
        await audio.play()
    }

    package func stop() {
        audio.stop()
    }
}
