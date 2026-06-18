# suzu

A small, sandboxed macOS menu-bar companion for your sound and mic.

suzu shows — at a glance — where your sound is going and where your mic is
listening, and lets you move either one in a single tap. It makes the obvious
right choice automatically when it can, asks gently when it isn't sure, and
remembers your answer so it stops asking. Every automatic change is announced in
plain language and can be undone.

## What it does

- **Right now.** A calm header that says, in plain words, where sound and mic
  are — one line when they're together, two when they're split.
- **One-tap switching.** Short lists of outputs and inputs, the current one
  checkmarked, a real icon on each row.
- **Smart Moments.** Quiet, optional help that follows one rule: ask once, honor
  the answer forever, and make the silent version always undoable.
  - *Headset arrives* → keep sound **and** mic together on it (macOS otherwise
    moves only one).
  - *Headset leaves, lid open* → offer the Mac's own speakers and mic back.
    (Stays quiet when the lid is shut and you're docked.)
- **Nothing is a dead end.** No jargon, no setting you can't undo, no screen you
  can't back out of.

The menu-bar icon mirrors where sound is going right now (a speaker, headphones,
a display), so you can read your state without even opening the menu.

## Distribution

suzu targets the **Mac App Store**: it builds sandboxed from day one and adds no
entitlement beyond the base App Sandbox. Setting the default input/output device
through CoreAudio doesn't require leaving the sandbox, and suzu never captures
audio (so it needs no microphone permission). Per-app output routing is
deliberately **out of scope** — it would require a HAL plug-in that can't ship in
a sandboxed App Store build.

## Requirements

- **Run:** macOS 26 (Tahoe) or later.
- **Build:** the Xcode 26 toolchain (Swift 6, strict concurrency) and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

Audio device access uses
[SimplyCoreAudio](https://github.com/rnine/SimplyCoreAudio) (resolved via Swift
Package Manager).

## Build

The Xcode project is generated from `project.yml`, and the version is
single-sourced in `Suzu/Version.xcconfig`.

```bash
make build   # generate the project and compile (unsigned, quick check)
make app     # build a runnable, ad-hoc-signed .app
make run     # build and launch it
make open    # generate and open the project in Xcode
```

## Project layout

```
project.yml              XcodeGen project definition
Suzu/
  SuzuApp.swift          @main App: MenuBarExtra + Settings scenes, bootstrap
  Audio/                 AudioController (the only CoreAudio caller), snapshots
  SmartMoments/          The ask/always/never engine, the Smart Moments, lid sensor
  Views/                 The popover, rows, suggestion card, settings, toast, welcome
  System/                Preferences (UserDefaults), launch-at-login
  Support/               Copy (all user-facing strings), naming, logging
  Version.xcconfig       Single source of truth for the version
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design decisions behind
the layout.
