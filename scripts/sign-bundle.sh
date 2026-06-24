#!/bin/bash
#
# sign-bundle.sh - inside-out codesign of Suzu.app. NO `--deep`.
#
# `--deep` is the wrong tool here: it re-signs nested code (Sparkle's framework +
# its Updater.app / Autoupdate / Installer.xpc / Downloader.xpc) with the MAIN
# app's `--entitlements`, clobbering each component's own entitlements - which is
# exactly what breaks Sparkle's sandboxed installer XPC at runtime. Apple
# deprecated `--deep` for distribution for the same reason.
#
# Instead we sign deepest-first: each Sparkle component re-signed with OUR
# Developer ID but PRESERVING its own entitlements/identifier, then the app last
# with Suzu's entitlements (sandbox + network.client + the installer-launcher
# mach-lookup exception). suzu has no other embedded code (no Homebrew dylibs,
# no helper daemon), so this is the whole story.
#
# Identity resolution is pinned to suzu's OWN keychain via --keychain so this
# never reaches into another project's signing kit, and never depends on the
# global keychain search-list order.
#
# Args:
#   $1  app path (Suzu.app)
#   $2  signing identity ('-' for adhoc)
#   $3  keychain to pin identity resolution to (optional)
#   $4  the app's entitlements file (Suzu/Suzu.entitlements)
set -euo pipefail

APP="${1:?usage: sign-bundle.sh <app> <identity> [keychain] <app-entitlements>}"
ID="${2:?identity required ('-' for adhoc)}"
KC="${3:-}"
ENT="${4:?app entitlements file required}"

KCF=""; [ -n "$KC" ] && [ "$ID" != "-" ] && KCF="--keychain $KC"
if [ "$ID" = "-" ]; then TS="--timestamp=none"; else TS="--timestamp"; fi

# Re-sign preserving the target's OWN entitlements + identifier (Sparkle's
# nested code). Hardened runtime is set explicitly (required for notarization).
sign_pres() { codesign --force --options runtime $TS $KCF --sign "$ID" \
    --preserve-metadata=entitlements,identifier "$1"; }
# Sign with no entitlements (framework bundle / bare binary).
sign_plain() { codesign --force --options runtime $TS $KCF --sign "$ID" "$1"; }

FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
	echo "Signing Sparkle.framework components inside-out (own entitlements preserved)"
	V="$FW/Versions/B"
	if [ -d "$V/Updater.app" ]; then
		for exe in "$V/Updater.app/Contents/MacOS/"*; do [ -f "$exe" ] && sign_pres "$exe"; done
		sign_pres "$V/Updater.app"
	fi
	for xpc in "$V/XPCServices/"*.xpc; do [ -e "$xpc" ] && sign_pres "$xpc"; done
	[ -e "$V/Autoupdate" ] && sign_pres "$V/Autoupdate"
	sign_plain "$FW"
else
	echo "  • no Sparkle.framework embedded yet - signing the app only"
fi

echo "Signing the app bundle (Suzu entitlements, no --deep)"
codesign --force --options runtime $TS $KCF --sign "$ID" --entitlements "$ENT" "$APP"

echo "Verifying the whole bundle (deep + strict)"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3
