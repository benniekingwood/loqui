#!/usr/bin/env bash
# Compares speech models on dictation you recorded with
# `loqui-model-bench record`. Each model runs in its own process so load time
# and peak memory are its own. Results land in benchmarks/results/<timestamp>/.
#
#   ./scripts/benchmark-models.sh                  # benchmarks/corpus
#   ./scripts/benchmark-models.sh path/to/corpus
#
# Optional:
#   LOQUI_BENCHMARK_PASSES=N              timed passes per clip (default 5)
#   LOQUI_BENCHMARK_MODELS="v2 unified"   models to compare
#                                         (default "v2 unified unified-stream")
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CORPUS="${1:-$ROOT/benchmarks/corpus}"
PASSES="${LOQUI_BENCHMARK_PASSES:-5}"
read -r -a MODELS <<< "${LOQUI_BENCHMARK_MODELS:-v2 unified unified-stream}"
PACKAGE="$ROOT/benchmarks/ModelBenchmark"

[[ -d "$CORPUS" ]] || {
    echo "error: no corpus at $CORPUS. Record one first:" >&2
    echo "  swift run -c release --package-path benchmarks/ModelBenchmark loqui-model-bench record benchmarks/corpus" >&2
    exit 1
}

swift build -c release --package-path "$PACKAGE"
BENCH="$(swift build -c release --package-path "$PACKAGE" --show-bin-path)/loqui-model-bench"
RESULTS="$ROOT/benchmarks/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS"

# A leftover v2 model is read from models/ in the checkout, so run from the root.
cd "$ROOT"
for model in "${MODELS[@]}"; do
    # Downloads the model if needed and pays the one-time Core ML compile, so
    # the measured run below times only loading from cache and inference.
    "$BENCH" prepare "$model"
done

files=()
for model in "${MODELS[@]}"; do
    echo "Running ${model}…"
    "$BENCH" run "$CORPUS" "$model" --passes "$PASSES" --output "$RESULTS/$model.json"
    files+=("$RESULTS/$model.json")
done

"$BENCH" report "${files[@]}" | tee "$RESULTS/report.md"
echo
echo "Saved to $RESULTS"
