# Mac App Store submission notes

The code is sandboxed and MAS-ready. This captures the *process/asset* steps that
aren't in the repo, so a submission is reproducible.

## Signing & upload

- Day-to-day builds are Developer ID (`make app`). The store wants a different
  identity: **Apple Distribution** + an **App Store provisioning profile** for
  `io.ugfugl.suzu`, both fetched automatically once the Apple ID is in Xcode's
  accounts.
- `make archive` → `make export-appstore` produces `build/appstore/Suzu.pkg`
  using `build-support/ExportOptions-AppStore.plist`.
- Upload the `.pkg` with Transporter (or `xcrun altool --upload-package`).

## Versioning (avoid a same-day collision)

`CFBundleVersion` is a `YYYYMMDD` stamp (`Suzu/Version.xcconfig`). App Store
Connect rejects a re-upload that reuses a build number, so two uploads on the
same day collide. Before any new upload, bump `CURRENT_PROJECT_VERSION` to a
monotonic value (e.g. append a `.N` counter or switch to a CI build number), and
bump `MARKETING_VERSION` before any new ASC version record.

## App Privacy nutrition label (must match PrivacyInfo.xcprivacy)

Answer in App Store Connect:

- **Data Collection:** *Data Not Collected.*
- No tracking, no third-party SDKs, no analytics.
- The only required-reason API is **UserDefaults** (reason `CA92.1`), already
  declared in `Suzu/PrivacyInfo.xcprivacy`.

## App Review note (Guideline 2.4.5 / system audio)

> suzu sets the user's **default** audio input/output device through the public
> CoreAudio HAL — the same mechanism as System Settings > Sound. It never
> captures audio (no microphone entitlement), never touches the system-sounds
> output, and every automatic switch shows a one-tap Undo. No private API is
> used. Per-app routing is intentionally not implemented (it would require a
> non-sandboxable HAL plug-in).

## Listing assets (to author)

- Name, subtitle, promotional text, keywords, support URL, marketing URL.
- Screenshots at 1280×800 (or 1440×900 / 2560×1600): the menu popover, a Smart
  Moment card, the undo toast, Settings.
- Category: Utilities. Age rating: 4+.
