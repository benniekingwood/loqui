import AppKit
import Combine
import SwiftUI
import XCTest
@testable import LoquiAudio
@testable import LoquiCore
@testable import LoquiInterface

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

    func testLaunchTimeModelLoadingDoesNotShowTheIndicator() {
        XCTAssertEqual(RecordingOverlayPhase(.starting, isDictating: false), .hidden)
        XCTAssertEqual(RecordingOverlayPhase(.starting, isDictating: true), .arming)
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

    func testTheMicrophoneIsAnnouncedFirstOnChangeAndAfterAQuietStretch() {
        var announcer = InputDeviceAnnouncer()
        let start = Date(timeIntervalSinceReferenceDate: 0)

        XCTAssertTrue(announcer.shouldAnnounce(deviceUID: "built-in", at: start))
        XCTAssertFalse(announcer.shouldAnnounce(deviceUID: "built-in", at: start + 60))
        XCTAssertTrue(announcer.shouldAnnounce(deviceUID: "airpods", at: start + 120))
        XCTAssertFalse(announcer.shouldAnnounce(deviceUID: "airpods", at: start + 180))
        XCTAssertTrue(announcer.shouldAnnounce(
            deviceUID: "airpods",
            at: start + 180 + InputDeviceAnnouncer.quietInterval
        ))
    }

    func testTheLabelShowsForANewDictationAndClearsWhenTheIndicatorHides() {
        let phases = PassthroughSubject<RecordingOverlayPhase, Never>()
        let device = AudioInputDevice(uid: "built-in", name: "MacBook Pro Microphone", deviceID: 1)
        let controller = RecordingOverlayController(
            phases: phases.eraseToAnyPublisher(),
            inputLevel: { 0 },
            inputDevice: { device }
        )
        controller.start()
        defer { controller.stop() }

        phases.send(.arming)
        XCTAssertEqual(controller.model.inputDeviceName, "MacBook Pro Microphone")
        phases.send(.listening)
        XCTAssertEqual(controller.model.inputDeviceName, "MacBook Pro Microphone")
        phases.send(.hidden)
        XCTAssertNil(controller.model.inputDeviceName)

        // The same microphone moments later is not worth naming again.
        phases.send(.arming)
        XCTAssertNil(controller.model.inputDeviceName)
    }

    func testTheLabelLeavesShortlyAfterListeningStarts() async throws {
        let phases = PassthroughSubject<RecordingOverlayPhase, Never>()
        let device = AudioInputDevice(uid: "built-in", name: "MacBook Pro Microphone", deviceID: 1)
        let controller = RecordingOverlayController(
            phases: phases.eraseToAnyPublisher(),
            inputLevel: { 0 },
            inputDevice: { device }
        )
        controller.start()
        defer { controller.stop() }

        phases.send(.arming)
        phases.send(.listening)
        try await Task.sleep(for: RecordingOverlayController.inputDeviceLabelDuration + .milliseconds(300))

        XCTAssertNil(controller.model.inputDeviceName)
        XCTAssertEqual(controller.model.phase, .listening)
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

@MainActor
final class FloatingPanelTests: XCTestCase {
    func testPanelsSitCenteredJustAboveTheDock() {
        let visibleFrame = NSRect(x: 0, y: 70, width: 1512, height: 870)
        let frame = FloatingPanel.frameAboveDock(size: NSSize(width: 160, height: 64), in: visibleFrame)
        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.minY, visibleFrame.minY + FloatingPanel.bottomMargin)
        XCTAssertEqual(frame.size, NSSize(width: 160, height: 64))
    }

    func testPanelsFloatOnEverySpaceWithoutTakingFocus() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        FloatingPanel.configure(panel)
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
    }

    func testBrandPaletteKeepsTheSpectrumOrder() {
        XCTAssertEqual(LoquiBrand.spectrum, [LoquiBrand.coral, LoquiBrand.amber, LoquiBrand.mint, LoquiBrand.sky])
    }
}
