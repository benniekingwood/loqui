import Foundation

enum Report {
    static func summaryLine(for result: RunResult) -> String {
        let stats = Stats(result)
        return String(
            format: "%@: WER %.2f%%, median %.0f ms, p95 %.0f ms, load %.2f s, peak %.0f MB\n",
            result.model.rawValue, stats.wer, stats.medianMs, stats.p95Ms, result.loadSeconds, result.peakMemoryMB
        )
    }

    static func markdown(for results: [RunResult]) -> String {
        var lines: [String] = []
        let machines = Set(results.map(\.machine)).sorted()
        lines.append("Machine: \(machines.joined(separator: "; "))")
        lines
            .append(
                "Clips: \(results[0].clips.count), \(String(format: "%.0f", results[0].clips.map(\.durationSeconds).reduce(0, +))) s of audio; \(results[0].passes) timed passes each"
            )
        lines.append("")
        lines.append("| Model | WER | Formatted WER | Median clip | p95 clip | Real time | Load | First pass | Peak memory |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for result in results {
            let stats = Stats(result)
            lines.append(
                String(
                    format: "| %@ | %.2f%% | %.2f%% | %.0f ms | %.0f ms | %.0f× | %.2f s | %.0f ms | %.0f MB |",
                    result.model.rawValue, stats.wer, stats.formattedWer, stats.medianMs, stats.p95Ms,
                    stats.realTimeFactor, result.loadSeconds, result.firstPassMs, result.peakMemoryMB
                )
            )
        }

        lines.append("")
        lines.append("WER ignores case and punctuation. Formatted WER compares the text exactly as it would be typed.")
        if results.contains(where: { $0.model == .unifiedStream }) {
            lines.append(
                "unified-stream times the compute to stream a whole clip in 100 ms chunks. Live, that work is spread across the time you speak."
            )
        }
        lines.append("")
        lines.append("### Clips where the models differ")
        lines.append("")
        let byID = results.map { result in Dictionary(uniqueKeysWithValues: result.clips.map { ($0.id, $0) }) }
        for clip in results[0].clips {
            let transcripts = byID.map { $0[clip.id]?.transcript ?? "" }
            guard Set(transcripts).count > 1 || transcripts.contains(where: { $0 != clip.reference }) else { continue }
            lines.append("**\(clip.id)** (\(String(format: "%.1f", clip.durationSeconds)) s)")
            lines.append("")
            lines.append("- reference: \(clip.reference)")
            for (result, clips) in zip(results, byID) {
                guard let other = clips[clip.id] else { continue }
                lines.append("- \(result.model.rawValue) (\(other.wordErrors) errors): \(other.transcript)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private struct Stats {
        let wer: Double
        let formattedWer: Double
        let medianMs: Double
        let p95Ms: Double
        let realTimeFactor: Double

        init(_ result: RunResult) {
            let words = Double(max(1, result.clips.map(\.referenceWords).reduce(0, +)))
            let formattedWords = Double(max(1, result.clips.map { $0.reference.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)))
            wer = Double(result.clips.map(\.wordErrors).reduce(0, +)) / words * 100
            formattedWer = Double(result.clips.map(\.formattedErrors).reduce(0, +)) / formattedWords * 100
            // Each clip's median pass, so every clip counts once.
            let medians = result.clips.map { Self.percentile($0.latenciesMs, 0.5) }
            medianMs = Self.percentile(medians, 0.5)
            p95Ms = Self.percentile(result.clips.flatMap(\.latenciesMs), 0.95)
            let audio = result.clips.map(\.durationSeconds).reduce(0, +)
            realTimeFactor = audio / max(0.001, medians.reduce(0, +) / 1000)
        }

        static func percentile(_ values: [Double], _ fraction: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            // Linear interpolation, so the median of an even count averages
            // the middle two instead of picking the slower one.
            let sorted = values.sorted()
            let position = Double(sorted.count - 1) * fraction
            let lower = Int(position.rounded(.down))
            let upper = min(sorted.count - 1, lower + 1)
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
        }
    }
}
