import XCTest
@testable import Loqui

@MainActor
final class TranscriptCardTests: XCTestCase {
    func testTextRolesAndEditableContentCountAsTextFields() {
        XCTAssertEqual(FocusedInputKind.classify(role: "AXTextArea", hasEditableAncestor: false, selectedTextRangeSettable: false), .text)
        XCTAssertEqual(FocusedInputKind.classify(role: "AXTextField", hasEditableAncestor: false, selectedTextRangeSettable: false), .text)
        XCTAssertEqual(FocusedInputKind.classify(role: "AXWebArea", hasEditableAncestor: true, selectedTextRangeSettable: false), .text)
        XCTAssertEqual(FocusedInputKind.classify(role: "AXGroup", hasEditableAncestor: false, selectedTextRangeSettable: true), .text)
    }

    func testListsButtonsAndPlainWebPagesAreNotTextFields() {
        for role in ["AXList", "AXOutline", "AXTable", "AXButton", "AXWebArea", "AXSlider"] {
            XCTAssertEqual(
                FocusedInputKind.classify(role: role, hasEditableAncestor: false, selectedTextRangeSettable: false),
                .notText,
                role
            )
        }
    }

    func testAmbiguousOrMissingFocusKeepsTheExistingDeliveryPath() {
        XCTAssertEqual(FocusedInputKind.classify(role: nil, hasEditableAncestor: false, selectedTextRangeSettable: false), .unknown)
        for role in ["AXGroup", "AXScrollArea", "AXWindow", "AXStaticText"] {
            XCTAssertEqual(
                FocusedInputKind.classify(role: role, hasEditableAncestor: false, selectedTextRangeSettable: false),
                .unknown,
                role
            )
        }
    }

    func testOnlyUnplacedOutcomesProduceACard() {
        XCTAssertEqual(UnplacedTranscript(text: "a", outcome: .noTextInput)?.reason, .noTextInput)
        XCTAssertEqual(UnplacedTranscript(text: "a", outcome: .copiedForManualPaste(.activationFailed))?.reason, .copiedToClipboard)
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .inserted))
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .pasted(restoration: .restored)))
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .cancelled(restoration: nil)))
    }

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
