# Changelog

Every change merged into `main` raises the version in [`VERSION`](VERSION) and
adds a section here describing it, newest first. Versions follow
[Semantic Versioning](https://semver.org): a **major** bump for changes that
break existing setups or drop support, a **minor** bump for new features, and a
**patch** bump for fixes and behind-the-scenes work. See
[docs/RELEASING.md](docs/RELEASING.md#versions-and-the-changelog) for the
workflow.

## [1.4.0] - 2026-11-04

### Added

- The recording indicator names the microphone above its bars for about two
  seconds after listening starts, so a dictation into the wrong microphone is
  caught before you speak. It shows on the first dictation after launch, when
  the input device changed since the last dictation, and after 30 minutes
  without dictating.

## [1.3.0] - 2026-11-04

### Changed

- Live drafts stream. Each draft decodes only the audio since the last one,
  instead of all the audio so far, so a long hands-free dictation no longer
  gets slower to draft as it goes. Drafts trail your voice by about 1.1 s.
- The final transcript continues the same stream, so after you release the key
  it arrives in about 30 ms instead of about 90 ms, and the wait no longer
  grows with the length of the dictation. On 20 dictation clips it was also
  more accurate (7.7% word errors instead of 8.8%), writing "March 3rd at
  2:30" and "Dr. Patel" where the whole-clip pass wrote "march third at 2.30"
  and "doctor Patel". See
  [#13](https://github.com/benniekingwood/loqui/issues/13) for the results.
- Loqui streams only the first 2 seconds of a long pause. Without that cap,
  Parakeet dropped the words after a 12-second pause, and a whole sentence
  after a 30-second one.
- The speech model's encoder is now the streaming encoder for the 1.12 s
  setting. Run `./setup.sh` again to install it; the download is about the
  same size (about 610 MB).

## [1.2.1] - 2026-11-04

### Added

- The model benchmark reports the wait after you stop speaking ("after
  release") alongside clip time. For Unified streaming, that's only the final
  flush, since the rest of the work happens while you speak.
- Two faster streaming settings to benchmark, `unified-stream-1120ms` and
  `unified-stream-320ms`, whose drafts trail speech by about 1.1 s and 0.3 s
  instead of 2.1 s. Each is an extra download of about 580 MB. See
  [#13](https://github.com/benniekingwood/loqui/issues/13) for the results.

## [1.2.0] - 2026-11-03

### Added

- Filler words such as "um", "uh", and "erm" are removed from drafts and the
  final transcript, along with the commas around them, so "we should, uh, ship
  it" becomes "we should ship it". Words that only look like fillers
  ("umbrella", "uh-huh", "ER") are kept. On by default; turn it off under
  Settings › Text.
- Spoken formatting: say "new line", "new paragraph", "open quote", or "close
  quote" to format the final transcript. The line after a break starts with a
  capital. Drafts never type line breaks. Off by default; turn it on under
  Settings › Text.

### Changed

- A dictation that was nothing but filler words now reports that no speech was
  detected instead of delivering empty text.

## [1.1.0] - 2026-11-02

### Changed

- Loqui now transcribes with Parakeet Unified English 0.6B instead of Parakeet
  TDT 0.6B v2. It writes punctuation and capitals and writes most numbers as
  digits ("port 3000", "$1,200"), and it uses about a third less memory. On 20
  dictation clips it was as accurate as v2, and its typical latency was within
  about 5 ms. See
  [#12](https://github.com/benniekingwood/loqui/issues/12) for the results.
- The model download is now about 615 MB, up from about 470 MB. Run
  `./setup.sh` again to install it. You can delete the old
  `models/parakeet-tdt-0.6b-v2-coreml` directory.
- The model is licensed under the NVIDIA Open Model License instead of CC BY
  4.0. The app bundle now includes a copy of the agreement next to the model
  notice.
- The model benchmark downloads v2 itself when it can't find a copy in
  `models/`.

## [1.0.2] - 2026-11-02

### Added

- A model benchmark for comparing speech models on your own dictation before
  Loqui switches to one. `loqui-model-bench record` walks you through
  recording prompts, and `./scripts/benchmark-models.sh` compares Parakeet v2,
  Parakeet Unified English, and Unified streaming on accuracy, latency, load
  time, and memory. It's a separate package under `benchmarks/` and isn't part
  of the app. It refuses silent recordings, which macOS produces when the
  terminal isn't allowed to use the microphone. See
  [benchmarks/README.md](benchmarks/README.md).

## [1.0.1] - 2026-10-22

### Fixed

- Dictation into Spark and other web-based editors that ignore Accessibility
  edits. Loqui now checks that its text actually appeared. Live drafts stop
  for that dictation, and the final text is pasted instead.
- A paste the app ignored is retried once as a typed ⌘V. If it still doesn't
  land, the transcript stays on the clipboard and the card says so, instead of
  the clipboard being restored over it.

### Changed

- Loqui's log records how each transcript was delivered (inserted, pasted, or
  copied, and why), without the transcript text.

## [1.0.0] - 2026-10-19

The first release of Loqui as its own project.

### Added

- Hold-to-dictate with on-device Parakeet TDT 0.6B v2 transcription. Hold the
  dictation key, wait for the ready chime, speak, and release. Double-tap the
  key for hands-free mode.
- Live drafts that appear at the cursor while you speak and are replaced by one
  final transcription when you stop.
- Text delivery into Accessibility text fields, with keystroke delivery for
  editors and GPU-rendered terminals.
- A Settings window for the dictation key (Right Option, Right Command, Right
  Control, or Fn), hands-free mode, the microphone, sound cues, and the
  recording indicator. Open it from the menu bar, with ⌘, or from the Dock.
- A floating recording indicator in Loqui's Spectrum colors that follows your
  voice level above the Dock.
- A transcript card with a Copy button when no text field has focus. Its close
  button is a countdown ring that dims until the card dismisses itself.
- The Spectrum Cursor Wave app icon and menu bar icon. Loqui shows its icon in
  the Dock while running.
- `scripts/deploy.sh` to build, sign, and install `/Applications/Loqui.app`.
- This changelog, and a CI check that every pull request raises the version.

### Changed

- Loqui is now a set of independent Swift modules (`LoquiCore`, `LoquiAudio`,
  `LoquiParakeet`, `LoquiDelivery`, `LoquiShortcuts`, `LoquiInterface`) with
  boundaries enforced by architecture tests. FluidAudio, which runs Parakeet, is
  the only third-party dependency.
- Live drafts decode the recorder's in-memory audio instead of writing a
  snapshot file for every pass, and skip passes while no new audio arrives.

### Fixed

- Release bundling on Swift 6.3 toolchains.
- The CI build on Xcode 16.4.
