# suzu

A small, sandboxed macOS menu-bar companion for your sound and mic.

suzu shows where your sound is going and where your mic is listening, and lets
you move either one in a single tap. When the right choice is obvious it makes
it; when it isn't, it asks once and remembers the answer. Every automatic change
is announced in plain language and can be undone.

## What it does

- **Right now.** A calm header naming where sound and mic are: one line when
  they're together, two when they're split.
- **One-tap switching.** Short lists of outputs and inputs, the current one
  checkmarked, a real icon on each row.
- **Smart Moments.** Quiet, optional help with one rule: ask once, honor the
  answer, and keep the silent version undoable.
  - *Headset arrives* → keep sound **and** mic on it together (macOS otherwise
    moves only one).
  - *A device leaves* → land on something you know: a device you've chosen
    before that's still connected, or your Mac's own speakers and mic when
    you're using it directly.
  - *A favorite returns* → restore the device you last chose.

The menu-bar icon mirrors where sound is going right now, so you can read your
state without opening the menu.

## Updates

suzu is signed with a Developer ID, notarized, and updates itself through
[Sparkle](https://sparkle-project.org). It stays sandboxed and adds nothing
beyond what auto-update needs, so a Mac App Store build (which delivers its own
updates) remains possible. Setting the default device through CoreAudio needs no
special permission, and suzu never captures audio. See
[docs/RELEASE.md](docs/RELEASE.md) for how a release is cut.

## Requirements

- **Run:** macOS 26 (Tahoe) or later.
- **Build:** the Xcode 26 toolchain (Swift 6, strict concurrency) and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

Audio access uses [SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio),
resolved via Swift Package Manager.

## Build

The Xcode project is generated from `project.yml`; the version is single-sourced
in `Suzu/Version.xcconfig`.

```bash
make build   # generate the project and compile (quick check)
make app     # build a runnable, signed .app
make run     # build and launch it
make test    # run the unit tests
```

## Project layout

```
project.yml              XcodeGen project definition
Suzu/
  SuzuApp.swift          @main App: MenuBarExtra + Settings, bootstrap
  Audio/                 AudioController (the only CoreAudio caller) + snapshots
  SmartMoments/          The ask/always/never engine and lid sensor
  Views/                 Popover, rows, suggestion card, settings, toast, welcome
  System/                Preferences, launch-at-login, updater
  Support/               Copy (all user-facing strings), naming, logging
  Version.xcconfig       Single source of truth for the version
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design behind the layout.
