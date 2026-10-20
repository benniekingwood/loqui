import CoreML
import FluidAudio
import Foundation
import LoquiCore

/// Loqui's speech backend: Parakeet TDT 0.6B v2 running on device through
/// FluidAudio. This module is the only code that imports FluidAudio, so a
/// backend upgrade or replacement stays inside it.
///
/// All weights remain resident. Every pass, draft or final, gets its own
/// decoder state so cancelling a draft cannot corrupt the final transcript.
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
        await tracked { await self.performTranscription(of: .file(audioURL)) }
    }

    package nonisolated func transcribe(samples: [Float]) async -> TranscriptionOutcome {
        await tracked { await self.performTranscription(of: .samples(samples)) }
    }

    package nonisolated func cancelActiveTranscriptions() {
        work.cancelAll()
    }

    private enum Audio {
        case file(URL)
        case samples([Float])
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

    private func performTranscription(of audio: Audio) async -> TranscriptionOutcome {
        do {
            try Task.checkCancellation()
            let result: String
            switch audio {
            case let .file(url):
                let validator = audioValidator
                let validation = await Task.detached(priority: .utility) { validator.validateAudio(at: url) }.value
                if case let .invalid(failure) = validation { return .invalidAudio(failure) }
                _ = try await prepareBackend(forceRevalidation: false)
                try Task.checkCancellation()
                result = try await recognizer.transcribe(audioURL: url)
            case let .samples(samples):
                let duration = TimeInterval(samples.count) / TimeInterval(Self.sampleRate)
                guard duration >= audioValidator.minimumUsefulDuration else {
                    return .invalidAudio(.tooShort(duration: duration))
                }
                _ = try await prepareBackend(forceRevalidation: false)
                try Task.checkCancellation()
                result = try await recognizer.transcribe(samples: samples)
            }
            try Task.checkCancellation()
            let text = TranscriptOutputClassifier.clean(result)
            return text.isEmpty ? .noSpeech : .success(text)
        } catch is CancellationError {
            return .cancelled
        } catch let failure as SpeechModelFailure {
            return Task.isCancelled ? .cancelled : .modelUnavailable(failure)
        } catch {
            return Task.isCancelled ? .cancelled : .inferenceFailed(TranscriptionDiagnostic(error: error))
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

package protocol ParakeetRecognizing: Sendable {
    func validateHardware() async throws
    func loadModels(at directory: URL) async throws
    func transcribe(audioURL: URL) async throws -> String
    func transcribe(samples: [Float]) async throws -> String
}

package extension ParakeetRecognizing {
    func validateHardware() async throws {}
}

private actor FluidAudioParakeetRecognizer: ParakeetRecognizing {
    private var models: AsrModels?
    private var modelURL: URL?
    private var loading: (url: URL, task: Task<AsrModels, any Error>)?

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
            if models != nil, modelURL == directory { return }
            if let pending = loading {
                let loaded = try await pending.task.value
                models = loaded
                modelURL = pending.url
                loading = nil
                if pending.url == directory { return }
            }
            let task = Task.detached(priority: .userInitiated) {
                let configuration = AsrModels.defaultConfiguration()
                return try AsrModels.loadLocal(from: directory, version: .v2, configuration: configuration)
            }
            loading = (directory, task)
            do {
                let loaded = try await task.value
                models = loaded
                modelURL = directory
                loading = nil
            } catch {
                loading = nil
                throw error
            }
        #endif
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let models else { throw ASRError.notInitialized }
        let manager = AsrManager(models: models)
        var decoder = TdtDecoderState.make(decoderLayers: models.version.decoderLayers)
        return try await manager.transcribe(audioURL, decoderState: &decoder).text
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let models else { throw ASRError.notInitialized }
        let manager = AsrManager(models: models)
        var decoder = TdtDecoderState.make(decoderLayers: models.version.decoderLayers)
        return try await manager.transcribe(samples, decoderState: &decoder).text
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
