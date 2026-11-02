import Foundation
import XCTest
@testable import LoquiCore

final class TranscriptCleanupTests: XCTestCase {
    func testFillersLeaveWithTheirCommasAndSpaces() {
        XCTAssertEqual(FillerWords.remove(from: "So, um, we should go."), "So, we should go.")
        XCTAssertEqual(FillerWords.remove(from: "I think uh we should go."), "I think we should go.")
        XCTAssertEqual(FillerWords.remove(from: "I think, um."), "I think.")
        XCTAssertEqual(FillerWords.remove(from: "Well umm... maybe"), "Well maybe")
        XCTAssertEqual(FillerWords.remove(from: "Well uh… maybe"), "Well maybe")
        XCTAssertEqual(FillerWords.remove(from: "It was, er, erm, fine"), "It was, fine")
        XCTAssertEqual(FillerWords.remove(from: "Done, uh"), "Done")
        XCTAssertEqual(FillerWords.remove(from: "(um, aside)"), "(aside)")
    }

    func testAFillerThatStartedASentenceHandsOnItsCapital() {
        XCTAssertEqual(FillerWords.remove(from: "Um, so I think"), "So I think")
        XCTAssertEqual(FillerWords.remove(from: "Hello. Uh, we left. Ah. Then"), "Hello. We left. Then")
        XCTAssertEqual(FillerWords.remove(from: "Uh, um, okay"), "Okay")
    }

    func testFillerRemovalKeepsLineBreaks() {
        XCTAssertEqual(FillerWords.remove(from: "First line.\nUm, second"), "First line.\nSecond")
        XCTAssertEqual(FillerWords.remove(from: "one um\ntwo"), "one\ntwo")
    }

    func testFillerRemovalLeavesOtherWordsAlone() {
        for text in [
            "The umbrella is ahead of the error.",
            "Uhura said uh-huh.",
            "Take him to the ER.",
            "UM is a university.",
            "drum, Ahab, ermine",
            "Plain text, nothing to do.",
            "",
        ] {
            XCTAssertEqual(FillerWords.remove(from: text), text)
        }
    }

    func testSpokenBreaksReplaceTheirPhrasesAndThePunctuationAroundThem() {
        XCTAssertEqual(SpokenFormatting.apply(to: "Hello. New line. Next"), "Hello.\nNext")
        XCTAssertEqual(SpokenFormatting.apply(to: "One. New paragraph. Two."), "One.\n\nTwo.")
        XCTAssertEqual(SpokenFormatting.apply(to: "one, line break, two"), "one\ntwo")
        XCTAssertEqual(SpokenFormatting.apply(to: "a NEW LINE new line b"), "a\n\nb")
    }

    func testSpokenQuotesBecomeQuotationMarks() {
        XCTAssertEqual(SpokenFormatting.apply(to: "He said open quote hi close quote."), "He said \"hi\".")
        XCTAssertEqual(
            SpokenFormatting.apply(to: "He said, Open quote, hello, close quote, and left."),
            "He said, \"hello\", and left."
        )
        XCTAssertEqual(SpokenFormatting.apply(to: "open quote yes close quote then"), "\"yes\" then")
    }

    func testSpokenFormattingLeavesOtherWordsAlone() {
        for text in [
            "The newline character",
            "a new liner",
            "renew line items",
            "line breaker",
            "open quotes",
            "Plain text, nothing to do.",
            "",
        ] {
            XCTAssertEqual(SpokenFormatting.apply(to: text), text)
        }
    }

    func testDraftsLoseFillersButNeverGainLineBreaks() {
        let cleanup = TranscriptCleanup(removesFillerWords: true, appliesSpokenFormatting: true)
        XCTAssertEqual(cleanup.draftTranscript("Um, first new line"), "First new line")
        XCTAssertEqual(cleanup.finalTranscript("Um, first new line second"), "First\nsecond")
    }

    func testFinalTranscriptKeepsRequestedLineBreaksAtEitherEnd() {
        let cleanup = TranscriptCleanup(removesFillerWords: false, appliesSpokenFormatting: true)
        XCTAssertEqual(cleanup.finalTranscript("New paragraph. Dear team"), "\n\nDear team")
        XCTAssertEqual(cleanup.finalTranscript("Thanks. New line."), "Thanks.\n")
    }

    func testNoCleanupLeavesTranscriptsUntouched() {
        XCTAssertEqual(TranscriptCleanup.none.finalTranscript("Um, new line"), "Um, new line")
        XCTAssertEqual(TranscriptCleanup.none.draftTranscript("Um, new line"), "Um, new line")
    }

    func testATranscriptOfOnlyFillersIsNoSpeech() {
        let cleanup = TranscriptCleanup(removesFillerWords: true, appliesSpokenFormatting: false)
        XCTAssertEqual(cleanup.apply(to: .success("Um.")), .noSpeech)
        XCTAssertEqual(cleanup.apply(to: .success("Um, hi.")), .success("Hi."))
        XCTAssertEqual(cleanup.apply(to: .cancelled), .cancelled)
    }

    func testPreferencesDefaultToFillerRemovalOnAndSpokenFormattingOff() throws {
        let suite = "TranscriptCleanupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            TranscriptCleanup(defaults: defaults),
            TranscriptCleanup(removesFillerWords: true, appliesSpokenFormatting: false)
        )

        defaults.set(false, forKey: FillerWordPreference.defaultsKey)
        defaults.set(true, forKey: SpokenFormattingPreference.defaultsKey)
        XCTAssertEqual(
            TranscriptCleanup(defaults: defaults),
            TranscriptCleanup(removesFillerWords: false, appliesSpokenFormatting: true)
        )
    }
}
