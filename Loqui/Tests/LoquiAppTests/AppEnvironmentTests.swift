import LoquiShortcuts
import XCTest
@testable import Loqui
@testable import LoquiCore

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testLiveEnvironmentNamesTheParakeetBackend() {
        let environment = AppEnvironment.live()
        defer { environment.transcriptionEngine.cleanup() }
        XCTAssertEqual(environment.transcriptionEngine.speechModelName, "Parakeet")
        XCTAssertEqual(environment.hotKeyController.availability, .unregistered, "Composing must not install the global key monitor")
    }
}
