import Foundation
import os

private let dependencyLogger = Logger(
    subsystem: AppIdentity.bundleIdentifier,
    category: "engine"
)

package extension TranscriptionEngine {
    func logTemporaryFileError(operation: StaticString, error: any Error) {
        let errorType = String(describing: type(of: error))
        dependencyLogger.error(
            "Temporary recording \(operation, privacy: .public) failed; error type: \(errorType, privacy: .public)"
        )
    }

    func logTranscriptionOutcome(_ outcome: TranscriptionOutcome) {
        switch outcome {
        case let .success(text):
            dependencyLogger.notice("Transcription succeeded; characters: \(text.count, privacy: .public)")
        case .noSpeech:
            dependencyLogger.notice("Transcription succeeded with no speech")
        case let .modelUnavailable(failure):
            dependencyLogger.error("Speech model unavailable; category: \(failure.category, privacy: .public)")
        case let .invalidAudio(reason):
            dependencyLogger.error("Transcription rejected invalid audio; reason: \(String(describing: reason), privacy: .public)")
        case let .inferenceFailed(diagnostic):
            dependencyLogger.error("Speech inference failed; domain: \(diagnostic.domain, privacy: .private), code: \(diagnostic.code, privacy: .public)")
        case .cancelled:
            dependencyLogger.notice("Transcription cancelled")
        }
    }

    func dependencyPreflightResult() async -> SpeechModelPreflightResult {
        if let cachedDependencyPreflight {
            return cachedDependencyPreflight
        }
        if let dependencyPreparationTask {
            return await dependencyPreparationTask.value
        }

        let preflight = dependencyPreflight
        let task = Task {
            await preflight.preflightSpeechModel()
        }
        dependencyPreparationTask = task
        let result = await task.value
        dependencyPreparationTask = nil
        cachedDependencyPreflight = result
        logDependencyPreflight(result)
        return result
    }

    func logDependencyPreflight(_ result: SpeechModelPreflightResult) {
        switch result {
        case let .ready(readiness):
            dependencyLogger.notice(
                "Speech model ready; \(readiness.summary, privacy: .public); model: \(readiness.location.path, privacy: .private(mask: .hash))"
            )
        case let .failure(failure):
            dependencyLogger.error(
                "Speech model preflight failed; category: \(failure.category, privacy: .public)"
            )
        }
    }
}
