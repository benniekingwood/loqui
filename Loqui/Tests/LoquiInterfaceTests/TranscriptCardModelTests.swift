import XCTest
@testable import LoquiCore
@testable import LoquiInterface

@MainActor
final class TranscriptCardModelTests: XCTestCase {
    func testCountdownClosesTheCardAndPausesWhileHovering() {
        let model = TranscriptCardModel()
        model.present(UnplacedTranscript(text: "hi", reason: .noTextInput))

        XCTAssertFalse(model.tick(elapsed: TranscriptCardModel.lifetime / 2))
        XCTAssertEqual(model.remainingFraction, 0.5, accuracy: 0.001)

        model.isHovering = true
        XCTAssertFalse(model.tick(elapsed: TranscriptCardModel.lifetime))
        XCTAssertEqual(model.remainingFraction, 0.5, accuracy: 0.001)

        model.isHovering = false
        XCTAssertTrue(model.tick(elapsed: TranscriptCardModel.lifetime))
    }

    func testANewTranscriptRestartsTheCountdown() {
        let model = TranscriptCardModel()
        model.present(UnplacedTranscript(text: "first", reason: .noTextInput))
        _ = model.tick(elapsed: TranscriptCardModel.lifetime - 1)
        model.markCopied()

        model.present(UnplacedTranscript(text: "second", reason: .copiedToClipboard))

        XCTAssertEqual(model.remainingFraction, 1)
        XCTAssertFalse(model.copied)
        XCTAssertEqual(model.transcript?.text, "second")
    }
}
