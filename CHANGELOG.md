# Changelog

Every change merged into `main` raises the version in [`VERSION`](VERSION) and
adds a section here describing it, newest first. Versions follow
[Semantic Versioning](https://semver.org): a **major** bump for changes that
break existing setups or drop support, a **minor** bump for new features, and a
**patch** bump for fixes and behind-the-scenes work. See
[docs/RELEASING.md](docs/RELEASING.md#versions-and-the-changelog) for the
workflow.

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
