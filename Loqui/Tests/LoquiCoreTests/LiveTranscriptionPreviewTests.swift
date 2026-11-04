import Foundation
import XCTest
import LoquiTestSupport
@testable import LoquiCore

@MainActor
final class LiveTranscriptionPreviewTests: XCTestCase {
    func testFullPassDraftsDecodeInMemorySamplesAndRepeatsAreNotRedelivered() async throws {
        let transcriber = PreviewTranscriberFake(drafts: ["ask", "ask not", "ask not"])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        var captured = 0
        var drafts: [String] = []
        preview.start(interval: 0.1, samples: {
            captured += 8000
            return Array(repeating: 0, count: captured)
        }, receiveTranscript: { drafts.append($0) })

        try await waitUntil { transcriber.sampleCounts.count >= 3 }
        await preview.stop()?.value

        XCTAssertEqual(Array(transcriber.sampleCounts.prefix(3)), [8000, 16000, 24000], "Without a stream, each draft is a full pass over the audio so far")
        XCTAssertEqual(drafts, ["ask", "ask not"], "An unchanged draft must not retype text at the cursor")
    }

    func testPassIsSkippedWhileNoNewAudioArrives() async throws {
        let transcriber = PreviewTranscriberFake(drafts: ["hello"])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        var polls = 0
        preview.start(interval: 0.1, samples: {
            polls += 1
            return Array(repeating: 0, count: 16000)
        }, receiveTranscript: { _ in })

        try await waitUntil { polls >= 4 }
        await preview.stop()?.value

        XCTAssertEqual(transcriber.sampleCounts, [16000], "A paused speaker must not trigger more decoding")
    }

    func testTooLittleAudioIsNotDecoded() async throws {
        let transcriber = PreviewTranscriberFake(drafts: ["noise"])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        var polls = 0
        preview.start(interval: 0.1, samples: {
            polls += 1
            return Array(repeating: 0, count: LiveTranscriptionPreview.minimumSampleCount - 1)
        }, receiveTranscript: { _ in XCTFail("Too little audio must not produce a draft") })

        try await waitUntil { polls >= 3 }
        await preview.stop()?.value

        XCTAssertEqual(transcriber.sampleCounts, [])
    }

    func testRecorderWithoutSamplesProducesNoDrafts() async throws {
        let transcriber = PreviewTranscriberFake(drafts: ["unused"])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        var polls = 0
        preview.start(interval: 0.1, samples: {
            polls += 1
            return nil
        }, receiveTranscript: { _ in XCTFail("No samples means no draft") })

        try await waitUntil { polls >= 3 }
        await preview.stop()?.value

        XCTAssertEqual(transcriber.sampleCounts, [])
    }

    func testCancelledPassDeliversNothing() async throws {
        let transcriber = PreviewTranscriberFake(drafts: ["late"], gated: true)
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        preview.start(interval: 0.1, samples: { Array(repeating: 0, count: 16000) }, receiveTranscript: { _ in
            XCTFail("A cancelled preview must not deliver text")
        })

        try await waitUntil { transcriber.sampleCounts.count == 1 }
        let task = preview.stop()
        transcriber.openGate()
        await task?.value
    }

    func testStopClosesMicrophoneAndStartsFinalTranscriptionWithoutWaitingForPreview() async throws {
        let recorder = EngineRecorderFake()
        let stoppedCue = EngineStoppedCueFake()
        let transcriber = PreviewTranscriberFake(drafts: ["draft"], gated: true)
        let engine = TranscriptionEngine(
            permissionProvider: EnginePermissionFake(),
            recorderFactory: EngineRecorderFactoryFake(recorders: [recorder]),
            recordingReadyCue: EngineReadyCueFake(),
            recordingStoppedCue: stoppedCue,
            recordingFileStore: EngineFileStoreFake(),
            dependencyPreflight: EnginePreflightFake(),
            transcriber: transcriber,
            textDelivery: EngineDeliveryFake(),
            livePreviewInterval: 0.1,
            performStartupCleanup: false
        )
        defer { engine.cleanup() }
        engine.startRecording()
        try await waitUntil { transcriber.sampleCounts.count == 1 }

        engine.stopRecording()
        try await waitUntil { recorder.stopCount > 0 }
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(stoppedCue.playCount, 1, "Stop audio feedback must not wait for preview inference")
        try await waitUntil { engine.state == .idle }
        transcriber.openGate()
    }

    func testAStreamingBackendDecodesEveryNewSliceAndSkipsFullPasses() async throws {
        let transcriber = StreamingTranscriberFake(drafts: ["ask", "ask not"])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        var captured = 0
        var drafts: [String] = []
        preview.start(interval: 0.1, samples: {
            captured += 1600
            return Array(repeating: 0, count: captured)
        }, receiveTranscript: { drafts.append($0) })

        try await waitUntil { transcriber.stream.draftCounts.count >= 2 }
        await preview.stop()?.value

        XCTAssertEqual(Array(transcriber.stream.draftCounts.prefix(2)), [1600, 3200], "A stream needs no minimum before its first draft")
        XCTAssertEqual(drafts, ["ask", "ask not"])
        XCTAssertEqual(transcriber.fullPassCount, 0, "A streaming backend must not re-decode the whole dictation")
        XCTAssertNotNil(preview.takeStream(), "Stopping the drafts keeps the stream for the final pass")
        XCTAssertNil(preview.takeStream(), "The stream is handed over once")
        XCTAssertEqual(transcriber.stream.cancelCount, 0)
    }

    func testCleanupEndsTheStream() async throws {
        let transcriber = StreamingTranscriberFake(drafts: [])
        let preview = LiveTranscriptionPreview(transcriber: transcriber)
        preview.start(interval: 0.1, samples: { Array(repeating: 0, count: 1600) }, receiveTranscript: { _ in })
        try await waitUntil { transcriber.stream.draftCounts.count == 1 }

        preview.cleanup()

        XCTAssertEqual(transcriber.stream.cancelCount, 1)
        XCTAssertNil(preview.takeStream())
    }

    func testTheFinalTranscriptFinishesTheDictationsStream() async throws {
        let recorder = EngineRecorderFake()
        let transcriber = StreamingTranscriberFake(drafts: ["draft"])
        let engine = TranscriptionEngine(
            permissionProvider: EnginePermissionFake(),
            recorderFactory: EngineRecorderFactoryFake(recorders: [recorder]),
            recordingReadyCue: EngineReadyCueFake(),
            recordingStoppedCue: EngineStoppedCueFake(),
            recordingFileStore: EngineFileStoreFake(),
            dependencyPreflight: EnginePreflightFake(),
            transcriber: transcriber,
            textDelivery: EngineDeliveryFake(),
            livePreviewInterval: 0.1,
            performStartupCleanup: false
        )
        defer { engine.cleanup() }
        engine.startRecording()
        try await waitUntil { transcriber.stream.draftCounts.count == 1 }

        engine.stopRecording()
        try await waitUntil { engine.state == .idle }

        XCTAssertEqual(transcriber.stream.finishCount, 1)
        XCTAssertEqual(transcriber.fullPassCount, 0, "The final pass must continue the stream, not start over")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met in time")
    }
}

/// Answers drafts in order from in-memory samples; final passes see no speech.
/// When gated, sample passes wait until `openGate()`.
private final class PreviewTranscriberFake: SpeechTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var drafts: [String]
    private var counts: [Int] = []
    private var gated: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(drafts: [String], gated: Bool = false) {
        self.drafts = drafts
        self.gated = gated
    }

    var sampleCounts: [Int] { lock.withLock { counts } }

    func openGate() {
        let pending = lock.withLock {
            gated = false
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    func transcribe(audioURL: URL) async -> TranscriptionOutcome { .noSpeech }

    func transcribe(samples: [Float]) async -> TranscriptionOutcome {
        let mustWait = lock.withLock {
            counts.append(samples.count)
            return gated
        }
        if mustWait {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock {
                    if gated { waiters.append(continuation) }
                    return !gated
                }
                if resumeNow { continuation.resume() }
            }
        }
        return lock.withLock { drafts.isEmpty ? .noSpeech : .success(drafts.removeFirst()) }
    }
}

/// A streaming backend whose one stream answers drafts in order. Full passes
/// are only counted.
private final class StreamingTranscriberFake: SpeechTranscribing, @unchecked Sendable {
    let stream: StreamFake
    private let lock = NSLock()
    private var fullPasses = 0

    init(drafts: [String]) {
        stream = StreamFake(drafts: drafts)
    }

    var fullPassCount: Int { lock.withLock { fullPasses } }

    func transcribe(audioURL: URL) async -> TranscriptionOutcome {
        lock.withLock { fullPasses += 1 }
        return .noSpeech
    }

    func transcribe(samples: [Float]) async -> TranscriptionOutcome {
        lock.withLock { fullPasses += 1 }
        return .noSpeech
    }

    func beginStream() async -> (any SpeechStreaming)? { stream }
}

private final class StreamFake: SpeechStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var drafts: [String]
    private var counts: [Int] = []
    private var finishes = 0
    private var cancels = 0

    init(drafts: [String]) {
        self.drafts = drafts
    }

    var draftCounts: [Int] { lock.withLock { counts } }
    var finishCount: Int { lock.withLock { finishes } }
    var cancelCount: Int { lock.withLock { cancels } }

    func draft(from samples: [Float]) async -> TranscriptionOutcome {
        lock.withLock {
            counts.append(samples.count)
            return drafts.isEmpty ? .noSpeech : .success(drafts.removeFirst())
        }
    }

    func finish(audioURL: URL) async -> TranscriptionOutcome {
        lock.withLock { finishes += 1 }
        return .noSpeech
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }
}
