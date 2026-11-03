import AVFoundation
import FluidAudio
import Foundation

enum BenchmarkModel: String, Codable, CaseIterable {
    /// Parakeet TDT 0.6B v2, what Loqui shipped before 1.1.0.
    case v2
    /// Parakeet Unified English 0.6B, whole clip at once, the way
    /// `FluidAudioParakeetRecognizer` calls it (issue #12).
    case unified
    /// Parakeet Unified English 0.6B fed in 100 ms chunks like live audio, at
    /// the default 2.08 s latency tier (issue #13).
    case unifiedStream = "unified-stream"

    func makeEngine(modelDirectory: URL?) throws -> any SpeechEngine {
        switch self {
        case .v2:
            if let modelDirectory {
                guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
                    throw BenchmarkError("No v2 model at \(modelDirectory.path).")
                }
                return ParakeetV2Engine(directory: modelDirectory)
            }
            // Loqui no longer installs v2, so use a checkout's leftover copy
            // when there is one and download it otherwise.
            let leftover = Self.repositoryModelDirectory
            return ParakeetV2Engine(directory: FileManager.default.fileExists(atPath: leftover.path) ? leftover : nil)
        case .unified:
            return UnifiedBatchEngine()
        case .unifiedStream:
            return UnifiedStreamEngine()
        }
    }

    /// `models/parakeet-tdt-0.6b-v2-coreml` in the checkout, found from the
    /// working directory the way the repository scripts run.
    private static var repositoryModelDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("models/parakeet-tdt-0.6b-v2-coreml", isDirectory: true)
    }
}

struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

protocol SpeechEngine: AnyObject {
    /// Loads the model and returns the seconds it took.
    func load() async throws -> TimeInterval
    func transcribe(_ samples: [Float]) async throws -> String
}

final class ParakeetV2Engine: SpeechEngine {
    private let directory: URL?
    private var models: AsrModels?

    /// Pass `nil` to use FluidAudio's download cache, about 450 MB on first use.
    init(directory: URL?) { self.directory = directory }

    func load() async throws -> TimeInterval {
        let source: URL
        if let directory {
            source = directory
        } else {
            source = try await AsrModels.download(version: .v2)
        }
        let start = Date()
        models = try AsrModels.loadLocal(from: source, version: .v2, configuration: AsrModels.defaultConfiguration())
        return Date().timeIntervalSince(start)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let models else { throw BenchmarkError("v2 is not loaded") }
        let manager = AsrManager(models: models)
        var decoder = TdtDecoderState.make(decoderLayers: models.version.decoderLayers)
        return try await manager.transcribe(samples, decoderState: &decoder).text
    }
}

final class UnifiedBatchEngine: SpeechEngine {
    private let manager = UnifiedAsrManager()

    func load() async throws -> TimeInterval {
        let start = Date()
        try await manager.loadModels()
        return Date().timeIntervalSince(start)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await manager.transcribe(samples)
    }
}

final class UnifiedStreamEngine: SpeechEngine {
    private let manager = StreamingUnifiedAsrManager()
    private static let chunkSamples = 1600

    func load() async throws -> TimeInterval {
        let start = Date()
        try await manager.loadModels()
        return Date().timeIntervalSince(start)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await manager.reset()
        var offset = 0
        while offset < samples.count {
            let end = min(offset + Self.chunkSamples, samples.count)
            try await manager.appendAudio(Self.buffer(for: samples[offset ..< end]))
            try await manager.processBufferedAudio()
            offset = end
        }
        return try await manager.finish()
    }

    private static func buffer(for chunk: ArraySlice<Float>) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw BenchmarkError("Could not allocate an audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(chunk.count)
        chunk.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: chunk.count) }
        return buffer
    }
}
