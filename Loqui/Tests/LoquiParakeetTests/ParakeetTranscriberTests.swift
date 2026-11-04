import Foundation
import XCTest
@testable import LoquiCore
@testable import LoquiParakeet

final class ParakeetTranscriberTests: XCTestCase {
    func testLiteralIdentifiersAndSymbolsSurviveFinalTranscription() async {
        let backend = ParakeetRecognizerFake(text: "  getUserByID != nil; [BLANK_AUDIO] \n")
        let result = await transcriber(backend: backend).transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(result, .success("getUserByID != nil; [BLANK_AUDIO]"))
    }

    func testSuccessfulEmptyOutputAloneMeansNoSpeech() async {
        let empty = await transcriber(backend: ParakeetRecognizerFake(text: " \n ")).transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(empty, .noSpeech)
        let failure = NSError(domain: "CoreML", code: 17, userInfo: [NSLocalizedDescriptionKey: "private dictated content"])
        let failed = await transcriber(backend: ParakeetRecognizerFake(error: failure)).transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(failed, .inferenceFailed(TranscriptionDiagnostic(domain: "CoreML", code: 17)))
    }

    func testInvalidAudioDoesNotLoadModelsOrInvokeInference() async {
        let backend = ParakeetRecognizerFake()
        let recognizer = transcriber(backend: backend, validation: .invalid(.unreadableFormat))
        let outcome = await recognizer.transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(outcome, .invalidAudio(.unreadableFormat))
        XCTAssertEqual(backend.loadCount, 0)
        XCTAssertEqual(backend.transcriptionCount, 0)
    }

    func testMissingWeightsFailBeforeInferenceAndNeverBecomeNoSpeech() async {
        let backend = ParakeetRecognizerFake()
        let failure = SpeechModelFailure.missingModel(searchedPaths: [])
        let recognizer = ParakeetTranscriber(
            resolver: ParakeetResolverFake(result: .failure(failure)),
            audioValidator: ParakeetAudioValidatorFake(result: .valid(duration: 1)), recognizer: backend
        )
        let outcome = await recognizer.transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(outcome, .modelUnavailable(failure))
        XCTAssertEqual(backend.loadCount, 0)
    }

    func testModelLoadFailureHasSafeTypedDiagnostics() async {
        let backend = ParakeetRecognizerFake(loadError: NSError(domain: "CoreML", code: 9))
        let recognizer = transcriber(backend: backend)
        let preflight = await recognizer.preflightSpeechModel()
        let expected = SpeechModelFailure.modelLoadFailed(TranscriptionDiagnostic(domain: "CoreML", code: 9))
        XCTAssertEqual(preflight, .failure(expected))
        let outcome = await recognizer.transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(outcome, .modelUnavailable(expected))
        XCTAssertEqual(backend.transcriptionCount, 0)
    }

    func testTaskCancellationAndApplicationTerminationCancelNativeWork() async throws {
        for terminateApplication in [false, true] {
            let backend = ParakeetRecognizerFake(block: true)
            let recognizer = transcriber(backend: backend)
            let operation = Task { await recognizer.transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav")) }
            for _ in 0..<100 where backend.transcriptionCount == 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(backend.transcriptionCount, 1)
            if terminateApplication { recognizer.cancelActiveTranscriptions() } else { operation.cancel() }
            let outcome = await operation.value
            XCTAssertEqual(outcome, .cancelled)
        }
    }

    func testDraftsDecodeInMemorySamplesWithoutTouchingTheFileValidator() async {
        let backend = ParakeetRecognizerFake(text: " ask not ")
        let recognizer = transcriber(backend: backend, validation: .invalid(.missing))
        let outcome = await recognizer.transcribe(samples: Array(repeating: 0, count: 16000))
        XCTAssertEqual(outcome, .success("ask not"))
        XCTAssertEqual(backend.sampleCounts, [16000])
    }

    func testTooFewSamplesAreRejectedBeforeInference() async {
        let backend = ParakeetRecognizerFake()
        let outcome = await transcriber(backend: backend).transcribe(samples: Array(repeating: 0, count: 800))
        XCTAssertEqual(outcome, .invalidAudio(.tooShort(duration: 0.05)))
        XCTAssertEqual(backend.transcriptionCount, 0)
    }

    func testRepeatedPassesReuseTheVerifiedModelUntilItIsStale() async {
        let backend = ParakeetRecognizerFake()
        let resolver = ParakeetResolverFake(result: .ready(Self.fixtureLocation))
        let clock = ParakeetTestClock()
        let recognizer = ParakeetTranscriber(
            resolver: resolver,
            audioValidator: ParakeetAudioValidatorFake(result: .valid(duration: 1)),
            recognizer: backend,
            now: { clock.now }
        )
        for _ in 0..<5 {
            _ = await recognizer.transcribe(samples: Array(repeating: 0, count: 16000))
        }
        XCTAssertEqual(resolver.callCount, 1, "Live drafts must not re-check every model file on each pass")

        clock.advance(by: ParakeetTranscriber.revalidationInterval + 1)
        _ = await recognizer.transcribe(samples: Array(repeating: 0, count: 16000))
        XCTAssertEqual(resolver.callCount, 2, "A stale verification is repeated before the next pass")

        _ = await recognizer.preflightSpeechModel()
        XCTAssertEqual(resolver.callCount, 3, "An explicit preflight always re-checks the files")
    }

    func testPreflightReportsAContentFreeSummary() async {
        let preflight = await transcriber(backend: ParakeetRecognizerFake()).preflightSpeechModel()
        guard case let .ready(readiness) = preflight else { return XCTFail("Expected a ready model") }
        XCTAssertTrue(readiness.summary.hasPrefix("Parakeet Unified English 0.6B; FluidAudio="))
        XCTAssertEqual(readiness.location, Self.fixtureLocation.model.url)
    }

    func testDraftsStreamOnlyNewAudioAndTheFinalFlushesOnlyTheRest() async throws {
        let backend = ParakeetRecognizerFake(text: " ask not ")
        backend.recording = Self.speech(seconds: 1.25)
        let recognizer = transcriber(backend: backend)
        let started = await recognizer.beginStream()
        let stream = try XCTUnwrap(started)

        let first = await stream.draft(from: Self.speech(seconds: 0.5))
        let second = await stream.draft(from: Self.speech(seconds: 1))
        let final = await stream.finish(audioURL: URL(fileURLWithPath: "/fixture.wav"))

        XCTAssertEqual(first, .success("ask not"))
        XCTAssertEqual(second, .success("ask not"))
        XCTAssertEqual(final, .success("ask not"))
        XCTAssertEqual(backend.calls, [.reset, .stream(8000), .stream(8000), .stream(4000), .finish])
    }

    func testAFinalWithoutALiveStreamStreamsTheWholeRecording() async {
        let backend = ParakeetRecognizerFake()
        backend.recording = Self.speech(seconds: 3)
        _ = await transcriber(backend: backend).transcribe(audioURL: URL(fileURLWithPath: "/fixture.wav"))
        XCTAssertEqual(backend.calls, [.reset, .stream(48000), .finish])
    }

    func testAFailedDraftMakesTheFinalStartOver() async throws {
        let backend = ParakeetRecognizerFake()
        backend.recording = Self.speech(seconds: 1)
        let recognizer = transcriber(backend: backend)
        let started = await recognizer.beginStream()
        let stream = try XCTUnwrap(started)
        backend.failNextStreamCall()

        let draft = await stream.draft(from: Self.speech(seconds: 0.5))
        _ = await stream.finish(audioURL: URL(fileURLWithPath: "/fixture.wav"))

        XCTAssertEqual(draft, .inferenceFailed(TranscriptionDiagnostic(domain: "CoreML", code: 3)))
        XCTAssertEqual(backend.calls, [.reset, .stream(8000), .reset, .stream(16000), .finish])
    }

    func testAReplacedStreamDecodesNothing() async throws {
        let backend = ParakeetRecognizerFake()
        let recognizer = transcriber(backend: backend)
        let started = await recognizer.beginStream()
        let earlier = try XCTUnwrap(started)
        _ = await recognizer.beginStream()

        let draft = await earlier.draft(from: Self.speech(seconds: 1))

        XCTAssertEqual(draft, .cancelled)
        XCTAssertEqual(backend.calls, [.reset, .reset])
    }

    func testNoStreamStartsWithoutAModel() async {
        let backend = ParakeetRecognizerFake()
        let recognizer = ParakeetTranscriber(
            resolver: ParakeetResolverFake(result: .failure(.missingModel(searchedPaths: []))),
            audioValidator: ParakeetAudioValidatorFake(result: .valid(duration: 1)), recognizer: backend
        )
        let stream = await recognizer.beginStream()
        XCTAssertNil(stream)
        XCTAssertEqual(backend.calls, [])
    }

    func testSpeechIsNeverHeldBack() {
        var pauses = PauseCap()
        XCTAssertEqual(pauses.admit(Self.speech(seconds: 10)[...]).count, 160_000)
    }

    func testOnlyTheFirstTwoSecondsOfALongPauseAreStreamed() {
        var pauses = PauseCap()
        let audio = Self.speech(seconds: 1) + Self.level(-70, seconds: 10) + Self.speech(seconds: 1)
        XCTAssertEqual(pauses.admit(audio[...]).count, 64000, "1 s of speech, 2 s of pause, 1 s of speech")
    }

    func testANoisyRoomHoldsNothingBack() {
        var pauses = PauseCap()
        let audio = Self.speech(seconds: 1) + Self.level(-40, seconds: 10) + Self.speech(seconds: 1)
        XCTAssertEqual(pauses.admit(audio[...]).count, 192_000)
    }

    func testAPartialChunkWaitsForTheNextSliceOrTheFlush() {
        var pauses = PauseCap()
        XCTAssertEqual(pauses.admit(Self.speech(seconds: 0.0625)[...]).count, 0)
        XCTAssertEqual(pauses.admit(Self.speech(seconds: 0.0625)[...]).count, 1600)
        XCTAssertEqual(pauses.flush().count, 400)
        XCTAssertEqual(pauses.flush().count, 0)
    }

    /// A steady signal at -20 dBFS stands in for speech.
    private static func speech(seconds: Double) -> [Float] { level(-20, seconds: seconds) }

    private static func level(_ decibels: Float, seconds: Double) -> [Float] {
        let amplitude = pow(10, decibels / 20)
        return (0 ..< Int(seconds * 16000)).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
    }

    private static let fixtureLocation = ParakeetModelLocation(
        model: ResolvedDependencyPath(url: URL(fileURLWithPath: "/fixture/parakeet-models"), source: .bundled)
    )

    private func transcriber(backend: ParakeetRecognizerFake, validation: AudioValidationResult = .valid(duration: 1)) -> ParakeetTranscriber {
        ParakeetTranscriber(
            resolver: ParakeetResolverFake(result: .ready(Self.fixtureLocation)),
            audioValidator: ParakeetAudioValidatorFake(result: validation), recognizer: backend
        )
    }
}

private final class ParakeetResolverFake: ParakeetModelResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let result: ParakeetModelResolution
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }

    init(result: ParakeetModelResolution) {
        self.result = result
    }

    func preflight() -> ParakeetModelResolution {
        lock.withLock { calls += 1 }
        return result
    }
}

private struct ParakeetAudioValidatorFake: AudioValidating {
    let result: AudioValidationResult
    var minimumUsefulDuration: TimeInterval = 0.1
    func validateAudio(at url: URL) -> AudioValidationResult { result }
}

private final class ParakeetTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)
    var now: Date { lock.withLock { current } }
    func advance(by interval: TimeInterval) { lock.withLock { current += interval } }
}

/// Records each streaming call. `stream` answers with `text`, and the final
/// flush with `text` too; `samples(of:)` returns `recording`.
private final class ParakeetRecognizerFake: ParakeetRecognizing, @unchecked Sendable {
    enum Call: Equatable {
        case reset
        case stream(Int)
        case finish
    }

    private let lock = NSLock()
    private var loads = 0
    private var log: [Call] = []
    private let text: String
    private let error: NSError?
    private let loadError: NSError?
    private let block: Bool
    private var failNextStream = false
    var recording: [Float] = Array(repeating: 0, count: 16000)
    var loadCount: Int { lock.withLock { loads } }
    var calls: [Call] { lock.withLock { log } }
    var transcriptionCount: Int { lock.withLock { log.filter { $0 == .finish }.count } }
    var sampleCounts: [Int] {
        lock.withLock { log.compactMap { if case let .stream(count) = $0 { count } else { nil } } }
    }

    init(text: String = "hello", error: NSError? = nil, loadError: NSError? = nil, block: Bool = false) {
        self.text = text
        self.error = error
        self.loadError = loadError
        self.block = block
    }

    func failNextStreamCall() { lock.withLock { failNextStream = true } }

    func loadModels(at directory: URL) async throws {
        lock.withLock { loads += 1 }
        if let loadError { throw loadError }
    }

    func samples(of audioURL: URL) async throws -> [Float] {
        lock.withLock { recording }
    }

    func resetStream() async throws {
        lock.withLock { log.append(.reset) }
    }

    func stream(_ samples: [Float]) async throws -> String {
        let fail = lock.withLock {
            log.append(.stream(samples.count))
            defer { failNextStream = false }
            return failNextStream
        }
        if fail { throw NSError(domain: "CoreML", code: 3) }
        return text
    }

    func finishStream() async throws -> String {
        lock.withLock { log.append(.finish) }
        if block { try await Task.sleep(for: .seconds(10)) }
        if let error { throw error }
        return text
    }
}
