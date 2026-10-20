# Changelog

Every change merged into `main` raises the version in [`VERSION`](VERSION) and
adds a section here describing it, newest first. Versions follow
[Semantic Versioning](https://semver.org): a **major** bump for changes that
break existing setups or drop support, a **minor** bump for new features, and a
**patch** bump for fixes and behind-the-scenes work. See
[docs/RELEASING.md](docs/RELEASING.md#versions-and-the-changelog) for the
workflow.

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
