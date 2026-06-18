# Architecture

suzu is intentionally small. Phase 1 is device switching plus Smart Moments,
shipped as a sandboxed Mac App Store candidate. This note records the decisions
that shape the code.

## Distribution lane: sandboxed, no driver

Per-app output routing on macOS requires a CoreAudio HAL plug-in / audio-server
extension, which cannot ship inside a sandboxed App Store app. Rather than
straddle, suzu commits to the sandboxed lane: the core experience (switching the
default output/input and Smart Moments) needs nothing beyond the base App
Sandbox. Per-app routing is out of scope, not deferred.

Entitlements are therefore just `com.apple.security.app-sandbox`. Notably:

- Setting the default device through CoreAudio works inside the sandbox.
- suzu never captures audio, so it needs no microphone entitlement/permission.
- Launch-at-login uses `SMAppService.mainApp`, which is sandbox-safe.

## Layers

```
Views  ─────────────▶ SmartMomentsEngine ─────▶ AudioController ─▶ CoreAudio
  │                          │                        │            (SimplyCoreAudio)
  └────────────▶ Preferences ┘                        │
                 (UserDefaults)                        └─▶ DeviceSnapshot (value type)
```

- **AudioController** (`@MainActor @Observable`) is the only thing that touches
  CoreAudio. It keeps a live, value-typed picture (`DeviceSnapshot`) of outputs,
  inputs, and which are current, refreshing on `deviceListChanged` /
  `defaultOutput/InputDeviceChanged`. The live `AudioDevice` reference type never
  leaves it — everything above works with `Sendable` snapshots. It only ever
  sets the main output and main input, never the system-sounds output.

- **SmartMomentsEngine** (`@MainActor @Observable`) receives a `WorldChange`
  (devices added/removed) after each refresh and applies one pattern per moment:
  *ask* (a dismissible card) → *always* (act silently, with an undo toast) →
  *never*. It remembers the answer in `Preferences` and self-disables a moment
  after three explicit declines.

- **Preferences** (`@MainActor @Observable`) is UserDefaults-backed in the house
  style (persist from `didSet`). The visible toggles are observed stored
  properties; per-moment policy and decline counts are read/written on demand.

- **Views** are the content layer. Liquid Glass is used only on the functional
  layer — the suggestion card, the suggestion's buttons, and the floating undo
  toast — never on device names or status text, and never glass-on-glass.

## Concurrency

Swift 6 strict concurrency (`complete`). Everything user-facing is MainActor
isolated. CoreAudio posts its notifications off the main thread; the observer
block does nothing but hop back onto the main actor before touching state.

## Undo

Every automatic switch captures the previous `Route` (output id + input id)
before acting and hands it to the toast's Undo action, so any silent change is
reversible in one tap. Manual selections from the menu don't toast — the moved
checkmark is the confirmation.

## Lid (clamshell) detection

The "offer the speakers back" moment must not fire while docked with the lid
shut. `LidSensor` reads `IOPMrootDomain`'s `AppleClamshellState` (works inside
the sandbox, no entitlement). It returns `nil` when it can't tell (desktop Mac,
property absent); callers treat unknown as "don't block the offer".
