@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// What to read aloud. Each line is also the clip's reference, written the way
/// it should end up typed. `[pause]` marks where to stop talking for about
/// three seconds; it is not part of the reference.
let prompts = [
    "Sounds good.",
    "Can you send me the notes from today's meeting?",
    "Let's push the release to Friday. I want one more day to test the installer.",
    "Open the pull request on GitHub and ask for a review of the Swift changes.",
    "The FluidAudio dependency is pinned to version 0.17.4 in Package.swift.",
    "Loqui runs Parakeet on the Neural Engine, so nothing leaves your Mac.",
    "Our meeting is on March 3rd at 2:30 PM, and the budget is $1,200.",
    "Let's meet at three. No, actually, make it four.",
    "Run npm install, then restart the dev server on port 3000.",
    "Remind me to call Dr. Patel about the MRI results.",
    "Priya, Mateo, and Siobhan are reviewing the design doc this afternoon.",
    "Set the timeout to 250 milliseconds and the retry count to 3.",
    "I need to check one thing. [pause] Okay, it's fine, go ahead.",
    "Hey team, quick update: the build is green, the docs are updated, and the beta goes out tomorrow.",
    """
    I looked at the crash reports from last week. Most of them come from the same code path, where we \
    read the settings file before it has finished writing. I think the fix is to write to a temporary \
    file and move it into place, which is atomic on APFS. I'll put up a pull request this afternoon.
    """,
]

enum Recorder {
    static func record(into directory: URL, freeForm: Bool, startingAt start: Int) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw BenchmarkError("Microphone access was denied. Allow your terminal under System Settings › Privacy & Security › Microphone.")
        }

        print("""
        Speak the way you normally dictate, at your usual distance from the mic.
        Recordings stay in \(directory.path) and are never committed.

        """)

        if freeForm {
            var number = nextFreeFormNumber(in: directory)
            while true {
                print("[free \(number)] Dictate anything you'd normally say. Enter starts, Enter stops (q to finish).")
                guard let (samples, saved) = try captureUntilKept(), saved else { return }
                print("Type exactly what you said, the way it should be typed:")
                guard let reference = readLine(), !reference.trimmingCharacters(in: .whitespaces).isEmpty else {
                    print("No text given, so the clip was not saved.\n")
                    continue
                }
                try save(samples, reference: reference, name: String(format: "free-%02d", number), in: directory)
                number += 1
            }
        }

        for (offset, prompt) in prompts.enumerated() where offset + 1 >= start {
            let number = offset + 1
            print("[\(number)/\(prompts.count)] Read this aloud:\n\n    \(prompt)\n")
            if prompt.contains("[pause]") {
                print("    At [pause], stop talking for about three seconds.\n")
            }
            guard let (samples, saved) = try captureUntilKept() else { return }
            guard saved else { continue }
            let reference = prompt.replacingOccurrences(of: " [pause]", with: "")
            try save(samples, reference: reference, name: String(format: "%02d", number), in: directory)
        }
        print("All prompts recorded. Add your own with `record \(directory.path) --free`.")
    }

    /// Records until the speaker keeps a take. Returns nil to quit, or
    /// `saved == false` to skip this prompt.
    private static func captureUntilKept() throws -> ([Float], saved: Bool)? {
        while true {
            print("Press Enter to start recording (s to skip, q to quit): ", terminator: "")
            switch readLine()?.lowercased() {
            case "q", nil: return nil
            case "s": return ([], false)
            default: break
            }
            let samples = try captureUntilEnter()
            if Clip.isSilent(samples) {
                print(silentTakeHelp)
                continue
            }
            let seconds = Double(samples.count) / 16000
            print(String(format: "Recorded %.1f s. Enter keeps it, r records again: ", seconds), terminator: "")
            if readLine()?.lowercased() != "r" {
                return (samples, true)
            }
        }
    }

    private static func captureUntilEnter() throws -> [Float] {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let buffer = SampleBuffer()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { pcm, _ in
            guard let channel = pcm.floatChannelData?[0] else { return }
            buffer.append(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
        }
        try engine.start()
        print("● Recording. Press Enter to stop.")
        _ = readLine()
        engine.stop()
        input.removeTap(onBus: 0)
        return try AudioConverter().resample(buffer.samples, from: format.sampleRate)
    }

    /// macOS hands a process silence, not an error, when the app it runs
    /// under isn't allowed to use the microphone.
    private static var silentTakeHelp: String {
        let app = ProcessInfo.processInfo.environment["TERM_PROGRAM"].map { "your terminal (\($0))" } ?? "your terminal"
        return """

        That take was silent: the microphone sent nothing but zeros, so it was not kept.
        macOS does this when \(app) isn't allowed to use the microphone, even if it
        says access was granted. Open System Settings › Privacy & Security › Microphone,
        turn \(app) on (or off and on again), quit and reopen it, then try again.
        Also check that the input under System Settings › Sound is the mic you're using.

        """
    }

    private static func save(_ samples: [Float], reference: String, name: String, in directory: URL) throws {
        let audio = directory.appendingPathComponent("\(name).wav")
        try AudioWAV.data(from: samples, sampleRate: 16000, normalize: false).write(to: audio)
        try (reference + "\n").write(to: directory.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
        print("Saved \(audio.lastPathComponent).\n")
    }

    private static func nextFreeFormNumber(in directory: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let numbers = names.compactMap { name -> Int? in
            guard name.hasPrefix("free-"), name.hasSuffix(".wav") else { return nil }
            return Int(name.dropFirst(5).dropLast(4))
        }
        return (numbers.max() ?? 0) + 1
    }
}

/// Collects samples from the audio thread.
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float] = []

    func append(_ samples: UnsafeBufferPointer<Float>) {
        lock.withLock { storage.append(contentsOf: samples) }
    }

    var samples: [Float] { lock.withLock { storage } }
}
