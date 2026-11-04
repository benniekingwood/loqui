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
    /// Streaming at the 1.12 s tier: drafts trail speech by half as much.
    case unifiedStream1120 = "unified-stream-1120ms"
    /// Streaming at the 0.32 s tier, the fastest export.
    case unifiedStream320 = "unified-stream-320ms"

    var isStreaming: Bool { self != .v2 && self != .unified }

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
            return UnifiedStreamEngine(config: UnifiedConfig())
        case .unifiedStream1120:
            return UnifiedStreamEngine(config: UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7))
        case .unifiedStream320:
            return UnifiedStreamEngine(config: UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2))
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
    /// Transcribes as `transcribe` does and also returns the milliseconds
    /// between the end of the audio and the final text: the wait after the
    /// key is released.
    func transcribeTimingRelease(_ samples: [Float]) async throws -> (text: String, releaseMs: Double)
}

extension SpeechEngine {
    /// A batch model starts only once the audio ends, so the whole pass is the wait.
    func transcribeTimingRelease(_ samples: [Float]) async throws -> (text: String, releaseMs: Double) {
        let start = Date()
        let text = try await transcribe(samples)
        return (text, Date().timeIntervalSince(start) * 1000)
    }
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
    private let manager: StreamingUnifiedAsrManager
    private static let chunkSamples = 1600

    /// Each latency tier is its own encoder of about 580 MB, downloaded on first use.
    init(config: UnifiedConfig) { manager = StreamingUnifiedAsrManager(config: config) }

    func load() async throws -> TimeInterval {
        let start = Date()
        try await manager.loadModels()
        return Date().timeIntervalSince(start)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await stream(samples)
        return try await manager.finish()
    }

    /// Streams the clip the way live audio arrives, then times only `finish()`,
    /// which is all that's left to do when the key is released.
    func transcribeTimingRelease(_ samples: [Float]) async throws -> (text: String, releaseMs: Double) {
        try await stream(samples)
        let start = Date()
        let text = try await manager.finish()
        return (text, Date().timeIntervalSince(start) * 1000)
    }

    private func stream(_ samples: [Float]) async throws {
        try await manager.reset()
        var offset = 0
        while offset < samples.count {
            let end = min(offset + Self.chunkSamples, samples.count)
            try await manager.appendAudio(Self.buffer(for: samples[offset ..< end]))
            try await manager.processBufferedAudio()
            offset = end
        }
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
