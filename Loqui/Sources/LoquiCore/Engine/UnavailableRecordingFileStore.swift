import Foundation

@MainActor
package final class UnavailableRecordingFileStore: RecordingFileStoring {
    package init() {}

    package func allocateRecordingURL() throws -> URL {
        throw RecordingFileStoreError.unableToAllocateRecording
    }

    package func removeRecording(at url: URL) throws {}
    package func removeStaleOwnedFiles(olderThan age: TimeInterval) throws {}
    package func cleanupInstance() throws {}
}
