import Foundation
import XCTest
import LoquiTestSupport
@testable import LoquiCore

@MainActor
final class LiveTranscriptionPreviewTests: XCTestCase {
    func testDraftsDecodeInMemorySamplesAndRepeatsAreNotRedelivered() async throws {
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

        XCTAssertEqual(Array(transcriber.sampleCounts.prefix(3)), [8000, 16000, 24000], "Each draft is a full pass over the audio so far")
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
