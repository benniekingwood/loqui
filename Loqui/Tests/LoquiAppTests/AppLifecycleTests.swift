import AppKit
import LoquiTestSupport
import XCTest
@testable import Loqui
@testable import LoquiAudio
@testable import LoquiCore
@testable import LoquiShortcuts

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testApplicationTerminationCancelsNativeTranscriptionAndUninstallsHotkey() async {
        let transcriber = EngineTranscriberFake(outcome: nil)
        let store = EngineFileStoreFake()
        let engine = TranscriptionEngine(
            permissionProvider: EnginePermissionFake(),
            recorderFactory: EngineRecorderFactoryFake(),
            recordingReadyCue: EngineReadyCueFake(),
            recordingStoppedCue: EngineStoppedCueFake(),
            recordingFileStore: store,
            dependencyPreflight: EnginePreflightFake(),
            transcriber: transcriber,
            textDelivery: EngineDeliveryFake(),
            performStartupCleanup: false
        )
        let hotKeyService = EngineHotKeyServiceFake()
        let delegate = AppDelegate(environment: AppEnvironment(
            audioInputSelection: AudioInputSelection(lister: NoInputDevices()),
            transcriptionEngine: engine,
            hotKeyController: HotKeyController(service: hotKeyService)
        ))
        engine.toggleRecording()
        await waitUntil { engine.state == .recording }
        engine.toggleRecording()
        await waitUntil { engine.state == .transcribing }
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertEqual(transcriber.synchronousCancellationCount, 1)
        XCTAssertEqual(store.removedURLs, store.allocatedURLs)
        XCTAssertEqual(hotKeyService.uninstallCount, 1)
        transcriber.resolve(.cancelled)
        await spinMainActor()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met in time")
    }

    private func spinMainActor() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

@MainActor
private final class EngineHotKeyServiceFake: GlobalHotKeyService {
    private(set) var uninstallCount = 0

    func install(
        key: DictationKey,
        action: @escaping @MainActor @Sendable (DictationKeyPhase) -> Void
    ) -> Result<Void, HotKeyInstallationError> {
        .success(())
    }

    func uninstall() {
        uninstallCount += 1
    }
}

@MainActor
private final class NoInputDevices: AudioInputDeviceListing {
    func inputDevices() -> [AudioInputDevice] { [] }
    func systemDefaultInputDevice() -> AudioInputDevice? { nil }
}
