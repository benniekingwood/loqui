import XCTest
@testable import LoquiCore
@testable import LoquiDelivery

@MainActor
final class FocusedInputTests: XCTestCase {
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
}
