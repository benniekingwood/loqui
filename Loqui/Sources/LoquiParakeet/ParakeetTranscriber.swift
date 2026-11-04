import AVFoundation
import CoreML
import FluidAudio
import Foundation
import LoquiCore

/// Loqui's speech backend: Parakeet Unified English 0.6B running on device
/// through FluidAudio. This module is the only code that imports FluidAudio, so
/// a backend upgrade or replacement stays inside it.
///
/// The model decodes a stream: a dictation's drafts feed it the audio as it is
/// captured, and the final transcript only flushes what they did not reach. One
/// stream is live at a time, and its calls run strictly in order. A final pass
/// with no healthy stream behind it streams the whole recording instead.
package actor ParakeetTranscriber: SpeechTranscribing, SpeechModelPreflighting {
    package static let displayName = "Parakeet"
    /// 16 kHz mono, the rate FluidAudio's Parakeet models consume directly.
    package static let sampleRate = 16000
    /// A verified model is re-checked on disk at most this often. Live drafts
    /// run several times a second and must not stat every model file each time.
    package static let revalidationInterval: TimeInterval = 30

    private let resolver: any ParakeetModelResolving
    private let audioValidator: any AudioValidating
    private let recognizer: any ParakeetRecognizing
    private let now: @Sendable () -> Date
    private nonisolated let work = TranscriptionWorkRegistry()
    private var verified: (location: ParakeetModelLocation, at: Date)?
    private var stream: LiveStream?
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private struct LiveStream {
        let identifier: UUID
        /// Captured samples already handed to the pause cap.
        var consumed = 0
        var pauses = PauseCap()
    }

    package init(
        resolver: any ParakeetModelResolving = ParakeetModelResolver(),
        audioValidator: any AudioValidating = RecordedAudioValidator(),
        recognizer: any ParakeetRecognizing = FluidAudioParakeetRecognizer(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.resolver = resolver
        self.audioValidator = audioValidator
        self.recognizer = recognizer
        self.now = now
    }

    /// Call once at app startup, before any SDK logger or loader is constructed.
    package static func configureRuntime() {
        ModelHub.offlineMode = true
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
    }

    package func preflightSpeechModel() async -> SpeechModelPreflightResult {
        do {
            return try await .ready(prepareBackend(forceRevalidation: true).readiness)
        } catch let failure as SpeechModelFailure {
            return .failure(failure)
        } catch {
            return .failure(.modelLoadFailed(TranscriptionDiagnostic(error: error)))
        }
    }

    package nonisolated func transcribe(audioURL: URL) async -> TranscriptionOutcome {
        await tracked { await self.performFinal(continuing: nil, audioURL: audioURL) }
    }

    package nonisolated func transcribe(samples: [Float]) async -> TranscriptionOutcome {
        await tracked { await self.performTranscription(of: samples) }
    }

    package func beginStream() async -> (any SpeechStreaming)? {
        await exclusively {
            do {
                _ = try await prepareBackend(forceRevalidation: false)
                try await recognizer.resetStream()
            } catch {
                stream = nil
                return nil
            }
            let identifier = UUID()
            stream = LiveStream(identifier: identifier)
            return ParakeetStream(identifier: identifier, transcriber: self)
        }
    }

    package nonisolated func cancelActiveTranscriptions() {
        work.cancelAll()
    }

    // MARK: Streaming

    fileprivate nonisolated func draft(stream identifier: UUID, samples: [Float]) async -> TranscriptionOutcome {
        await tracked { await self.performDraft(stream: identifier, samples: samples) }
    }

    fileprivate nonisolated func finish(stream identifier: UUID, audioURL: URL) async -> TranscriptionOutcome {
        await tracked { await self.performFinal(continuing: identifier, audioURL: audioURL) }
    }

    fileprivate func end(stream identifier: UUID) {
        if stream?.identifier == identifier { stream = nil }
    }

    private func performDraft(stream identifier: UUID, samples: [Float]) async -> TranscriptionOutcome {
        await exclusively {
            guard var live = stream, live.identifier == identifier else { return .cancelled }
            guard samples.count > live.consumed else { return .cancelled }
            let admitted = live.pauses.admit(samples[live.consumed...])
            live.consumed = samples.count
            stream = live
            // A cancelled draft still streams its audio; only its text is dropped.
            return await decode {
                try await recognizer.stream(admitted)
            } onFailure: {
                // Audio may be lost mid-stream, so the final pass starts over.
                end(stream: identifier)
            }
        }
    }

    /// Flushes the live stream with the rest of the recording, or streams the
    /// whole recording when there is no healthy stream to continue.
    private func performFinal(continuing identifier: UUID?, audioURL: URL) async -> TranscriptionOutcome {
        let validator = audioValidator
        let validation = await Task.detached(priority: .utility) { validator.validateAudio(at: audioURL) }.value
        if case let .invalid(failure) = validation { return .invalidAudio(failure) }
        return await exclusively {
            let continuing = stream.flatMap { $0.identifier == identifier ? $0 : nil }
            stream = nil
            return await decode {
                _ = try await prepareBackend(forceRevalidation: false)
                try Task.checkCancellation()
                let recording = try await recognizer.samples(of: audioURL)
                var live = continuing ?? LiveStream(identifier: UUID())
                if continuing == nil || recording.count < live.consumed {
                    try await recognizer.resetStream()
                    live = LiveStream(identifier: live.identifier)
                }
                var admitted = live.pauses.admit(recording[live.consumed...])
                admitted += live.pauses.flush()
                _ = try await recognizer.stream(admitted)
                try Task.checkCancellation()
                return try await recognizer.finishStream()
            }
        }
    }

    /// A one-off pass over in-memory samples. It ends any live stream.
    private func performTranscription(of samples: [Float]) async -> TranscriptionOutcome {
        let duration = TimeInterval(samples.count) / TimeInterval(Self.sampleRate)
        guard duration >= audioValidator.minimumUsefulDuration else {
            return .invalidAudio(.tooShort(duration: duration))
        }
        return await exclusively {
            stream = nil
            return await decode {
                _ = try await prepareBackend(forceRevalidation: false)
                try Task.checkCancellation()
                try await recognizer.resetStream()
                var pauses = PauseCap()
                _ = try await recognizer.stream(pauses.admit(samples[...]) + pauses.flush())
                try Task.checkCancellation()
                return try await recognizer.finishStream()
            }
        }
    }

    /// Runs `operation` and classifies its text. `onFailure` runs only when it
    /// throws, not when the caller was cancelled after it finished.
    private func decode(
        _ operation: () async throws -> String,
        onFailure: () -> Void = {}
    ) async -> TranscriptionOutcome {
        let result: String
        do {
            result = try await operation()
        } catch {
            onFailure()
            if error is CancellationError || Task.isCancelled { return .cancelled }
            if let failure = error as? SpeechModelFailure { return .modelUnavailable(failure) }
            return .inferenceFailed(TranscriptionDiagnostic(error: error))
        }
        if Task.isCancelled { return .cancelled }
        let text = TranscriptOutputClassifier.clean(result)
        return text.isEmpty ? .noSpeech : .success(text)
    }

    /// Runs `operation` once every earlier call has finished. The recognizer
    /// holds one stream, and actor reentrancy would otherwise let a draft and the
    /// final flush interleave at their awaits.
    private func exclusively<T: Sendable>(_ operation: () async -> T) async -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
        return await operation()
    }

    /// Runs one pass in its own task so `cancelActiveTranscriptions` can stop it
    /// even though the actor is busy awaiting the recognizer.
    private nonisolated func tracked(
        _ operation: @escaping @Sendable () async -> TranscriptionOutcome
    ) async -> TranscriptionOutcome {
        let task = Task { await operation() }
        let identifier = work.register { task.cancel() }
        defer { work.remove(identifier) }
        return await withTaskCancellationHandler {
            if Task.isCancelled { task.cancel() }
            return await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func prepareBackend(forceRevalidation: Bool) async throws -> ParakeetModelLocation {
        try await recognizer.validateHardware()
        if !forceRevalidation, let verified, now().timeIntervalSince(verified.at) < Self.revalidationInterval {
            return verified.location
        }
        let location: ParakeetModelLocation
        switch resolver.preflight() {
        case let .failure(failure):
            verified = nil
            throw failure
        case let .ready(value): location = value
        }
        do {
            try await recognizer.loadModels(at: location.model.url)
            verified = (location, now())
            return location
        } catch let failure as SpeechModelFailure {
            throw failure
        } catch {
            throw SpeechModelFailure.modelLoadFailed(TranscriptionDiagnostic(error: error))
        }
    }
}

/// A dictation's handle on the transcriber's live stream. A call on a stream
/// that has been replaced or ended does nothing.
private struct ParakeetStream: SpeechStreaming {
    let identifier: UUID
    let transcriber: ParakeetTranscriber

    func draft(from samples: [Float]) async -> TranscriptionOutcome {
        await transcriber.draft(stream: identifier, samples: samples)
    }

    func finish(audioURL: URL) async -> TranscriptionOutcome {
        await transcriber.finish(stream: identifier, audioURL: audioURL)
    }

    func cancel() {
        Task { [transcriber, identifier] in await transcriber.end(stream: identifier) }
    }
}

/// Holds back most of each long pause. Parakeet's stream can drop the words
/// after a pause longer than its 5.6 s left context (12 s cost a word and 30 s
/// a whole sentence on our clips), so only the first `maximumPauseSeconds` of
/// a pause is streamed.
///
/// Audio is judged in 100 ms chunks. A chunk is part of a pause when it is
/// within 12 dB of the quietest chunk so far and below -50 dBFS, so speech never
/// counts as a pause, and in a noisy room nothing is held back.
package struct PauseCap: Sendable {
    package static let chunkSamples = 1600
    package static let maximumPauseSeconds = 2.0
    private static let pauseMargin: Float = 12
    private static let pauseCeiling: Float = -50

    private var pending: [Float] = []
    private var quietestLevel = Float.infinity
    private var pauseSamples = 0

    package init() {}

    /// The samples to stream from `samples`. A partial chunk waits for the
    /// next call or `flush()`.
    package mutating func admit(_ samples: ArraySlice<Float>) -> [Float] {
        pending.append(contentsOf: samples)
        var admitted: [Float] = []
        admitted.reserveCapacity(pending.count)
        var start = 0
        while pending.count - start >= Self.chunkSamples {
            let chunk = pending[start ..< start + Self.chunkSamples]
            if admits(chunk) { admitted.append(contentsOf: chunk) }
            start += Self.chunkSamples
        }
        pending.removeFirst(start)
        return admitted
    }

    /// The partial chunk left at the end of the recording, always streamed.
    package mutating func flush() -> [Float] {
        defer { pending = [] }
        return pending
    }

    private mutating func admits(_ chunk: ArraySlice<Float>) -> Bool {
        let power = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let level = 10 * log10(max(power, 1e-14))
        quietestLevel = min(quietestLevel, level)
        guard level < min(quietestLevel + Self.pauseMargin, Self.pauseCeiling) else {
            pauseSamples = 0
            return true
        }
        pauseSamples += chunk.count
        return Double(pauseSamples) <= Self.maximumPauseSeconds * Double(ParakeetTranscriber.sampleRate)
    }
}

/// The decoding primitives the transcriber drives. One stream at a time.
package protocol ParakeetRecognizing: Sendable {
    func validateHardware() async throws
    func loadModels(at directory: URL) async throws
    /// The recording as 16 kHz mono samples.
    func samples(of audioURL: URL) async throws -> [Float]
    /// Clears the stream for a new dictation.
    func resetStream() async throws
    /// Appends `samples`, decodes what is ready, and returns the text so far.
    func stream(_ samples: [Float]) async throws -> String
    /// Decodes the rest of the stream and returns the final text.
    func finishStream() async throws -> String
}

package extension ParakeetRecognizing {
    func validateHardware() async throws {}
}

private actor FluidAudioParakeetRecognizer: ParakeetRecognizing {
    /// The 1.12 s tier: [70, 7, 7] encoder frames of left context, chunk, and
    /// look-ahead. It matched the default 2.08 s tier word for word on our
    /// clips with half the draft lag (issue #13).
    static let streamingConfig = UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7)

    private var manager: StreamingUnifiedAsrManager?
    private var modelURL: URL?
    private var loading: (url: URL, task: Task<StreamingUnifiedAsrManager, any Error>)?

    func validateHardware() async throws {
        // Core ML prediction crashes under Rosetta for these assets. Keep the
        // universal executable launchable, but require native Apple Silicon ASR.
        #if arch(x86_64)
            throw SpeechModelFailure.unsupportedHardware
        #endif
    }

    func loadModels(at directory: URL) async throws {
        try await validateHardware()
        #if arch(arm64)
            if manager != nil, modelURL == directory { return }
            if let pending = loading {
                let loaded = try await pending.task.value
                manager = loaded
                modelURL = pending.url
                loading = nil
                if pending.url == directory { return }
            }
            let task = Task.detached(priority: .userInitiated) {
                let manager = StreamingUnifiedAsrManager(config: Self.streamingConfig)
                try await manager.loadModels(from: directory)
                return manager
            }
            loading = (directory, task)
            do {
                let loaded = try await task.value
                manager = loaded
                modelURL = directory
                loading = nil
            } catch {
                loading = nil
                throw error
            }
        #endif
    }

    func samples(of audioURL: URL) async throws -> [Float] {
        try AudioConverter().resampleAudioFile(audioURL)
    }

    func resetStream() async throws {
        guard let manager else { throw ASRError.notInitialized }
        try await manager.reset()
    }

    func stream(_ samples: [Float]) async throws -> String {
        guard let manager else { throw ASRError.notInitialized }
        if !samples.isEmpty {
            try await manager.appendAudio(Self.buffer(for: samples))
            try await manager.processBufferedAudio()
        }
        return await manager.getPartialTranscript()
    }

    func finishStream() async throws -> String {
        guard let manager else { throw ASRError.notInitialized }
        return try await manager.finish()
    }

    private static func buffer(for samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(ParakeetTranscriber.sampleRate),
            channels: 1,
            interleaved: false
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0] else {
            throw ASRError.processingFailed("Could not allocate an audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}

private final class TranscriptionWorkRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations: [UUID: @Sendable () -> Void] = [:]

    func register(_ cancel: @escaping @Sendable () -> Void) -> UUID {
        let identifier = UUID()
        lock.withLock { cancellations[identifier] = cancel }
        return identifier
    }

    func remove(_ identifier: UUID) {
        lock.withLock { _ = cancellations.removeValue(forKey: identifier) }
    }

    func cancelAll() {
        let pending = lock.withLock { Array(cancellations.values) }
        pending.forEach { $0() }
    }
}

/// The entry point the app uses to build its speech backend.
package enum ParakeetSpeechBackend {
    package static let displayName = ParakeetTranscriber.displayName

    /// Configures FluidAudio for offline, quiet operation, then returns a
    /// transcriber that also performs the model preflight.
    package static func make() -> ParakeetTranscriber {
        ParakeetTranscriber.configureRuntime()
        return ParakeetTranscriber()
    }
}
