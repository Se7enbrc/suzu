# suzu - a small, sandboxed macOS menu-bar audio companion.
#
# The Xcode project is generated from project.yml by XcodeGen, so the pbxproj
# never needs hand-editing and stays free of per-machine signing settings.
# Version is single-sourced in Suzu/Version.xcconfig.
#
# DAY TO DAY:
#   make build           Compile-only check (unsigned, fast).
#   make app             Build a signed, runnable .app (Developer ID, or adhoc).
#   make run             Build + launch it.
#   make install         Build + copy to /Applications.
#   make test / lint / clean
#
# RELEASE (Developer ID + notarized, auto-updates via Sparkle):
#   make release-publish THE release: dist -> ZIP + EdDSA-sign -> GitHub release
#                        + appcast; existing installs auto-update.
#   make dist            Build-only checkpoint: Release -> sign -> notarize ->
#                        staple -> DMG (no publish).
#
# ONE-TIME SETUP (suzu's OWN signing kit - shares nothing but the .p12):
#   make creds-init      Write the signing credentials file template.
#   make codesign-setup  Build suzu's dedicated signing keychain + import .p12.
#   make setup-notary    Store the notarytool profile (in suzu's keychain).
#   make sparkle-keys    Mint the Sparkle EdDSA update-signing keypair.
#   make codesign-teardown  Remove suzu's signing keychain.

APP_NAME := Suzu
PROJECT  := $(APP_NAME).xcodeproj
SCHEME   := $(APP_NAME)
CONFIG   ?= Release
DERIVED  := build
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)
APP      := $(PRODUCTS)/$(APP_NAME).app
ENT      := Suzu/Suzu.entitlements

# --- Code signing / notarization (suzu's OWN, isolated kit) ------------------
# Everything here is namespaced to suzu and references nothing from another
# project. The ONLY shared input is the Developer ID .p12 (there is just one such
# Apple cert), imported into suzu's OWN keychain below. Two rules keep suzu's kit
# from ever colliding with another project's signing kit on the same Mac:
#   1. codesign / notarytool are ALWAYS pinned to suzu's keychain via --keychain.
#   2. suzu NEVER mutates the global keychain search list (it even removes itself
#      from it). That search-list reordering is exactly how two kits end up
#      shadowing each other's identically-named identity - so we don't play.
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/suzu-signing.keychain-db
# Developer ID detected from suzu's OWN keychain only - never the global search
# list - so the build is deterministic about which cert/keychain it uses. Empty
# until `make codesign-setup` runs -> builds fall back to adhoc (local dev still
# works). Cert metadata is readable even while the keychain is locked.
DEVELOPER_ID ?= $(shell security find-identity -v -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | \
                  sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
TEAM_ID      := $(shell printf '%s' '$(DEVELOPER_ID)' | sed -n 's/.*(\([A-Z0-9]\{10\}\))$$/\1/p')
# notarytool keychain profile name (stored in suzu's keychain by setup-notary).
NOTARY_PROFILE ?= suzu-notary
# Signing credentials file - the ONE secret store the release pipeline reads.
# Plain KEY=value, mode 0600, OUTSIDE the repo; scripts/signing-creds.sh is the
# sole reader/writer. Override with `make dist SIGNING_CREDS=/path` (or the
# SUZU_SIGNING_CREDS env var).
SIGNING_CREDS ?= $(HOME)/.config/suzu/signing.env
export SUZU_SIGNING_CREDS := $(SIGNING_CREDS)
CREDS         := scripts/signing-creds.sh

# Version single source of truth: Suzu/Version.xcconfig (NOT pbxproj).
MARKETING_VERSION := $(shell sed -n 's/^MARKETING_VERSION = \(.*\)/\1/p' Suzu/Version.xcconfig | tr -d ' ')
BUILD_NUMBER      := $(shell sed -n 's/^CURRENT_PROJECT_VERSION = \(.*\)/\1/p' Suzu/Version.xcconfig | tr -d ' ')
DMG_NAME          := Suzu-$(MARKETING_VERSION).dmg
DIST_DIR          := $(DERIVED)/dist
# Repo that hosts the Sparkle appcast (GitHub Pages) + release assets.
RELEASES_REPO     ?= Se7enbrc/suzu
SPARKLE_VERSION   ?= 2.9.3
export SPARKLE_VERSION
# Dedicated Sparkle keychain account so suzu's update-signing key is its OWN,
# never the shared default key another app on this Mac might already use.
SPARKLE_ACCOUNT   ?= suzu

.PHONY: all generate build app run install test lint open clean distclean \
        sign ensure-signing codesign-setup codesign-teardown \
        creds-init setup-notary sparkle-keys preflight notarize dmg dist \
        release-publish archive export-appstore

all: app

generate:
	xcodegen generate

# Compile + embed, adhoc-signed - the quick "does it build" gate, and the
# bundle the `sign` step re-seals. Signing must be ALLOWED (adhoc is enough):
# with CODE_SIGNING_ALLOWED=NO, Xcode skips processing Sparkle's binary
# xcframework, so it neither embeds nor becomes importable. The real Developer
# ID seal (+ hardened runtime + timestamp) is applied by `sign`.
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) \
	  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build

# Inside-out sign the freshly-built bundle (Developer ID via suzu's dedicated
# keychain, adhoc fallback without a cert). A sandboxed app must be signed even
# for a local run, or it won't get its container/entitlements.
sign: build ensure-signing
	@if [ -n "$(strip $(DEVELOPER_ID))" ]; then \
	  echo "▶ signing inside-out: $(DEVELOPER_ID) (team $(TEAM_ID))"; \
	  scripts/sign-bundle.sh "$(APP)" "$(DEVELOPER_ID)" "$(SIGN_KEYCHAIN)" "$(ENT)"; \
	else \
	  echo "▶ no Developer ID in suzu's keychain - adhoc signing (run 'make codesign-setup' for a real cert)"; \
	  scripts/sign-bundle.sh "$(APP)" "-" "" "$(ENT)"; \
	fi

# `make app` = a signed, runnable bundle.
app: sign

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "▶ installed to /Applications/$(APP_NAME).app"

# Unlock + authorize suzu's keychain for non-interactive signing. NEVER touches
# the global keychain search list, so it can't disturb (or be disturbed by) any
# other project's signing kit. No-op without a Developer ID / keychain yet.
ensure-signing:
	@test -n "$(strip $(DEVELOPER_ID))" || exit 0; \
	test -f "$(SIGN_KEYCHAIN)" || exit 0; \
	KCPW=$$($(CREDS) get SIGN_KEYCHAIN_PASSWORD --optional 2>/dev/null || true); \
	if [ -n "$$KCPW" ]; then \
	  security unlock-keychain -p "$$KCPW" "$(SIGN_KEYCHAIN)" 2>/dev/null || true; \
	  if ! security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q "Developer ID"; then \
	    P12="$$($(CREDS) get P12_PATH --optional 2>/dev/null || true)"; \
	    P12PW="$$($(CREDS) get P12_PASSWORD --optional 2>/dev/null || true)"; \
	    if [ -s "$$P12" ] && [ -n "$$P12PW" ]; then \
	      security import "$$P12" -k "$(SIGN_KEYCHAIN)" -P "$$P12PW" -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || true; \
	      echo "  ↺ re-imported Developer ID into suzu's keychain (auto-heal)"; \
	    fi; \
	  fi; \
	  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$$KCPW" "$(SIGN_KEYCHAIN)" >/dev/null 2>&1 || true; \
	  echo "  ✓ suzu signing keychain unlocked + authorized (search list untouched)"; \
	fi

# One-time: write the signing credentials template (mode 0600, outside the repo).
creds-init:
	@$(CREDS) init

# One-time: build suzu's DEDICATED signing keychain, importing the Developer ID
# from the .p12 with `-T /usr/bin/codesign` baked into its ACL (the only reliable
# way to get non-interactive codesign). Non-destructive: a separate keychain,
# never the login keychain. The .p12 path + passphrase + keychain password come
# from the credentials file. Finishes by REMOVING suzu's keychain from the global
# search list so it can never shadow another project's cert (codesign reaches it
# via --keychain). Idempotent.
codesign-setup:
	@echo "▶ Building suzu's dedicated signing keychain $(SIGN_KEYCHAIN)..."
	@set -eu; \
	$(CREDS) check >/dev/null; \
	P12="$$($(CREDS) get P12_PATH)"; \
	test -s "$$P12" || { echo "ERR: P12_PATH '$$P12' missing or empty - export the Developer ID cert+key as .p12 first" >&2; exit 1; }; \
	P12PW="$$($(CREDS) get P12_PASSWORD)"; \
	KCPASS="$$($(CREDS) get SIGN_KEYCHAIN_PASSWORD --optional)"; \
	if [ -z "$$KCPASS" ]; then \
	  KCPASS="$$(/usr/bin/openssl rand -base64 24)"; \
	  $(CREDS) set SIGN_KEYCHAIN_PASSWORD "$$KCPASS"; \
	  echo "  ✓ generated keychain password → $$($(CREDS) path)"; \
	fi; \
	if [ ! -f "$(SIGN_KEYCHAIN)" ]; then \
	  security create-keychain -p "$$KCPASS" "$(SIGN_KEYCHAIN)"; \
	  echo "  ✓ created keychain"; \
	else \
	  echo "  • keychain exists - updating in place (preserves the notary profile)"; \
	fi; \
	security set-keychain-settings "$(SIGN_KEYCHAIN)"; \
	security unlock-keychain -p "$$KCPASS" "$(SIGN_KEYCHAIN)"; \
	if ! security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q "Developer ID"; then \
	  security import "$$P12" -k "$(SIGN_KEYCHAIN)" -P "$$P12PW" -T /usr/bin/codesign -T /usr/bin/security; \
	  echo "  ✓ imported Developer ID"; \
	else \
	  echo "  • Developer ID already present - left as is"; \
	fi; \
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$$KCPASS" "$(SIGN_KEYCHAIN)" >/dev/null; \
	others="$$(security list-keychains -d user | sed 's/[" ]//g' | grep -vF "$(SIGN_KEYCHAIN)" || true)"; \
	security list-keychains -d user -s $$others >/dev/null 2>&1 || true; \
	echo "  ✓ suzu signing keychain ready (authorized, non-interactive, isolated from the search list)"
	@security find-identity -v -p codesigning "$(SIGN_KEYCHAIN)" | grep "Developer ID" || true

# Remove suzu's dedicated signing keychain. It isn't in the search list, so this
# just deletes the file (and drops it from the list if it somehow is).
codesign-teardown:
	@echo "▶ Removing $(SIGN_KEYCHAIN)..."
	@security delete-keychain "$(SIGN_KEYCHAIN)" 2>/dev/null || true
	@echo "  ✓ removed"

# One-time: store the Apple ID app-specific password as a notarytool profile IN
# SUZU'S KEYCHAIN (--keychain), not the login keychain (which is locked in
# SSH/cron sessions). Reads APPLE_ID / APPLE_APP_PASSWORD (+ optional
# APPLE_TEAM_ID) from the creds file. Re-run only if the password rotates.
setup-notary:
	@echo "▶ Storing notary profile '$(NOTARY_PROFILE)' in suzu's signing keychain..."
	@set -eu; \
	test -f "$(SIGN_KEYCHAIN)" || { echo "ERR: no signing keychain - run 'make codesign-setup' first" >&2; exit 1; }; \
	$(CREDS) missing APPLE_ID APPLE_APP_PASSWORD SIGN_KEYCHAIN_PASSWORD \
	  || { echo "  fill those in ($$($(CREDS) path)), then re-run - 'make dist' runs this automatically" >&2; exit 1; }; \
	APPLE_ID="$$($(CREDS) get APPLE_ID)"; \
	APP_PW="$$($(CREDS) get APPLE_APP_PASSWORD)"; \
	TEAM="$$($(CREDS) get APPLE_TEAM_ID --optional)"; \
	[ -n "$$TEAM" ] || TEAM='$(TEAM_ID)'; \
	[ -n "$$TEAM" ] || { echo "ERR: no team id - set APPLE_TEAM_ID in the creds file" >&2; exit 1; }; \
	KCPW="$$($(CREDS) get SIGN_KEYCHAIN_PASSWORD)"; \
	security unlock-keychain -p "$$KCPW" "$(SIGN_KEYCHAIN)"; \
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
	  --apple-id "$$APPLE_ID" --team-id "$$TEAM" --password "$$APP_PW" \
	  --keychain "$(SIGN_KEYCHAIN)"; \
	echo "  ✓ notary profile stored in suzu's keychain (readable from any session)"

# One-time: mint the EdDSA (ed25519) update-signing keypair. Generated under a
# DEDICATED keychain account ($(SPARKLE_ACCOUNT)) so suzu has its OWN update key,
# never the shared default one another app on this Mac may already use - one
# signing kit must not borrow another's root of trust. The PRIVATE key is also
# stored in the creds file (SPARKLE_ED_PRIVATE_KEY) so publishing is prompt-free;
# the PUBLIC key is printed for Info.plist's SUPublicEDKey. Idempotent. BACK UP
# the private key: losing it strands every client at the last signed build; a
# leak lets anyone sign an update suzu will install.
sparkle-keys:
	@set -eu; \
	TOOLS="$$(scripts/sparkle-tools.sh)"; \
	if $(CREDS) get SPARKLE_ED_PRIVATE_KEY --optional 2>/dev/null | grep -q .; then \
	  echo "  • SPARKLE_ED_PRIVATE_KEY already in $$($(CREDS) path)"; \
	else \
	  TMP="$$(mktemp)"; rm -f "$$TMP"; trap 'rm -f "$$TMP"' EXIT; \
	  "$$TOOLS/generate_keys" --account $(SPARKLE_ACCOUNT) >/dev/null 2>&1 || true; \
	  "$$TOOLS/generate_keys" --account $(SPARKLE_ACCOUNT) -x "$$TMP" >/dev/null 2>&1; \
	  $(CREDS) set SPARKLE_ED_PRIVATE_KEY "$$(cat "$$TMP")"; \
	  echo "  ✓ private key (account '$(SPARKLE_ACCOUNT)') stored in $$($(CREDS) path) - BACK IT UP"; \
	fi; \
	echo "  SUPublicEDKey for Suzu/Info.plist:"; \
	"$$TOOLS/generate_keys" --account $(SPARKLE_ACCOUNT) -p

# Fail-fast gate for `make dist`: verify every non-interactive ingredient BEFORE
# the long Release build. Self-bootstrapping: first run writes the creds
# template and stores the notary profile automatically once the file is filled.
preflight:
	@set -eu; \
	echo "▶ Preflight (release signing)..."; \
	test -n "$(strip $(DEVELOPER_ID))" || { echo "ERR: no Developer ID in suzu's keychain - run 'make codesign-setup'" >&2; exit 1; }; \
	echo "  ✓ identity: $(DEVELOPER_ID)"; \
	if ! $(CREDS) check >/dev/null 2>&1; then \
	  $(CREDS) init >/dev/null; \
	  echo "ERR: first run - signing credentials needed." >&2; \
	  echo "  A template was just written to: $$($(CREDS) path)" >&2; \
	  echo "  Fill in APPLE_ID + APPLE_APP_PASSWORD, then re-run 'make dist'." >&2; \
	  exit 1; \
	fi; \
	echo "  ✓ creds file: $$($(CREDS) path)"; \
	if ! $(CREDS) missing APPLE_ID APPLE_APP_PASSWORD 2>/dev/null; then \
	  $(CREDS) fill-from-op 2>/dev/null || true; \
	  $(CREDS) missing APPLE_ID APPLE_APP_PASSWORD \
	    || { echo "  fill those in (or set OP_SOURCE), then re-run 'make dist'" >&2; exit 1; }; \
	fi; \
	if ! security dump-keychain "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q notary; then \
	  echo "  ▶ no notary profile yet - storing it now (automatic setup-notary)..."; \
	  $(MAKE) --no-print-directory setup-notary; \
	fi; \
	if ! $(CREDS) get SPARKLE_ED_PRIVATE_KEY --optional | grep -q .; then \
	  echo "ERR: no Sparkle update-signing key - run 'make sparkle-keys' once (and set SUPublicEDKey in Info.plist)" >&2; \
	  exit 1; \
	fi; \
	echo "  ✓ notary profile + Sparkle key present"

# Notarize the signed bundle: zip -> submit (waits) -> staple -> verify. The app
# is already Developer-ID signed with hardened runtime + secure timestamp by the
# `sign` step. notarytool reads suzu's profile from suzu's keychain (--keychain).
notarize: app
	@test -n "$(strip $(DEVELOPER_ID))" || { echo "ERR: no Developer ID cert - can't notarize" >&2; exit 1; }
	@echo "▶ Notarizing $(APP)..."
	@rm -f "$(DERIVED)/Suzu-notarize.zip"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(DERIVED)/Suzu-notarize.zip"
	xcrun notarytool submit "$(DERIVED)/Suzu-notarize.zip" \
	  --keychain-profile "$(NOTARY_PROFILE)" --keychain "$(SIGN_KEYCHAIN)" --wait
	xcrun stapler staple "$(APP)"
	@rm -f "$(DERIVED)/Suzu-notarize.zip"
	@echo "  ✓ notarized + stapled"
	@spctl --assess --type execute --verbose=2 "$(APP)" || true

# Build a distributable DMG from the signed (and stapled) bundle.
dmg:
	@test -d "$(APP)" || { echo "ERR: build first (make app)" >&2; exit 1; }
	@echo "▶ Building $(DMG_NAME)..."
	@rm -rf "$(DIST_DIR)" && mkdir -p "$(DIST_DIR)/stage"
	cp -R "$(APP)" "$(DIST_DIR)/stage/"
	ln -s /Applications "$(DIST_DIR)/stage/Applications"
	hdiutil create -volname "suzu $(MARKETING_VERSION)" \
	  -srcfolder "$(DIST_DIR)/stage" -ov -format UDZO "$(DIST_DIR)/$(DMG_NAME)"
	@rm -rf "$(DIST_DIR)/stage"
	@echo "  ✓ $(DIST_DIR)/$(DMG_NAME)"
	@shasum -a 256 "$(DIST_DIR)/$(DMG_NAME)"

# Full distribution pipeline: preflight (fail fast) -> clean Release -> sign ->
# notarize + staple -> DMG. Non-interactive from any session once the one-time
# setup is done. (`notarize` pulls in `app`, so the build happens once.)
dist:
	$(MAKE) CONFIG=Release preflight clean notarize dmg

# THE release: build + notarize (via dist), then publish a Sparkle update - ZIP
# the notarized bundle, EdDSA-sign it, upload ZIP + DMG to the GitHub release,
# and update the Pages-hosted appcast.xml. Bump Suzu/Version.xcconfig + commit
# FIRST: the appcast version comes from HEAD.
release-publish: dist
	@scripts/publish-release.sh \
	  "$(MARKETING_VERSION)" "$(BUILD_NUMBER)" \
	  "$(APP)" "$(DIST_DIR)" "$(RELEASES_REPO)"

# Hostless unit tests. Adhoc-signed (signing allowed) so the Sparkle xcframework
# the Suzu module links is embedded into the test bundle and loads at runtime.
test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(DERIVED) \
	  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES test

lint:
	swiftlint

open: generate
	open $(PROJECT)

# Mac App Store (dormant scaffolding - the active channel is Developer ID +
# Sparkle above). NOTE: a real MAS build must use an entitlements file WITHOUT
# Sparkle's temporary-exception mach-lookup + network.client and WITHOUT the
# Sparkle package - the App Store rejects temporary-exception entitlements and
# delivers its own updates. See docs/appstore.md.
archive: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -archivePath $(DERIVED)/$(APP_NAME).xcarchive archive

export-appstore: archive
	xcodebuild -exportArchive -archivePath $(DERIVED)/$(APP_NAME).xcarchive \
	  -exportOptionsPlist build-support/ExportOptions-AppStore.plist \
	  -exportPath $(DERIVED)/appstore

# Keep the generated project (and its tracked Package.resolved); just drop build
# output. `make distclean` also removes the generated project.
clean:
	rm -rf $(DERIVED)

distclean: clean
	rm -rf $(PROJECT)
