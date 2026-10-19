import XCTest
@testable import Loqui

@MainActor
final class RecordingOverlayTests: XCTestCase {
    func testPhaseFollowsEngineState() {
        XCTAssertEqual(RecordingOverlayPhase(.idle), .hidden)
        XCTAssertEqual(RecordingOverlayPhase(.failed), .hidden)
        XCTAssertEqual(RecordingOverlayPhase(.requestingPermission), .arming)
        XCTAssertEqual(RecordingOverlayPhase(.starting), .arming)
        XCTAssertEqual(RecordingOverlayPhase(.recording), .listening)
        XCTAssertEqual(RecordingOverlayPhase(.stopping), .processing)
        XCTAssertEqual(RecordingOverlayPhase(.transcribing), .processing)
        XCTAssertEqual(RecordingOverlayPhase(.delivering), .processing)
    }

    func testLevelNormalizationCoversSpeechRange() {
        XCTAssertEqual(RecordingOverlayModel.normalizedLevel(amplitude: 0), 0)
        XCTAssertEqual(RecordingOverlayModel.normalizedLevel(amplitude: 0.001), 0)
        XCTAssertEqual(RecordingOverlayModel.normalizedLevel(amplitude: 0.01), 0.25, accuracy: 0.001)
        XCTAssertEqual(RecordingOverlayModel.normalizedLevel(amplitude: 1), 1)
    }

    func testNewestLevelStartsAtCenterAndRipplesOutward() {
        let model = RecordingOverlayModel()
        let center = RecordingOverlayModel.barCount / 2

        model.push(amplitude: 1)
        XCTAssertEqual(model.levels[center], 1)
        XCTAssertEqual(model.levels[center - 1], 0)

        model.push(amplitude: 1)
        XCTAssertGreaterThan(model.levels[center - 1], 0)
        XCTAssertEqual(model.levels[center - 1], model.levels[center + 1])
    }

    func testLevelsFallGraduallyAfterSpeechStops() {
        let model = RecordingOverlayModel()
        let center = RecordingOverlayModel.barCount / 2
        model.push(amplitude: 1)

        model.push(amplitude: 0)

        XCTAssertEqual(model.levels[center], 0.7, accuracy: 0.001)
        model.reset()
        XCTAssertTrue(model.levels.allSatisfy { $0 == 0 })
    }

    func testIndicatorIsOnByDefault() throws {
        let suiteName = "RecordingOverlayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(RecordingOverlayPreference.isEnabled(defaults: defaults))
        defaults.set(false, forKey: RecordingOverlayPreference.defaultsKey)
        XCTAssertFalse(RecordingOverlayPreference.isEnabled(defaults: defaults))
    }
}
