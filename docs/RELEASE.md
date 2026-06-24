# Releasing suzu

suzu ships as a **Developer ID-signed, notarized** app that **auto-updates via
Sparkle**. Updates are published to a GitHub Release and announced through an
`appcast.xml` served by GitHub Pages.

suzu's signing kit is **fully self-contained** - its own keychain
(`suzu-signing.keychain-db`), its own credentials file (`~/.config/suzu/signing.env`),
its own notary profile (`suzu-notary`), and its own Sparkle keypair. The only
thing shared with any other project is the Developer ID `.p12` itself (there is
one such Apple certificate). The kit pins `codesign`/`notarytool` to suzu's
keychain via `--keychain` and never reorders the global keychain search list, so
it can't collide with a sibling project's signing.

## One-time setup

```sh
make creds-init          # writes ~/.config/suzu/signing.env (mode 0600)
# Fill in: P12_PATH, P12_PASSWORD, APPLE_ID, APPLE_APP_PASSWORD
#   - P12_*  : your Developer ID Application cert+key exported as .p12
#   - APPLE_*: Apple ID + an app-specific password (appleid.apple.com)
#   (or set OP_SOURCE to a 1Password item and let `make dist` fill the rest)

make codesign-setup      # build suzu's keychain, import the .p12 (non-interactive)
make setup-notary        # store the notarytool profile in suzu's keychain
make sparkle-keys        # mint the EdDSA update keypair; prints SUPublicEDKey
```

Take the `SUPublicEDKey` value printed by `make sparkle-keys` and paste it into
`Suzu/Info.plist` (replace the `__SET_BY_make_sparkle-keys__` placeholder). The
**private** key is stored in the creds file - **back it up**; it is the root of
update trust.

### GitHub side (one-time)

- The repo (`Se7enbrc/suzu`) must be **public** for Pages + release downloads.
- Enable **GitHub Pages** (Settings → Pages) serving from the default branch
  root, so `appcast.xml` is reachable at
  `https://se7enbrc.github.io/suzu/appcast.xml` (this is the `SUFeedURL`).
- `gh` must be authenticated (`gh auth status`) with rights to create releases.

## Cutting a release

1. Bump **both** lines in `Suzu/Version.xcconfig`
   (`MARKETING_VERSION` = CalVer, `CURRENT_PROJECT_VERSION` = monotonic build
   number). Commit + push.
2. Run:

   ```sh
   make release-publish
   ```

   This runs `dist` (preflight → clean Release → inside-out sign → notarize →
   staple → DMG), then ZIPs + EdDSA-signs the bundle, uploads the ZIP + DMG to
   the GitHub Release for the tag, and inserts the item into the Pages appcast.

Sparkle clients pick it up at their next daily check, or immediately via
Settings → **Check for Updates…**.

## Inspect without publishing

```sh
make dist                # build + sign + notarize + DMG, no upload
open build/dist          # the notarized .dmg
```

## Notes

- The Sparkle build carries `network.client` + a `temporary-exception`
  mach-lookup entitlement (for the sandboxed installer XPC). That is valid for
  Developer ID + notarized distribution but **not** for the Mac App Store; a MAS
  build would drop Sparkle and those entitlements (see `docs/appstore.md`).
- `appcast.xml` is committed as a seed; `make release-publish` updates the
  served copy directly via the GitHub API, so the working-tree copy can lag -
  re-pull before hand-editing.
