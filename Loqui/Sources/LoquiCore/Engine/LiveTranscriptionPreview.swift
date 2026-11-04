import Foundation
import os

private let livePreviewLogger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "live-text")

/// Owns the best-effort draft loop independently from the canonical final
/// transcription. Preview failures never stop recording or deliver partial text.
///
/// Drafts read the recorder's memory: no snapshot file is written or re-read.
/// When the backend streams, each draft decodes only the audio since the last
/// one, and the stream is handed to the final pass by `takeStream()`.
/// Otherwise each draft is a full pass over the audio captured so far. Either
/// way a draft is skipped while no new audio has arrived, so a paused speaker
/// costs nothing.
@MainActor
package final class LiveTranscriptionPreview {
    /// Shorter audio holds too little speech for a useful full-pass draft.
    package static let minimumSampleCount = 8000

    private let transcriber: any SpeechTranscribing
    private var task: Task<Void, Never>?
    private var stream: (any SpeechStreaming)?

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
        task = Task { @MainActor [weak self] in
            let stream = await transcriber.beginStream()
            guard !Task.isCancelled, let self else {
                stream?.cancel()
                return
            }
            self.stream = stream
            var lastTranscript: String?
            var lastSampleCount = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(boundedInterval))
                } catch {
                    break
                }
                guard let audio = samples(),
                      audio.count != lastSampleCount,
                      stream != nil || audio.count >= Self.minimumSampleCount else {
                    continue
                }
                lastSampleCount = audio.count
                let outcome = if let stream {
                    await stream.draft(from: audio)
                } else {
                    await transcriber.transcribe(samples: audio)
                }
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

    /// Cancels the draft loop so the final flow can start. The stream stays
    /// open for `takeStream()`.
    package func stop() -> Task<Void, Never>? {
        let currentTask = task
        task = nil
        currentTask?.cancel()
        return currentTask
    }

    /// The dictation's stream, for the final pass to finish. Nil when the
    /// backend does not stream or the stream had not started yet.
    package func takeStream() -> (any SpeechStreaming)? {
        defer { stream = nil }
        return stream
    }

    package func cleanup() {
        task?.cancel()
        task = nil
        stream?.cancel()
        stream = nil
    }
}
