@preconcurrency import AVFoundation
import Foundation
import LoquiCore

package struct RecordedAudioValidator: AudioValidating, @unchecked Sendable {
    package let minimumUsefulDuration: TimeInterval
    package let maximumUsefulDuration: TimeInterval
    private let fileManager: FileManager

    package init(
        minimumUsefulDuration: TimeInterval = 0.1,
        maximumUsefulDuration: TimeInterval = 301,
        fileManager: FileManager = .default
    ) {
        self.minimumUsefulDuration = minimumUsefulDuration
        self.maximumUsefulDuration = maximumUsefulDuration
        self.fileManager = fileManager
    }

    package func validateAudio(at url: URL) -> AudioValidationResult {
        guard fileManager.fileExists(atPath: url.path) else {
            return .invalid(.missing)
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0 else {
            return .invalid(.empty)
        }

        guard let audioFile = try? AVAudioFile(forReading: url),
              audioFile.fileFormat.sampleRate > 0 else {
            return .invalid(.unreadableFormat)
        }

        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        guard duration.isFinite, duration >= minimumUsefulDuration else {
            return .invalid(.tooShort(duration: max(0, duration)))
        }
        guard duration <= maximumUsefulDuration else {
            return .invalid(.tooLong(duration: duration))
        }
        return .valid(duration: duration)
    }
}
