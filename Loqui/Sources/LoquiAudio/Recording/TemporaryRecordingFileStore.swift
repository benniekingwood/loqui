@preconcurrency import AVFoundation
import AppKit
import Foundation
import os
import LoquiCore

private let recordingFileStoreLog = OSLog(
    subsystem: AppIdentity.bundleIdentifier,
    category: "recording-file-store"
)

@MainActor
package final class TemporaryRecordingFileStore: RecordingFileStoring {
    package static let staleFileAge: TimeInterval = 24 * 60 * 60

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let instanceDirectoryURL: URL
    private let now: () -> Date

    package init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        instanceIdentifier: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) throws {
        self.fileManager = fileManager
        self.now = now
        baseDirectoryURL = (temporaryDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent("Loqui", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
        instanceDirectoryURL = baseDirectoryURL
            .appendingPathComponent("instance-\(instanceIdentifier.uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: instanceDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecordingFileStoreError.unableToCreateDirectory
        }
    }

    package func allocateRecordingURL() throws -> URL {
        if !fileManager.fileExists(atPath: instanceDirectoryURL.path) {
            do {
                try fileManager.createDirectory(
                    at: instanceDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw RecordingFileStoreError.unableToAllocateRecording
            }
        }

        return instanceDirectoryURL
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    package func removeRecording(at url: URL) throws {
        guard ownsRecordingURL(url) else {
            throw RecordingFileStoreError.outOfScopeURL
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw RecordingFileStoreError.cleanupFailed
        }
    }

    package func removeStaleOwnedFiles(olderThan age: TimeInterval = staleFileAge) throws {
        guard fileManager.fileExists(atPath: baseDirectoryURL.path) else {
            return
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: baseDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RecordingFileStoreError.cleanupFailed
        }

        let cutoff = now().addingTimeInterval(-max(0, age))
        var metadataLookupFailed = false
        for url in contents where url.lastPathComponent.hasPrefix("instance-") {
            guard url.standardizedFileURL != instanceDirectoryURL.standardizedFileURL else {
                continue
            }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(
                    forKeys: [.isDirectoryKey, .contentModificationDateKey]
                )
            } catch {
                let errorType = String(describing: type(of: error))
                os_log(
                    "Stale recording metadata lookup failed; error type: %{public}@",
                    log: recordingFileStoreLog,
                    type: .error,
                    errorType
                )
                metadataLookupFailed = true
                continue
            }
            guard values.isDirectory == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw RecordingFileStoreError.cleanupFailed
            }
        }
        if metadataLookupFailed {
            throw RecordingFileStoreError.cleanupFailed
        }
    }

    package func cleanupInstance() throws {
        guard fileManager.fileExists(atPath: instanceDirectoryURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: instanceDirectoryURL)
        } catch {
            throw RecordingFileStoreError.cleanupFailed
        }
    }

    private func ownsRecordingURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "wav"
            && url.deletingLastPathComponent().standardizedFileURL == instanceDirectoryURL.standardizedFileURL
            && url.lastPathComponent.hasPrefix("recording-")
    }
}
