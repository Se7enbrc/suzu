# suzu - a small, sandboxed macOS menu-bar audio companion.
#
# The Xcode project is generated from project.yml by XcodeGen, so the pbxproj
# never needs hand-editing and stays free of per-machine signing settings.
# Version is single-sourced in Suzu/Version.xcconfig.
#
#   make build           - generate the project and compile (unsigned, fast)
#   make app             - build a runnable, signed .app (Developer ID, or ad-hoc)
#   make run             - build and launch it
#   make install         - build and copy to /Applications
#   make codesign-setup  - one-time: build suzu's dedicated signing keychain
#   make codesign-teardown - remove that keychain
#   make test / lint / clean

APP_NAME := Suzu
PROJECT  := $(APP_NAME).xcodeproj
SCHEME   := $(APP_NAME)
CONFIG   ?= Release
DERIVED  := build
PRODUCTS := $(DERIVED)/Build/Products/$(CONFIG)
APP      := $(PRODUCTS)/$(APP_NAME).app

# --- Code signing -----------------------------------------------------------
# suzu keeps its OWN dedicated signing keychain, separate from the login
# keychain and from any other project's. The Developer ID key is imported with
# `-T /usr/bin/codesign` baked into its ACL, which is the only reliable way to
# get non-interactive codesign (no "codesign wants to use key" prompt). Secrets
# live in $(SUZU_CREDS) (mode 0600, OUTSIDE the repo) - never in the Makefile.
#
# suzu is sandboxed; Developer ID + hardened runtime (on via project.yml) is a
# valid posture for direct/local use. Mac App Store submission instead uses the
# Apple Distribution cert via App Store Connect.
SIGN_KEYCHAIN ?= $(HOME)/Library/Keychains/suzu-signing.keychain-db
SUZU_CREDS    ?= $(HOME)/.config/suzu/signing.env

# Developer ID auto-detected across the search list (incl. the dedicated
# keychain once set up). Empty on machines without one -> ad-hoc fallback.
DEVELOPER_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | \
                  sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
TEAM_ID      := $(shell printf '%s' '$(DEVELOPER_ID)' | sed -n 's/.*(\([A-Z0-9]\{10\}\))$$/\1/p')

.PHONY: all generate build app run install test lint open clean \
        codesign-setup codesign-teardown ensure-signing

all: app

generate:
	xcodegen generate

# Compile only, no signing - the quick "does it build" gate.
build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO build

# Signed, runnable build. Developer ID via the dedicated keychain when present,
# ad-hoc otherwise.
app: generate ensure-signing
	@if [ -n "$(DEVELOPER_ID)" ]; then \
	  echo "▶ signing: $(DEVELOPER_ID) (team $(TEAM_ID))"; \
	  xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	    -derivedDataPath $(DERIVED) \
	    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(DEVELOPER_ID)" \
	    DEVELOPMENT_TEAM="$(TEAM_ID)" \
	    OTHER_CODE_SIGN_FLAGS="--keychain $(SIGN_KEYCHAIN)" build; \
	else \
	  echo "▶ no Developer ID cert - ad-hoc signing"; \
	  xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	    -derivedDataPath $(DERIVED) \
	    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build; \
	fi

run: app
	open "$(APP)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "▶ installed to /Applications/$(APP_NAME).app"

# Unlock the dedicated keychain (no-op if it isn't set up yet) so the signed
# build stays non-interactive even after a lock/sleep.
ensure-signing:
	@if [ -f "$(SIGN_KEYCHAIN)" ] && [ -f "$(SUZU_CREDS)" ]; then \
	  KCPASS="$$(sed -n 's/^SIGN_KEYCHAIN_PASSWORD=//p' "$(SUZU_CREDS)" | head -1)"; \
	  [ -n "$$KCPASS" ] && security unlock-keychain -p "$$KCPASS" "$(SIGN_KEYCHAIN)" 2>/dev/null \
	    && echo "▶ suzu signing keychain unlocked" || true; \
	fi

# One-time: build suzu's dedicated signing keychain from a Developer ID .p12.
# Preferred (keeps the password out of shell history / ps): put these lines in
# $(SUZU_CREDS) first, then run `make codesign-setup`:
#     P12_PATH=/path/to/DeveloperID.p12
#     P12_PASSWORD=...
# Env also works: P12_PATH=... P12_PASSWORD='...' make codesign-setup
# The keychain password is generated and stored in $(SUZU_CREDS) so signing can
# re-unlock non-interactively from any session.
codesign-setup:
	@set -eu; \
	mkdir -p "$$(dirname "$(SUZU_CREDS)")"; \
	P12="$${P12_PATH:-$$(sed -n 's/^P12_PATH=//p' "$(SUZU_CREDS)" 2>/dev/null | head -1)}"; \
	test -n "$$P12" && test -s "$$P12" || { echo "ERR: P12_PATH missing/empty - export the Developer ID cert+key as a .p12 first" >&2; exit 1; }; \
	P12PW="$${P12_PASSWORD:-$$(sed -n 's/^P12_PASSWORD=//p' "$(SUZU_CREDS)" 2>/dev/null | head -1)}"; \
	test -n "$$P12PW" || { echo "ERR: P12_PASSWORD not set (env or $(SUZU_CREDS))" >&2; exit 1; }; \
	KCPASS="$$(sed -n 's/^SIGN_KEYCHAIN_PASSWORD=//p' "$(SUZU_CREDS)" 2>/dev/null | head -1)"; \
	if [ -z "$$KCPASS" ]; then \
	  KCPASS="$$(/usr/bin/openssl rand -base64 24)"; \
	  umask 177; printf 'SIGN_KEYCHAIN_PASSWORD=%s\n' "$$KCPASS" >> "$(SUZU_CREDS)"; chmod 600 "$(SUZU_CREDS)"; \
	  echo "  ✓ generated keychain password → $(SUZU_CREDS)"; \
	fi; \
	[ -f "$(SIGN_KEYCHAIN)" ] || { security create-keychain -p "$$KCPASS" "$(SIGN_KEYCHAIN)"; echo "  ✓ created $(notdir $(SIGN_KEYCHAIN))"; }; \
	security set-keychain-settings -lut 3600 "$(SIGN_KEYCHAIN)"; \
	security unlock-keychain -p "$$KCPASS" "$(SIGN_KEYCHAIN)"; \
	if ! security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q "Developer ID"; then \
	  security import "$$P12" -k "$(SIGN_KEYCHAIN)" -P "$$P12PW" -T /usr/bin/codesign; \
	  echo "  ✓ imported Developer ID"; \
	else echo "  • Developer ID already present"; fi; \
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$$KCPASS" "$(SIGN_KEYCHAIN)" >/dev/null; \
	security list-keychains -d user -s "$(SIGN_KEYCHAIN)" $$(security list-keychains -d user | sed 's/[" ]//g' | grep -v suzu-signing); \
	echo "  ✓ suzu signing keychain ready (codesign authorized, non-interactive)"; \
	security find-identity -v -p codesigning "$(SIGN_KEYCHAIN)" | grep "Developer ID" || true

# Remove the dedicated signing keychain (drops it from the search list too).
codesign-teardown:
	@security list-keychains -d user -s \
	  $$(security list-keychains -d user | sed 's/[" ]//g' | grep -v suzu-signing) 2>/dev/null || true
	@security delete-keychain "$(SIGN_KEYCHAIN)" 2>/dev/null && echo "▶ removed $(notdir $(SIGN_KEYCHAIN))" || true

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' \
	  -derivedDataPath $(DERIVED) test

lint:
	swiftlint

open: generate
	open $(PROJECT)

clean:
	rm -rf $(DERIVED) $(PROJECT)
