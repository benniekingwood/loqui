import XCTest
@testable import LoquiCore

final class DeliveryContractsTests: XCTestCase {
    func testOnlyUnplacedOutcomesProduceACard() {
        XCTAssertEqual(UnplacedTranscript(text: "a", outcome: .noTextInput)?.reason, .noTextInput)
        XCTAssertEqual(UnplacedTranscript(text: "a", outcome: .copiedForManualPaste(.activationFailed))?.reason, .copiedToClipboard)
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .inserted))
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .pasted(restoration: .restored)))
        XCTAssertNil(UnplacedTranscript(text: "a", outcome: .cancelled(restoration: nil)))
    }
}
