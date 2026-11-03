# Model benchmark

Compares speech models on your own dictation before Loqui switches to one
([#12](https://github.com/benniekingwood/loqui/issues/12)). It runs each model
through the same FluidAudio release Loqui pins, keeps it loaded the way Loqui
does, and reports accuracy, latency, load time, and memory.

| Model | What it is |
|---|---|
| `v2` | Parakeet TDT 0.6B v2, what Loqui shipped before 1.1.0. Read from `models/` if an older setup left it there, or downloaded (about 450 MB) on first use. |
| `unified` | Parakeet Unified English 0.6B, whole clip at once, what Loqui ships today. Downloads about 600 MB on first use. |
| `unified-stream` | The same model fed in 100 ms chunks like live audio ([#13](https://github.com/benniekingwood/loqui/issues/13)). Its encoder is a second download of about 580 MB. |

The benchmark is a separate Swift package and isn't part of the app.

## 1. Record

```sh
swift run -c release --package-path benchmarks/ModelBenchmark \
  loqui-model-bench record benchmarks/corpus
```

It shows 15 prompts covering short replies, technical terms, numbers and times,
names, a correction, a pause, and a 20-second paragraph. Read each one aloud
the way you normally dictate, at your usual distance from the mic. Press Enter
to start and stop each recording. You can redo or skip any prompt. `--start N`
picks up from prompt N.

Then add a few clips of what you'd really dictate:

```sh
swift run -c release --package-path benchmarks/ModelBenchmark \
  loqui-model-bench record benchmarks/corpus --free
```

After each one, type exactly what you said, the way it should be typed. Unscripted
speech is the better test, so aim for at least five.

macOS asks your terminal app for microphone access the first time. Recordings
are 16 kHz WAV files with a `.txt` reference beside each. `benchmarks/corpus/`
is ignored by Git, so your voice never gets committed. You can also drop in
your own `.wav` or `.m4a` files with a matching `.txt`.

### If a recording is silent

The recorder won't keep a silent take, and `run` refuses a corpus with silent
clips. macOS sends silence instead of an error when your terminal app isn't
allowed to use the microphone, even after saying access was granted. Open
System Settings › Privacy & Security › Microphone, turn your terminal on (or
off and on again), quit and reopen it, and record again. If it's still silent,
check the input under System Settings › Sound, or record from Terminal.app.

## 2. Compare

```sh
./scripts/benchmark-models.sh
```

It prints a Markdown table and saves it, with the raw JSON, to
`benchmarks/results/<timestamp>/`:

- **WER** is word errors per reference word, ignoring case and punctuation.
- **Formatted WER** compares the text exactly as it would be typed, so it
  counts missing punctuation, wrong capitals, and "2.30" for "2:30".
- **Median clip** and **p95 clip** are warm transcription times after a
  warm-up pass. **First pass** is the first transcription after loading.
- **Load** is loading an already-compiled model. **Peak memory** is the
  benchmark process's peak resident memory.

The report then lists each clip that any model got wrong, with every model's text.

For a fair comparison, keep your Mac plugged in, close other heavy apps, and
run it twice. Results from someone else's Mac don't carry over to yours.
