import Foundation

package struct TranscriptionDiagnostic: Equatable, Sendable {
    package let domain: String
    package let code: Int

    package init(error: any Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
    }

    package init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

/// A speech backend's verified, loadable model. `summary` is content-free text
/// for public logs; `location` is logged only as a private hash.
package struct SpeechModelReadiness: Equatable, Sendable {
    package let summary: String
    package let location: URL

    package init(summary: String, location: URL) {
        self.summary = summary
        self.location = location
    }
}

/// Why a speech backend's model cannot be used. Shared by every backend so the
/// engine can explain failures without knowing which model is installed.
package enum SpeechModelFailure: Error, Equatable, Sendable {
    case invalidOverride(variable: String, path: String, requirement: String)
    case missingModel(searchedPaths: [String])
    case invalidModel(path: String, reason: String)
    case modelLoadFailed(TranscriptionDiagnostic)
    case unsupportedHardware

    package var category: String {
        switch self {
        case .invalidOverride: "invalid-override"
        case .missingModel: "missing-model"
        case .invalidModel: "invalid-model"
        case .modelLoadFailed: "model-load-failed"
        case .unsupportedHardware: "unsupported-hardware"
        }
    }

    package func userMessage(modelName: String) -> String {
        switch self {
        case let .invalidOverride(variable, _, requirement):
            "\(variable) must point to \(requirement). Fix or unset it, then retry setup."
        case .missingModel:
            "The \(modelName) model is missing. Run ./setup.sh from the Loqui checkout, or reinstall Loqui."
        case .invalidModel:
            "The \(modelName) model is incomplete or invalid. Run ./setup.sh from the Loqui checkout, or reinstall Loqui."
        case .modelLoadFailed:
            "The \(modelName) model could not load. Retry setup, or reinstall Loqui."
        case .unsupportedHardware:
            "The \(modelName) model requires Apple Silicon. On an Apple Silicon Mac, turn off Open using Rosetta and reopen Loqui."
        }
    }
}

package enum SpeechModelPreflightResult: Equatable, Sendable {
    case ready(SpeechModelReadiness)
    case failure(SpeechModelFailure)
}

package enum TranscriptionOutcome: Equatable, Sendable {
    case success(String)
    case noSpeech
    case modelUnavailable(SpeechModelFailure)
    case invalidAudio(AudioValidationFailure)
    case inferenceFailed(TranscriptionDiagnostic)
    case cancelled
}

/// Verifies that a speech backend's model is present, intact, and loadable on
/// this Mac before the microphone opens.
package protocol SpeechModelPreflighting: Sendable {
    func preflightSpeechModel() async -> SpeechModelPreflightResult
}

/// A speech-to-text backend. Final transcripts come from the finished recording
/// file; live drafts come from in-memory 16 kHz mono samples.
package protocol SpeechTranscribing: Sendable {
    func transcribe(audioURL: URL) async -> TranscriptionOutcome
    func transcribe(samples: [Float]) async -> TranscriptionOutcome
    func cancelActiveTranscriptions()
}

package extension SpeechTranscribing {
    /// Backends without an in-memory path produce no live drafts.
    func transcribe(samples: [Float]) async -> TranscriptionOutcome { .cancelled }
    func cancelActiveTranscriptions() {}
}

package enum TranscriptOutputClassifier {
    package static func clean(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
