import Foundation
import os

private let livePreviewLogger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "live-text")

/// Owns the best-effort draft loop independently from the canonical final
/// transcription. Preview failures never stop recording or deliver partial text.
///
/// Each draft is a full pass over the audio captured so far, read straight from
/// the recorder's memory: no snapshot file is written or re-read. A pass is
/// skipped while no new audio has arrived, so a paused speaker costs nothing.
@MainActor
package final class LiveTranscriptionPreview {
    /// Shorter audio holds too little speech for a useful draft.
    package static let minimumSampleCount = 8000

    private let transcriber: any SpeechTranscribing
    private var task: Task<Void, Never>?

    package init(transcriber: any SpeechTranscribing) {
        self.transcriber = transcriber
    }

    package func start(
        interval: TimeInterval,
        samples: @escaping @MainActor () -> [Float]?,
        receiveTranscript: @escaping @MainActor (String) async -> Void
    ) {
        cleanup()
        let boundedInterval = max(0.1, interval)
        let transcriber = transcriber
        task = Task { @MainActor in
            var lastTranscript: String?
            var lastSampleCount = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(boundedInterval))
                } catch {
                    break
                }
                guard let audio = samples(),
                      audio.count >= Self.minimumSampleCount,
                      audio.count != lastSampleCount else {
                    continue
                }
                lastSampleCount = audio.count
                let outcome = await transcriber.transcribe(samples: audio)
                guard !Task.isCancelled, case let .success(transcript) = outcome,
                      transcript != lastTranscript else {
                    continue
                }
                livePreviewLogger.debug("Live draft ready; characters: \(transcript.count, privacy: .public)")
                lastTranscript = transcript
                await receiveTranscript(transcript)
            }
        }
    }

    /// Cancels the draft pass so the final flow can wait for it to wind down.
    package func stop() -> Task<Void, Never>? {
        let currentTask = task
        task = nil
        currentTask?.cancel()
        return currentTask
    }

    package func cleanup() {
        task?.cancel()
        task = nil
    }
}
