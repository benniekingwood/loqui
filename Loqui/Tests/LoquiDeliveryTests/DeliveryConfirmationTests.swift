import Foundation
import XCTest
@testable import LoquiCore
@testable import LoquiDelivery

/// Some web-based editors, such as Spark's composer, report Accessibility
/// writes and pasted shortcuts as handled without changing the field. Delivery
/// reads the field back so dictated text is never silently lost.
@MainActor
final class DeliveryConfirmationTests: XCTestCase {
    func testInsertionThatChangesTheFieldIsTrusted() async {
        let fixture = Fixture()
        fixture.accessibility.fieldValue = "Hello "

        let outcome = await fixture.service.deliver("world", to: fixture.target)

        XCTAssertEqual(outcome, .inserted)
        XCTAssertTrue(fixture.pasteboard.replaceTexts.isEmpty)
    }

    func testUnreadableFieldTrustsTheInsertion() async {
        let fixture = Fixture()
        fixture.accessibility.insertionChangesField = false

        let outcome = await fixture.service.deliver("world", to: fixture.target)

        XCTAssertEqual(outcome, .inserted)
        XCTAssertTrue(fixture.pasteboard.replaceTexts.isEmpty)
    }

    func testIgnoredInsertionFallsBackToPaste() async {
        let fixture = Fixture()
        fixture.accessibility.fieldValue = "dsfsd"
        fixture.accessibility.insertionChangesField = false
        fixture.eventPoster.onPost = { fixture.accessibility.fieldValue = "dsfsd Yeah, that sounds good." }

        let outcome = await fixture.service.deliver("Yeah, that sounds good.", to: fixture.target)

        XCTAssertEqual(outcome, .pasted(restoration: .restored))
        XCTAssertEqual(fixture.accessibility.insertedTargets, [fixture.target])
        XCTAssertEqual(fixture.eventPoster.postedTargets, [fixture.target])
        XCTAssertEqual(fixture.eventPoster.frontmostPostCount, 0)
    }

    func testPasteIgnoredByTheProcessIsRetriedAsATypedShortcut() async {
        let fixture = Fixture()
        fixture.accessibility.fieldValue = ""
        fixture.accessibility.insertionChangesField = false
        fixture.eventPoster.onFrontmostPost = { fixture.accessibility.fieldValue = "Hello" }

        let outcome = await fixture.service.deliver("Hello", to: fixture.target)

        XCTAssertEqual(outcome, .pasted(restoration: .restored))
        XCTAssertEqual(fixture.eventPoster.postedTargets.count, 1)
        XCTAssertEqual(fixture.eventPoster.frontmostPostCount, 1)
    }

    func testTypedShortcutIsNotSentWhenAnotherAppCameForward() async {
        let fixture = Fixture()
        fixture.accessibility.fieldValue = ""
        fixture.accessibility.insertionChangesField = false
        fixture.eventPoster.onPost = { fixture.workspace.frontmost = nil }

        let outcome = await fixture.service.deliver("Hello", to: fixture.target)

        XCTAssertEqual(outcome, .copiedForManualPaste(.eventPostFailed))
        XCTAssertEqual(fixture.eventPoster.frontmostPostCount, 0)
    }

    func testPasteThatNeverLandsLeavesTheTranscriptOnTheClipboard() async {
        let fixture = Fixture()
        fixture.accessibility.fieldValue = "dsfsd"
        fixture.accessibility.insertionChangesField = false

        let outcome = await fixture.service.deliver("Yeah, that sounds good.", to: fixture.target)

        XCTAssertEqual(outcome, .copiedForManualPaste(.eventPostFailed))
        XCTAssertEqual(fixture.eventPoster.frontmostPostCount, 1)
        XCTAssertEqual(fixture.pasteboard.currentString, "Yeah, that sounds good.")
        XCTAssertEqual(fixture.pasteboard.restoreCount, 0)
    }

    func testPasteIntoUnreadableFieldIsTrusted() async {
        let fixture = Fixture()
        fixture.accessibility.insertionOutcome = .valueNotWritable

        let outcome = await fixture.service.deliver("Hello", to: fixture.target)

        XCTAssertEqual(outcome, .pasted(restoration: .restored))
        XCTAssertEqual(fixture.eventPoster.frontmostPostCount, 0)
    }

    func testFinalTextIsPastedWhenTheFieldDiscardedEveryDraft() async {
        let fixture = Fixture()
        let editor = DeliveryFakeLiveTextEditor()
        editor.finalizationOutcome = .noActiveDraft
        editor.cancellationOutcome = .noActiveDraft
        fixture.accessibility.fieldValue = "dsfsd"
        fixture.accessibility.insertionChangesField = false
        fixture.accessibility.focusedInputKindValue = .text
        fixture.eventPoster.onPost = { fixture.accessibility.fieldValue = "dsfsdYeah." }
        let service = fixture.makeService(liveTextEditor: editor)

        let outcome = await service.finalizeLiveTranscript("Yeah.", in: fixture.target)

        XCTAssertEqual(outcome, .pasted(restoration: .restored))
        XCTAssertEqual(editor.finalizedTexts, ["Yeah."])
    }
}

@MainActor
private final class Fixture {
    let target = PasteTarget(processIdentifier: 77, bundleIdentifier: "test.spark", launchDate: Date(timeIntervalSince1970: 77),
                             bundleURL: URL(fileURLWithPath: "/Applications/Test Spark.app"))!
    let workspace: DeliveryFakeWorkspace
    let accessibility = DeliveryFakeAccessibility(insertionOutcome: .inserted)
    let pasteboard = DeliveryFakePasteboard()
    let eventPoster = DeliveryFakeEventPoster()
    lazy var service = makeService()

    init() {
        workspace = DeliveryFakeWorkspace(capturedTarget: target, frontmost: target)
    }

    func makeService(liveTextEditor: any LiveTextEditing = DeliveryFakeLiveTextEditor()) -> TextDeliveryService {
        TextDeliveryService(
            workspace: workspace,
            accessibility: accessibility,
            pasteboard: pasteboard,
            eventPoster: eventPoster,
            liveTextEditor: liveTextEditor,
            sleeper: DeliveryImmediateSleeper(),
            activationAttempts: 2,
            activationRetryDelay: 0,
            restorationDelay: 0,
            insertionConfirmationDelay: 0
        )
    }
}
