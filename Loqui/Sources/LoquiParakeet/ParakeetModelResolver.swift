import Foundation
import LoquiCore

/// These weights and the SDK version are reviewed together. Setup and bundling
/// verify every file against the same manifest before the app loads local assets.
package enum ParakeetModelContract {
    package static let directoryName = "parakeet-tdt-0.6b-v2-coreml"
    package static let sdkVersion = "0.17.4"
    package static let requiredComponents = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc",
    ]

    package static var manifestURL: URL {
        #if SWIFT_PACKAGE
            if Bundle.main.bundleURL.pathExtension != "app" {
                return (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("parakeet-model.json")
            }
        #endif
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("parakeet-model.json")
    }
}

package struct ParakeetModelManifest: Decodable, Sendable {
    package struct File: Decodable, Sendable {
        package let path: String
        package let size: UInt64
        package let sha256: String
    }

    package let repository: String
    package let revision: String
    package let directory: String
    package let fluidAudioVersion: String
    package let files: [File]
}

package enum DependencySearchSource: String, Equatable, Sendable {
    case override
    case bundled
    case development
    case userData
}

package struct ResolvedDependencyPath: Equatable, Sendable {
    package let url: URL
    package let source: DependencySearchSource
}

/// Where the verified Parakeet model was found.
package struct ParakeetModelLocation: Equatable, Sendable {
    package let model: ResolvedDependencyPath

    package var readiness: SpeechModelReadiness {
        SpeechModelReadiness(
            summary: "Parakeet TDT 0.6B v2; FluidAudio=\(ParakeetModelContract.sdkVersion); model source=\(model.source.rawValue)",
            location: model.url
        )
    }
}

package enum ParakeetModelResolution: Equatable, Sendable {
    case ready(ParakeetModelLocation)
    case failure(SpeechModelFailure)
}

package struct ParakeetResolverConfiguration: Sendable {
    package var environment: [String: String]
    package var bundleResourceURL: URL?
    package var executableURL: URL?
    package var currentDirectoryURL: URL
    package var applicationSupportURL: URL
    package var manifestURL: URL

    package static var production: Self {
        Self(
            environment: ProcessInfo.processInfo.environment,
            bundleResourceURL: Bundle.main.resourceURL,
            executableURL: Bundle.main.executableURL,
            currentDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            applicationSupportURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Loqui", isDirectory: true),
            manifestURL: ParakeetModelContract.manifestURL
        )
    }
}

package protocol ParakeetModelResolving: Sendable {
    func preflight() -> ParakeetModelResolution
}

/// Finds the pinned Parakeet model and checks every file against the manifest.
/// The manifest is decoded once per resolver; the files are re-checked on each
/// preflight so a model replaced on disk is never loaded unverified.
package struct ParakeetModelResolver: ParakeetModelResolving {
    package let configuration: ParakeetResolverConfiguration
    private let manifestCache = ManifestCache()

    package init(configuration: ParakeetResolverConfiguration = .production) {
        self.configuration = configuration
    }

    package func preflight() -> ParakeetModelResolution {
        guard let manifest = manifestCache.manifest(at: configuration.manifestURL) else {
            return .failure(.invalidModel(path: configuration.manifestURL.path, reason: "model manifest is unreadable"))
        }
        guard manifest.directory == ParakeetModelContract.directoryName,
              manifest.fluidAudioVersion == ParakeetModelContract.sdkVersion,
              !manifest.files.isEmpty else {
            return .failure(.invalidModel(path: configuration.manifestURL.path, reason: "model manifest does not match the backend"))
        }

        if let override = configuration.environment["LOQUI_MODEL_PATH"], !override.isEmpty {
            let url = resolveDirectory(override)
            if let reason = validationFailure(at: url, manifest: manifest) {
                return .failure(.invalidOverride(
                    variable: "LOQUI_MODEL_PATH",
                    path: url.path,
                    requirement: "a complete Parakeet v2 model directory (\(reason))"
                ))
            }
            return .ready(ParakeetModelLocation(model: ResolvedDependencyPath(url: url, source: .override)))
        }

        let candidates = modelCandidates()
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.url.path) {
            // An invalid preferred bundle must never silently select different weights.
            if let reason = validationFailure(at: candidate.url, manifest: manifest) {
                return .failure(.invalidModel(path: candidate.url.path, reason: reason))
            }
            return .ready(ParakeetModelLocation(model: candidate))
        }
        return .failure(.missingModel(searchedPaths: candidates.map { $0.url.path }))
    }

    private func resolveDirectory(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL }
        return configuration.currentDirectoryURL.appendingPathComponent(path, isDirectory: true).standardizedFileURL
    }

    private func modelCandidates() -> [ResolvedDependencyPath] {
        var candidates: [ResolvedDependencyPath] = []
        func append(_ root: URL, source: DependencySearchSource) {
            let url = root.appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(ParakeetModelContract.directoryName, isDirectory: true).standardizedFileURL
            if !candidates.contains(where: { $0.url == url }) {
                candidates.append(ResolvedDependencyPath(url: url, source: source))
            }
        }
        if let resourceURL = configuration.bundleResourceURL { append(resourceURL, source: .bundled) }
        if let root = configuration.environment["LOQUI_DEVELOPMENT_ROOT"], !root.isEmpty {
            append(resolveDirectory(root), source: .development)
        }
        if let executableURL = configuration.executableURL {
            var ancestor = executableURL.deletingLastPathComponent()
            while ancestor.path != "/" {
                if ancestor.lastPathComponent == ".build" {
                    append(ancestor.deletingLastPathComponent().deletingLastPathComponent(), source: .development)
                    break
                }
                ancestor.deleteLastPathComponent()
            }
        }
        append(configuration.currentDirectoryURL, source: .development)
        append(configuration.currentDirectoryURL.deletingLastPathComponent(), source: .development)
        append(configuration.applicationSupportURL, source: .userData)
        return candidates
    }

    private func validationFailure(at root: URL, manifest: ParakeetModelManifest) -> String? {
        let fileManager = FileManager.default
        guard let values = try? root.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
            return "directory is missing"
        }
        for entry in manifest.files {
            let file = root.appendingPathComponent(entry.path).standardizedFileURL
            guard file.path.hasPrefix(root.standardizedFileURL.path + "/"),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  fileManager.isReadableFile(atPath: file.path),
                  values.fileSize.map({ UInt64($0) == entry.size }) == true else {
                return "a required file is missing, unreadable, or has the wrong size"
            }
        }
        return nil
    }
}

/// Holds the decoded manifest so repeated preflights skip JSON decoding. The
/// manifest ships inside the app and never changes while Loqui runs.
private final class ManifestCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: (url: URL, manifest: ParakeetModelManifest)?

    func manifest(at url: URL) -> ParakeetModelManifest? {
        if let cached = lock.withLock({ cached }), cached.url == url {
            return cached.manifest
        }
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ParakeetModelManifest.self, from: data) else {
            return nil
        }
        lock.withLock { cached = (url, manifest) }
        return manifest
    }
}
