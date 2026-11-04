import Darwin
import FluidAudio
import Foundation

struct ClipResult: Codable {
    let id: String
    let durationSeconds: Double
    let reference: String
    let transcript: String
    /// Errors after lowercasing and removing punctuation.
    let wordErrors: Int
    /// Errors comparing the text exactly as it would be typed.
    let formattedErrors: Int
    let referenceWords: Int
    let latenciesMs: [Double]
    /// Wait after the audio ends for each pass. Missing from results saved
    /// before it was measured.
    let releaseMs: [Double]?
}

struct RunResult: Codable {
    let model: BenchmarkModel
    let date: Date
    let machine: String
    let loadSeconds: Double
    let firstPassMs: Double
    let peakMemoryMB: Double
    let passes: Int
    let clips: [ClipResult]
}

enum Runner {
    static func run(corpus: URL, model: BenchmarkModel, modelDirectory: URL?, passes: Int) async throws -> RunResult {
        let clips = try Corpus.load(from: corpus)
        guard !clips.isEmpty else { throw BenchmarkError("No clips in \(corpus.path). Record some with `record` first.") }

        let engine = try model.makeEngine(modelDirectory: modelDirectory)
        let loadSeconds = try await engine.load()

        // The first pass after loading pays one-time setup costs; report it
        // separately, then warm every clip once before measuring.
        let first = Date()
        _ = try await engine.transcribe(clips[0].samples)
        let firstPassMs = Date().timeIntervalSince(first) * 1000
        for clip in clips {
            _ = try await engine.transcribe(clip.samples)
        }

        var results: [ClipResult] = []
        for clip in clips {
            var latencies: [Double] = []
            var releases: [Double] = []
            var transcript = ""
            for _ in 0 ..< max(1, passes) {
                let start = Date()
                let pass = try await engine.transcribeTimingRelease(clip.samples)
                latencies.append(Date().timeIntervalSince(start) * 1000)
                releases.append(pass.releaseMs)
                transcript = pass.text
            }
            transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let reference = WordErrorRate.normalizedWords(clip.reference)
            results.append(
                ClipResult(
                    id: clip.id,
                    durationSeconds: Double(clip.samples.count) / 16000,
                    reference: clip.reference,
                    transcript: transcript,
                    wordErrors: WordErrorRate.edits(reference, WordErrorRate.normalizedWords(transcript)),
                    formattedErrors: WordErrorRate.edits(WordErrorRate.formattedWords(clip.reference), WordErrorRate.formattedWords(transcript)),
                    referenceWords: reference.count,
                    latenciesMs: latencies,
                    releaseMs: releases
                )
            )
            FileHandle.standardError.write(Data("  \(clip.id): \(Int(latencies.sorted()[latencies.count / 2])) ms\n".utf8))
        }

        return RunResult(
            model: model,
            date: Date(),
            machine: machineDescription(),
            loadSeconds: loadSeconds,
            firstPassMs: firstPassMs,
            peakMemoryMB: peakMemoryMB(),
            passes: passes,
            clips: results
        )
    }

    private static func peakMemoryMB() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        // macOS reports ru_maxrss in bytes.
        return Double(usage.ru_maxrss) / 1_048_576
    }

    private static func machineDescription() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let chip = String(decoding: brand.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "\(chip), \(memory) GB, macOS \(os)"
    }
}

struct Clip {
    let id: String
    let reference: String
    let samples: [Float]

    /// Below this peak a clip holds no usable sound. A working microphone
    /// picks up room noise above it even when nobody is talking.
    static let silentPeak: Float = 0.001

    static func isSilent(_ samples: [Float]) -> Bool {
        !samples.contains { abs($0) >= silentPeak }
    }
}

/// A corpus is a directory of audio files, each with a `.txt` reference of the
/// same name holding exactly what was said, written the way it should be typed.
enum Corpus {
    static let audioExtensions: Set = ["wav", "m4a", "caf", "aiff", "mp3"]

    static func load(from directory: URL) throws -> [Clip] {
        let converter = AudioConverter()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let clips: [Clip] = try files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { audio in
                let referenceURL = audio.deletingPathExtension().appendingPathExtension("txt")
                guard let reference = try? String(contentsOf: referenceURL, encoding: .utf8) else {
                    FileHandle.standardError.write(Data("  skipping \(audio.lastPathComponent): no .txt reference\n".utf8))
                    return nil
                }
                return try Clip(
                    id: audio.deletingPathExtension().lastPathComponent,
                    reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
                    samples: converter.resampleAudioFile(audio)
                )
            }
        let silent = clips.filter { Clip.isSilent($0.samples) }.map(\.id)
        guard silent.isEmpty else {
            throw BenchmarkError("""
            These clips are silent, so the results would be meaningless: \(silent.joined(separator: ", ")).
            Delete them and record again. See "If a recording is silent" in benchmarks/README.md.
            """)
        }
        return clips
    }
}

enum WordErrorRate {
    /// Lowercased words with punctuation removed, so "Hello, world." and
    /// "hello world" match, and "p.m." matches "PM". A period survives only
    /// between digits ("3.5"). Hyphens and slashes split words.
    static func normalizedWords(_ text: String) -> [String] {
        let characters = Array(text.lowercased().replacingOccurrences(of: "’", with: "'"))
        var kept = ""
        for (index, character) in characters.enumerated() {
            if character == "-" || character == "/" {
                kept.append(" ")
            } else if character == "." {
                let betweenDigits = index > 0 && index + 1 < characters.count
                    && characters[index - 1].isNumber && characters[index + 1].isNumber
                if betweenDigits { kept.append(character) }
            } else if character.isLetter || character.isNumber || character.isWhitespace || character == "'" || character == "%" {
                kept.append(character)
            }
        }
        return kept.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Words exactly as typed, case and punctuation included.
    static func formattedWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Word-level Levenshtein distance: substitutions + insertions + deletions.
    static func edits(_ reference: [String], _ hypothesis: [String]) -> Int {
        guard !reference.isEmpty else { return hypothesis.count }
        guard !hypothesis.isEmpty else { return reference.count }
        var previous = Array(0 ... hypothesis.count)
        for (row, word) in reference.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: hypothesis.count)
            for (column, candidate) in hypothesis.enumerated() {
                current[column + 1] = min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + (word == candidate ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[hypothesis.count]
    }
}
