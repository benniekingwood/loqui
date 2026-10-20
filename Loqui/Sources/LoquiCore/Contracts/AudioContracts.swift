import Foundation
import os

package enum MicrophoneAuthorization: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

@MainActor
package protocol MicrophonePermissionProviding: AnyObject {
    func authorizationStatus() -> MicrophoneAuthorization
    func requestAccess() async -> Bool
}

package struct RecorderErrorDiagnostic: Equatable, Sendable {
    package let domain: String
    package let code: Int

    package init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

package enum RecorderEvent: Equatable, Sendable {
    case maximumDurationReached
    case interrupted
    case deviceUnavailable
    case encodeError(RecorderErrorDiagnostic)
    case unexpectedCompletion
}

package enum RecorderStopOutcome: Equatable, Sendable {
    case finished
    case notRecording
    case encodeError(RecorderErrorDiagnostic)
    case unsuccessfulCompletion
    case finalizationTimedOut
    case cancelled
}

@MainActor
package protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    /// Loudest sample captured so far in dBFS, or `-.infinity` before any audio
    /// arrives. The engine uses this to tell silence apart from speech instead
    /// of trusting a recognizer to classify silent input.
    var peakLevel: Float { get }
    /// The input the session actually opened, for status text and logging.
    var inputDeviceName: String { get }
    /// Opens the selected microphone and returns only after input buffers arrive.
    /// Warm-up audio is discarded so a ready cue can play after a slow Bluetooth
    /// route has settled without becoming part of the recording.
    func prepare() async -> Bool
    /// Enables file capture and returns only after a post-cue buffer reaches the
    /// WAV. Starting an audio unit alone is not a readiness guarantee on macOS.
    func start(maximumDuration: TimeInterval) async -> Bool
    func stop() async -> RecorderStopOutcome
    func cancel()
    /// Loudest linear sample (0...1) since the previous call, for level meters.
    func takeRecentPeakAmplitude() -> Float
    /// Every 16 kHz mono sample captured so far, for live drafts, or nil when
    /// the recorder keeps no in-memory copy.
    func snapshotSamples() -> [Float]?
}

package extension AudioRecording {
    func takeRecentPeakAmplitude() -> Float { 0 }
    func snapshotSamples() -> [Float]? { nil }
}

package enum AudioRecorderCreationError: Error, Equatable, Sendable {
    case noInputDevice
    case inputDeviceUnusable
}

@MainActor
package protocol AudioRecorderCreating: AnyObject {
    func makeRecorder(
        at url: URL,
        eventHandler: @escaping @MainActor (RecorderEvent) -> Void
    ) throws -> any AudioRecording
}

package enum RecordingFileStoreError: Error, Equatable, Sendable {
    case unableToCreateDirectory
    case unableToAllocateRecording
    case cleanupFailed
    case outOfScopeURL
}

/// How long another Loqui instance's leftover recordings are kept before startup
/// cleanup removes them.
package enum RecordingFileRetention {
    package static let staleFileAge: TimeInterval = 24 * 60 * 60
}

@MainActor
package protocol RecordingFileStoring: AnyObject {
    func allocateRecordingURL() throws -> URL
    func removeRecording(at url: URL) throws
    func removeStaleOwnedFiles(olderThan age: TimeInterval) throws
    func cleanupInstance() throws
}

package enum AudioValidationFailure: Equatable, Sendable {
    case missing
    case empty
    case unreadableFormat
    case tooShort(duration: TimeInterval)
    case tooLong(duration: TimeInterval)
}

package enum AudioValidationResult: Equatable, Sendable {
    case valid(duration: TimeInterval)
    case invalid(AudioValidationFailure)
}

package protocol AudioValidating: Sendable {
    /// Recordings shorter than this hold too little audio to transcribe.
    var minimumUsefulDuration: TimeInterval { get }
    func validateAudio(at url: URL) -> AudioValidationResult
}
