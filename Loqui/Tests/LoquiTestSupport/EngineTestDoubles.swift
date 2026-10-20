import Foundation
import LoquiCore

@MainActor
package final class EngineReadyCueFake: RecordingReadyCuePlaying {
    private let completesImmediately: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    package private(set) var playCount = 0
    package private(set) var stopCount = 0

    package init(completesImmediately: Bool = true) {
        self.completesImmediately = completesImmediately
    }

    package func play() async {
        playCount += 1
        guard !completesImmediately else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    package func complete() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }

    package func stop() {
        stopCount += 1
        complete()
    }
}

@MainActor
package final class EngineStoppedCueFake: RecordingStoppedCuePlaying {
    package init() {}

    package private(set) var playCount = 0
    package private(set) var stopCount = 0
    package var onPlay: (() -> Void)?

    package func play() {
        playCount += 1
        onPlay?()
    }

    package func stop() { stopCount += 1 }
}

package final class EnginePreflightFake: SpeechModelPreflighting, @unchecked Sendable {
    private let lock = NSLock()
    private var result: SpeechModelPreflightResult?
    private var continuation: CheckedContinuation<SpeechModelPreflightResult, Never>?
    package private(set) var invocationCount = 0

    package init(result: SpeechModelPreflightResult? = EngineFixtures.readyPreflightResult) {
        self.result = result
    }

    package func preflightSpeechModel() async -> SpeechModelPreflightResult {
        let immediateResult = lock.withLock { () -> SpeechModelPreflightResult? in
            invocationCount += 1
            return result
        }
        if let immediateResult {
            return immediateResult
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    package func resolve(_ result: SpeechModelPreflightResult) {
        let continuation: CheckedContinuation<SpeechModelPreflightResult, Never>?
        lock.lock()
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

@MainActor
package final class EnginePermissionFake: MicrophonePermissionProviding {
    package var status: MicrophoneAuthorization
    package private(set) var statusCallCount = 0
    package private(set) var requestCount = 0
    private var continuation: CheckedContinuation<Bool, Never>?

    package init(status: MicrophoneAuthorization = .authorized) {
        self.status = status
    }

    package func authorizationStatus() -> MicrophoneAuthorization {
        statusCallCount += 1
        return status
    }

    package func requestAccess() async -> Bool {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    package func resolveAccess(granted: Bool) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: granted)
    }
}

@MainActor
package final class EngineRecorderFake: AudioRecording {
    package init() {}

    package var isRecording = false
    /// Loud by default so tests exercise the transcription path rather than the
    /// silence guard.
    package var peakLevel: Float = -12
    package var inputDeviceName = "Fake Microphone"
    /// In-memory audio for live drafts; one second of silence by default.
    package var samples: [Float]? = Array(repeating: 0, count: 16000)
    package var preparationResult = true
    package var completesPreparationImmediately = true
    package var startResult = true
    package var completesStartImmediately = true
    package var immediateStopOutcome: RecorderStopOutcome? = .finished
    package var onStart: (() -> Void)?
    package private(set) var maximumDurations: [TimeInterval] = []
    package private(set) var preparationCount = 0
    package private(set) var startCount = 0
    package private(set) var stopCount = 0
    package private(set) var cancelCount = 0
    private var preparationContinuation: CheckedContinuation<Bool, Never>?
    private var startContinuation: CheckedContinuation<Bool, Never>?
    private var stopContinuation: CheckedContinuation<RecorderStopOutcome, Never>?

    package func snapshotSamples() -> [Float]? {
        samples
    }

    package func prepare() async -> Bool {
        preparationCount += 1
        guard !completesPreparationImmediately else {
            return preparationResult
        }
        return await withCheckedContinuation { continuation in
            preparationContinuation = continuation
        }
    }

    package func completePreparation(with result: Bool? = nil) {
        let result = result ?? preparationResult
        let continuation = preparationContinuation
        preparationContinuation = nil
        continuation?.resume(returning: result)
    }

    package func start(maximumDuration: TimeInterval) async -> Bool {
        startCount += 1
        maximumDurations.append(maximumDuration)
        if completesStartImmediately {
            isRecording = startResult
        }
        onStart?()
        guard !completesStartImmediately else {
            return startResult
        }
        return await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    package func completeStart(with result: Bool? = nil) {
        let result = result ?? startResult
        isRecording = result
        let continuation = startContinuation
        startContinuation = nil
        continuation?.resume(returning: result)
    }

    package func stop() async -> RecorderStopOutcome {
        stopCount += 1
        isRecording = false
        if let immediateStopOutcome {
            return immediateStopOutcome
        }
        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
    }

    package func completeStop(with outcome: RecorderStopOutcome) {
        let continuation = stopContinuation
        stopContinuation = nil
        continuation?.resume(returning: outcome)
    }

    package func cancel() {
        cancelCount += 1
        isRecording = false
        let preparationContinuation = preparationContinuation
        self.preparationContinuation = nil
        preparationContinuation?.resume(returning: false)
        let startContinuation = startContinuation
        self.startContinuation = nil
        startContinuation?.resume(returning: false)
        completeStop(with: .cancelled)
    }
}

@MainActor
package final class EngineRecorderFactoryFake: AudioRecorderCreating {
    package var recorders: [EngineRecorderFake]
    package var creationError: (any Error)?
    package private(set) var creationCount = 0
    package private(set) var eventHandlers: [@MainActor (RecorderEvent) -> Void] = []

    package init(recorders: [EngineRecorderFake] = [EngineRecorderFake()]) {
        self.recorders = recorders
    }

    package func makeRecorder(
        at url: URL,
        eventHandler: @escaping @MainActor (RecorderEvent) -> Void
    ) throws -> any AudioRecording {
        creationCount += 1
        if let creationError {
            throw creationError
        }
        guard !recorders.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        let recorder = recorders.removeFirst()
        eventHandlers.append(eventHandler)
        return recorder
    }

    package func emit(_ event: RecorderEvent, recorderIndex: Int = 0) {
        guard eventHandlers.indices.contains(recorderIndex) else {
            return
        }
        eventHandlers[recorderIndex](event)
    }
}

@MainActor
package final class EngineFileStoreFake: RecordingFileStoring {
    package init() {}

    package private(set) var allocatedURLs: [URL] = []
    package private(set) var removedURLs: [URL] = []
    package private(set) var staleCleanupCount = 0
    package private(set) var instanceCleanupCount = 0
    package var allocationError: (any Error)?
    package var removalError: (any Error)?

    package func allocateRecordingURL() throws -> URL {
        if let allocationError {
            throw allocationError
        }
        let url = URL(fileURLWithPath: "/tmp/engine-recording-\(UUID().uuidString).wav")
        allocatedURLs.append(url)
        return url
    }

    package func removeRecording(at url: URL) throws {
        removedURLs.append(url)
        if let removalError {
            throw removalError
        }
    }

    package func removeStaleOwnedFiles(olderThan age: TimeInterval) throws {
        staleCleanupCount += 1
    }

    package func cleanupInstance() throws {
        instanceCleanupCount += 1
    }
}

package final class EngineTranscriberFake: SpeechTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: TranscriptionOutcome?
    private var continuation: CheckedContinuation<TranscriptionOutcome, Never>?
    private var cancelled = false
    package private(set) var invocationCount = 0
    package private(set) var synchronousCancellationCount = 0

    package init(outcome: TranscriptionOutcome? = .noSpeech) {
        self.outcome = outcome
    }

    package func transcribe(audioURL: URL) async -> TranscriptionOutcome {
        let immediateOutcome = lock.withLock { () -> TranscriptionOutcome? in
            invocationCount += 1
            return outcome
        }
        if let immediateOutcome {
            return immediateOutcome
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let outcome {
                    lock.unlock()
                    continuation.resume(returning: outcome)
                } else if cancelled || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: .cancelled)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.resolveCancellation()
        }
    }

    package func resolve(_ outcome: TranscriptionOutcome) {
        let continuation: CheckedContinuation<TranscriptionOutcome, Never>?
        lock.lock()
        self.outcome = outcome
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: outcome)
    }

    package func cancelActiveTranscriptions() {
        lock.lock()
        synchronousCancellationCount += 1
        lock.unlock()
        resolveCancellation()
    }

    private func resolveCancellation() {
        let continuation: CheckedContinuation<TranscriptionOutcome, Never>?
        lock.lock()
        cancelled = true
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: .cancelled)
    }
}

package final class EngineSequencedTranscriberFake: SpeechTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [TranscriptionOutcome]
    private var _audioURLs: [URL] = []
    private var _sampleCounts: [Int] = []

    package init(outcomes: [TranscriptionOutcome]) {
        self.outcomes = outcomes
    }

    package var audioURLs: [URL] {
        lock.withLock { _audioURLs }
    }

    /// Sample counts of in-memory draft passes, in call order.
    package var sampleCounts: [Int] {
        lock.withLock { _sampleCounts }
    }

    package func transcribe(samples: [Float]) async -> TranscriptionOutcome {
        lock.withLock {
            _sampleCounts.append(samples.count)
            guard !outcomes.isEmpty else {
                return .noSpeech
            }
            return outcomes.removeFirst()
        }
    }

    package func transcribe(audioURL: URL) async -> TranscriptionOutcome {
        lock.withLock {
            _audioURLs.append(audioURL)
            guard !outcomes.isEmpty else {
                return .noSpeech
            }
            return outcomes.removeFirst()
        }
    }
}

@MainActor
package final class EngineDeliveryFake: TextDelivering {
    package var capturedTarget: PasteTarget?
    package var outcome: DeliveryOutcome?
    package var liveUpdateResult = true
    package private(set) var captureCount = 0
    package private(set) var liveUpdatedTexts: [String] = []
    package private(set) var finalizedTexts: [String] = []
    package private(set) var liveCancellationCount = 0
    package private(set) var deliveredTexts: [String] = []
    package private(set) var deliveredTargets: [PasteTarget?] = []
    private var continuation: CheckedContinuation<DeliveryOutcome, Never>?

    package init(outcome: DeliveryOutcome? = .inserted) {
        self.outcome = outcome
    }

    package func captureCurrentTarget(excludingBundleIdentifier: String?) -> PasteTarget? {
        captureCount += 1
        return capturedTarget
    }

    package func updateLiveTranscript(_ text: String, in target: PasteTarget?) async -> Bool {
        liveUpdatedTexts.append(text)
        return liveUpdateResult
    }

    package func finalizeLiveTranscript(_ text: String, in target: PasteTarget?) async -> DeliveryOutcome {
        finalizedTexts.append(text)
        return await deliver(text, to: target)
    }

    package func cancelLiveTranscript() {
        liveCancellationCount += 1
    }

    package func deliver(_ text: String, to target: PasteTarget?) async -> DeliveryOutcome {
        deliveredTexts.append(text)
        deliveredTargets.append(target)
        if let outcome {
            return outcome
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    package func resolve(_ outcome: DeliveryOutcome) {
        self.outcome = outcome
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: outcome)
    }
}

package enum EngineFixtures {
    package static let readyPreflightResult: SpeechModelPreflightResult = .ready(
        SpeechModelReadiness(summary: "Fixture model", location: URL(fileURLWithPath: "/fixture/speech-model"))
    )
}
