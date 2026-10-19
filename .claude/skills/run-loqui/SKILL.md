---
name: run-loqui
description: Build, run, and drive the Loqui macOS menu bar dictation app. Use when asked to run, start, launch, build, bundle, quit, screenshot, or check the logs of Loqui, to smoke-test transcription with the real Parakeet model, or to run its tests.
---

Loqui is a macOS menu bar app with a Dock icon and no windows. It records while
right Option is held and types the Parakeet transcription at the cursor.
Drive it with `.claude/skills/run-loqui/driver.sh`. All paths are relative to
the repo root. macOS on Apple Silicon only. Verified on macOS 26 with Swift 6.3.3.

## Prerequisites

- Xcode or Command Line Tools with Swift 6.x (`swift --version`).
- An "Apple Development" signing identity in the keychain (optional but
  strongly recommended, see Gotchas). The driver finds it on its own.
- About 1.2 GB of disk for the model under `models/`.

`bun` is NOT required. The README's `bun loqui` path is replaced by the driver.

## Build

```bash
.claude/skills/run-loqui/driver.sh build
```

Installs and verifies the pinned model if it is missing, then runs
`./bundle.sh`, signed with your Apple Development identity. Produces
`Loqui.app` at the repo root. A cold build takes about 5 minutes. A cached
rebuild takes about 10 seconds.

## Run (agent path)

```bash
D=.claude/skills/run-loqui/driver.sh
$D launch        # quits any running copy, launches, waits for hotkey + model
$D status        # pid, memory, CPU, menu bar icon window and position
$D ss mytag      # screenshots into $TMPDIR/loqui-driver/, paths printed
open -a "$PWD/Loqui.app"   # while running: opens the Settings window (Dock reopen)
$D logs 10       # last 10 minutes of the app's unified log
$D quit
```

A healthy `launch` prints:

```
pid 93757
menu bar icon: window 54332 exists but is OFF-SCREEN (menu bar full / hidden behind the notch)
waiting for model (up to 90s)...
hotkey: rightOption monitor registered
model: Parakeet TDT 0.6B v2 ready
```

`ss` writes `<tag>-full.png` (whole screen) and `<tag>-icon.png` (the
status icon itself, captured by window ID). It adds `<tag>-menubar.png` only
when the icon is actually visible. **Read the icon PNG.** Idle shows three
sound bars and a text cursor. Recording shows taller bars and a dot. While
the icon sits under the notch, macOS tints it white, so view the PNG on a
dark background.

What happened during real use shows up in `logs`. A successful dictation logs
this sequence: `Recording started with verified input`, `Recording finished;
... peak`, `Transcription succeeded; characters: N`, `Delivery completed`.

## Transcription without a microphone

```bash
.claude/skills/run-loqui/driver.sh transcribe
```

Runs the opt-in `ParakeetIntegrationTests` against `tests/fixtures/jfk.wav`
with the real model. It covers model load, final transcription, and the
`CapturedAudioSink` live-draft snapshot path. Use it for any change under
`Loqui/Sources/Loqui/` that touches audio or transcription. It takes about 40
seconds the first time and under 1 second after that.

## Test

```bash
.claude/skills/run-loqui/driver.sh test   # 199 tests, 3 skipped by design
```

## Run (human path)

`open -a "$PWD/Loqui.app"`, then hold right Option, wait for the two-note
chime, speak, and release. The first use prompts for Microphone and
Accessibility access.

## Gotchas

- **The icon is probably hidden behind the notch.** On a full MacBook menu
  bar, macOS 26 places new status items under the camera notch (x of about
  700 on a 14-inch screen). The app still works. `launch` reports
  `OFF-SCREEN`, and `ss` still captures the icon by window ID.
- **Do not trust a waveform icon you see in the menu bar.** Other menu bar
  apps use similar bars icons. Identify Loqui's item with `status`.
- **On macOS 26, Control Center owns every menu bar item window.** Matching
  windows by owner finds nothing. The driver diffs window IDs before and
  after launch. Item titles are generic, such as `Item-0`.
- **`menu` (clicking the icon) needs Accessibility for the terminal app.**
  Without it, System Events fails with error -1719. The driver also refuses
  to click while the icon is hidden. This path is unverified.
- **The team ID is not the code in the certificate name.** In
  `Apple Development: Name (SJ564RQ354)` the parenthesised code is the
  person's ID. `bundle.sh` checks the team, which is the certificate's `OU`.
  A wrong value fails with `signature TeamIdentifier does not match` after
  the whole build.
- **Ad-hoc signing resets permission grants on every build.** Without an
  Apple Development identity, macOS re-prompts for Microphone and
  Accessibility after each rebuild.
- **The first model load after a build takes about 40 seconds.** Core ML
  recompiles its cache for the new bundle. `launch` waits up to 90 seconds,
  and you can override that with `LOQUI_MODEL_WAIT`.
- **`log` is a zsh builtin.** Use `/usr/bin/log`, as the driver does.
- **`transcribe` prints an E5RT error.** The line `E5RT encountered an STL
  exception ... zero shape error` is Core ML noise. The test still passes.
- **Quit uses `NSRunningApplication.terminate` through JXA**, the same as
  `scripts/macos-app-lifecycle.ts`. That avoids the Automation consent
  prompt that `osascript 'quit app'` can trigger.

## Troubleshooting

- **`bundle.sh` fails with `mutation of captured var 'suppliedBuffer' in
  concurrently-executing code`.** Swift 6.3 is stricter than upstream's
  Xcode 16.4 pin. Fixed in `CapturedAudioSink.swift` by PR #1.
- **`bundle.sh` fails with `xattr: [Errno 13] Permission denied ...
  FluidAudio_FluidAudio.bundle/...`.** SwiftPM emitted read-only resources.
  Fixed in `bundle.sh` by PR #1, which runs `chmod -R u+w` on copied bundles.
- **`launch` prints `model: NOT ready`.** Run `driver.sh logs`. A
  `Dependency preflight failed; category: ...` line names the cause.
  Otherwise the model is still compiling, so raise `LOQUI_MODEL_WAIT`.
