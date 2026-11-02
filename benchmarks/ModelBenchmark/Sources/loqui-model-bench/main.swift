import FluidAudio
import Foundation

let usage = """
usage:
  loqui-model-bench record <corpus-dir> [--free] [--start N]
      Read each prompt aloud and save it as NN.wav with its reference NN.txt.
      --free records what you'd normally dictate, then asks you to type it.
  loqui-model-bench prepare <model>
      Download the model if needed and load it once, so later runs time only
      inference. Models: v2, unified, unified-stream.
  loqui-model-bench run <corpus-dir> <model> [--model-dir DIR] [--passes N] [--output FILE]
      Load the model once, warm it up, then transcribe every clip N times
      (default 5). Writes a JSON result.
  loqui-model-bench report <result.json>...
      Compare results as a Markdown table.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

AppLogger.minimumLevel = .error
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }

do {
    switch command {
    case "record":
        guard arguments.count >= 2 else { fail(usage) }
        let start = option("--start", in: arguments).flatMap(Int.init) ?? 1
        try await Recorder.record(
            into: URL(fileURLWithPath: arguments[1], isDirectory: true),
            freeForm: arguments.contains("--free"),
            startingAt: start
        )
    case "prepare":
        guard arguments.count >= 2, let model = BenchmarkModel(rawValue: arguments[1]) else { fail(usage) }
        let engine = try model.makeEngine(modelDirectory: option("--model-dir", in: arguments).map { URL(fileURLWithPath: $0) })
        _ = try await engine.load()
        print("\(model.rawValue) is ready.")
    case "run":
        guard arguments.count >= 3, let model = BenchmarkModel(rawValue: arguments[2]) else { fail(usage) }
        let result = try await Runner.run(
            corpus: URL(fileURLWithPath: arguments[1], isDirectory: true),
            model: model,
            modelDirectory: option("--model-dir", in: arguments).map { URL(fileURLWithPath: $0) },
            passes: option("--passes", in: arguments).flatMap(Int.init) ?? 5
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        if let output = option("--output", in: arguments) {
            try data.write(to: URL(fileURLWithPath: output))
        } else {
            FileHandle.standardOutput.write(data)
        }
        FileHandle.standardError.write(Data(Report.summaryLine(for: result).utf8))
    case "report":
        let results = try arguments.dropFirst().map { path in
            try JSONDecoder().decode(RunResult.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        }
        guard !results.isEmpty else { fail(usage) }
        print(Report.markdown(for: results))
    default:
        fail(usage)
    }
} catch {
    fail(String(describing: error))
}
