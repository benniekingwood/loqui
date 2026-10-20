import Foundation
import XCTest
@testable import LoquiCore

final class SpeechContractsTests: XCTestCase {
    func testTranscriptClassifierPreservesLiteralCodeAndBlankMarkers() {
        XCTAssertEqual(TranscriptOutputClassifier.clean("  getUserByID != nil; [BLANK_AUDIO] \n"), "getUserByID != nil; [BLANK_AUDIO]")
    }

    func testModelFailuresNameTheConfiguredBackend() {
        let failures: [SpeechModelFailure] = [
            .missingModel(searchedPaths: []),
            .invalidModel(path: "/fixture", reason: "incomplete"),
            .modelLoadFailed(TranscriptionDiagnostic(domain: "CoreML", code: 1)),
            .unsupportedHardware,
        ]
        for failure in failures {
            XCTAssertTrue(failure.userMessage(modelName: "Whisperless").contains("The Whisperless model"), "\(failure)")
        }
        XCTAssertTrue(SpeechModelFailure.missingModel(searchedPaths: []).userMessage(modelName: "speech").hasPrefix("The speech model is missing"))
    }

    func testOverrideFailureExplainsTheVariableWithoutNamingTheBackend() {
        let failure = SpeechModelFailure.invalidOverride(variable: "LOQUI_MODEL_PATH", path: "/x", requirement: "a model directory")
        XCTAssertEqual(
            failure.userMessage(modelName: "Parakeet"),
            "LOQUI_MODEL_PATH must point to a model directory. Fix or unset it, then retry setup."
        )
    }

    func testFailureCategoriesAreStableLogTokens() {
        XCTAssertEqual(SpeechModelFailure.invalidOverride(variable: "", path: "", requirement: "").category, "invalid-override")
        XCTAssertEqual(SpeechModelFailure.missingModel(searchedPaths: []).category, "missing-model")
        XCTAssertEqual(SpeechModelFailure.invalidModel(path: "", reason: "").category, "invalid-model")
        XCTAssertEqual(SpeechModelFailure.modelLoadFailed(TranscriptionDiagnostic(domain: "", code: 0)).category, "model-load-failed")
        XCTAssertEqual(SpeechModelFailure.unsupportedHardware.category, "unsupported-hardware")
    }

    func testDiagnosticsKeepOnlyDomainAndCode() {
        let error = NSError(domain: "CoreML", code: 7, userInfo: [NSLocalizedDescriptionKey: "private dictated words"])
        XCTAssertEqual(TranscriptionDiagnostic(error: error), TranscriptionDiagnostic(domain: "CoreML", code: 7))
    }

    func testBackendsWithoutAnInMemoryPathProduceNoDrafts() async {
        let outcome = await FileOnlyTranscriber().transcribe(samples: [0, 0, 0])
        XCTAssertEqual(outcome, .cancelled)
    }
}

private struct FileOnlyTranscriber: SpeechTranscribing {
    func transcribe(audioURL: URL) async -> TranscriptionOutcome { .noSpeech }
}
