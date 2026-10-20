import AVFoundation
import XCTest
@testable import LoquiAudio
@testable import LoquiCore

@MainActor
final class RecordingCuePlayerTests: XCTestCase {
    func testReadyAndStoppedCuesHaveAudibleSamplesAndPredictableShortDuration() throws {
        for ascending in [true, false] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at: url) }
            try RecordingCueAudio.makeWave(ascending: ascending).write(to: url)
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 0.08, accuracy: 0.001)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            let peak = (0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.35)
            XCTAssertLessThan(peak, 1)
            XCTAssertEqual(samples[0], 0)
            XCTAssertEqual(samples[Int(buffer.frameLength) - 1], 0)
        }
    }

    func testDisabledReadyCueReturnsWithoutDelayingCapture() async {
        let player = SystemRecordingReadyCuePlayer(isEnabled: { false })
        let clock = ContinuousClock()
        let started = clock.now
        await player.play()
        XCTAssertLessThan(clock.now - started, .milliseconds(50))
    }
}
