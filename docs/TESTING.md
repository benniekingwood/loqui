# Testing Loqui

Run every module's tests from the repository root:

```sh
swift test --package-path Loqui -Xswiftc -warnings-as-errors
```

Each module has its own test target (`LoquiCoreTests`, `LoquiAudioTests`,
`LoquiParakeetTests`, `LoquiDeliveryTests`, `LoquiShortcutsTests`,
`LoquiInterfaceTests`, and `LoquiAppTests`). Engine fakes shared between them
live in the `LoquiTestSupport` target. `LoquiArchitectureTests` reads the
sources themselves and fails when a module imports past its layer, when a
package dependency other than FluidAudio appears, when anything but
`LoquiParakeet` imports FluidAudio, when a log interpolation omits its privacy
level, or when any tracked file refers back to the project Loqui started from.

The safety-critical coverage expectation is behavioral rather than a single
line-percentage target. A change must keep deterministic tests for:

- dependency preflight before recording, output cleanup, and the distinction
  between successful no-speech output and every transcription failure;
- permission/start/stop/recorder callback races, verified input readiness,
  cancellation while audio is still opening, maximum duration, explicit state
  transitions, and failure presentation;
- resampling across input-rate changes, discarded warm-up audio, complete
  trailing samples on stop, input metering, in-memory draft samples, skipped
  passes while no new audio arrives, and final inference proceeding while
  cancelled preview work winds down;
- unique session recordings plus cleanup after success, failure, cancellation,
  startup stale-file pruning, and application termination;
- captured-target identity, PID reuse/relaunch, closed windows, target switches,
  activation exhaustion, event failure, and never posting to an unverified app;
- serialized clipboard transactions, checked writes, cancellation handoff,
  restoration, and manual-copy fallback policy without real keystrokes; and
- a static privacy regression check that rejects raw transcript or
  clipboard-content logging and requires every logged value to state its
  privacy level.

The ordinary Swift suite uses injected recognizers and requires no model download.
To check the actual system default microphone after granting microphone access,
run:

```sh
LOQUI_MICROPHONE_SMOKE_TEST=1 swift test --package-path Loqui --filter SystemAudioRecorderTests.testDefaultMicrophoneDeliversWarmupBuffers
```

This opens the real input and requires incoming warm-up buffers. It discards the
audio and verifies that the temporary WAV contains no recorded frames. Regression
tests also cover an 18-channel CONNECT 6 format through mono WAV capture.

The real-model test checks draft text decoded from the in-memory samples of an
open capture within the first three seconds of input, and final inference.
It uses fixture audio, not microphone access. AirPods profile negotiation and
audible cue playback still need a hardware check: select the AirPods under Input,
hold the dictation key until the ready chime, speak, check the recording
indicator's level bars and the draft, then release. Repeat immediately and check that input recovers after an
AirPods reconnect.

Run the model installer, cache, and release-source fixtures with:

```sh
bash tests/dependency-tool-fixtures.sh
```

After installing the pinned weights, exercise real final transcription and live
preview without recording the microphone or posting keystrokes:

```sh
./scripts/dependency-tool.sh install-model
LOQUI_PARAKEET_SMOKE_TEST=1 swift test --package-path Loqui --filter ParakeetIntegrationTests
```

The smoke test reports short-draft latency and always checks final and draft
transcripts, including a draft from a still-open capture. Shared CI runners have
variable load and Core ML warm-up costs, so their wall-clock latency is diagnostic.
On an otherwise idle native Apple Silicon Mac, also enforce the two-second draft
latency budget with:

```sh
LOQUI_PARAKEET_SMOKE_TEST=1 LOQUI_PARAKEET_LATENCY_TEST=1 swift test --package-path Loqui --filter ParakeetIntegrationTests
```

The integration fixture `tests/fixtures/jfk.wav` comes from
`ggml-org/whisper.cpp` at commit `9386f239401074690479731c1e41683fbbeac557`
(`samples/jfk.wav`, SHA-256 `59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e`).
It contains public speech, not a user's recording. Native CI runs real inference on
Apple Silicon and tests the unsupported-hardware preflight on Intel. Core ML
prediction with these assets crashed under Rosetta during local verification;
Loqui rejects x86_64 inference before loading any model.

Useful focused commands include:

```sh
swift test --package-path Loqui --filter LoquiCoreTests
swift test --package-path Loqui --filter LoquiParakeetTests
swift test --package-path Loqui --filter LoquiDeliveryTests
swift test --package-path Loqui --filter LoquiArchitectureTests
```

Before merging, also run the same format, lint, and changelog gates as CI:

```sh
./scripts/changelog.sh check
bash tests/changelog-tests.sh
swiftlint lint --strict --config .swiftlint.yml
swiftformat --lint --config .swiftformat Loqui/Sources Loqui/Tests
```
