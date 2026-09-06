#!/bin/bash
# AirControl one-line installer / updater.
#
#   curl -fsSL https://raw.githubusercontent.com/RonakToprani/aircontrol/production/install.sh | sh
#
# Downloads the latest release DMG, verifies its checksum when one is
# published, installs to /Applications, and strips the quarantine flag a
# browser download would have carried — so Gatekeeper never blocks it.
# Safe to re-run any time: that IS the update path. No telemetry, ever.

set -euo pipefail

REPO="RonakToprani/aircontrol"
API="https://api.github.com/repos/$REPO/releases/latest"
FALLBACK_DMG="https://github.com/$REPO/releases/latest/download/AirControl-0.3.0.dmg"
APP="/Applications/AirControl.app"

bold=$(printf '\033[1m'); green=$(printf '\033[32m'); red=$(printf '\033[31m')
yellow=$(printf '\033[33m'); reset=$(printf '\033[0m')

ok()   { printf '%s✓%s %s\n' "$green" "$reset" "$1"; }
warn() { printf '%s!%s %s\n' "$yellow" "$reset" "$1"; }
fail() { printf '%s✗ %s%s\n' "$red" "$1" "$reset" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || fail "AirControl is a macOS app — this doesn't look like a Mac."

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$macos_major" -ge 14 ] 2>/dev/null \
  || fail "AirControl needs macOS 14 (Sonoma) or newer — this Mac is running $(sw_vers -productVersion)."

command -v curl >/dev/null || fail "curl is required and wasn't found."

printf '%sAirControl%s — gesture control for your Mac\n\n' "$bold" "$reset"

# --- Locate the latest release ---------------------------------------------

tmp=$(mktemp -d /tmp/aircontrol-install.XXXXXX)
trap 'rm -rf "$tmp"; [ -n "${mountpoint:-}" ] && hdiutil detach "$mountpoint" -quiet 2>/dev/null || true' EXIT

release_json=$(curl -fsSL "$API" 2>/dev/null || true)

dmg_url=$(printf '%s' "$release_json" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
  | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
sums_url=$(printf '%s' "$release_json" \
  | grep -o '"browser_download_url": *"[^"]*checksums\.txt"' \
  | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')

if [ -z "$dmg_url" ]; then
  warn "Couldn't query GitHub for the latest release — using the pinned URL."
  dmg_url="$FALLBACK_DMG"
fi

# --- Download + verify ------------------------------------------------------

printf '  downloading %s\n' "${dmg_url##*/}"
curl -fL --progress-bar "$dmg_url" -o "$tmp/AirControl.dmg" \
  || fail "Download failed. Check your connection and try again."
ok "downloaded"

if [ -n "$sums_url" ] && curl -fsSL "$sums_url" -o "$tmp/checksums.txt" 2>/dev/null; then
  expected=$(grep "${dmg_url##*/}" "$tmp/checksums.txt" | awk '{print $1}' | head -1)
  actual=$(shasum -a 256 "$tmp/AirControl.dmg" | awk '{print $1}')
  if [ -n "$expected" ]; then
    [ "$expected" = "$actual" ] || fail "Checksum mismatch — the download doesn't match the published release. Aborting."
    ok "checksum verified"
  else
    warn "Release has a checksums.txt but no entry for this DMG — skipping verification."
  fi
else
  warn "No published checksum for this release — skipping verification."
fi

# --- Install ----------------------------------------------------------------

if pgrep -xq AirControl; then
  osascript -e 'tell application "AirControl" to quit' >/dev/null 2>&1 || true
  sleep 1
  pgrep -xq AirControl && fail "AirControl is running and wouldn't quit — close it and re-run."
  ok "quit the running copy"
fi

mountpoint=$(hdiutil attach "$tmp/AirControl.dmg" -nobrowse -readonly -quiet \
  | grep -o '/Volumes/.*' | head -1)
[ -n "$mountpoint" ] && [ -d "$mountpoint/AirControl.app" ] \
  || fail "The downloaded DMG doesn't contain AirControl.app."

rm -rf "$APP"
cp -R "$mountpoint/AirControl.app" "$APP"
hdiutil detach "$mountpoint" -quiet
mountpoint=""
ok "installed to /Applications"

# The whole point of installing from the terminal: no quarantine flag means
# no Gatekeeper "could not verify" dance.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
ok "cleared quarantine — no \"Open Anyway\" needed"

open "$APP"

# --- Next steps -------------------------------------------------------------

printf '\n%sAirControl is running.%s Look for the hand icon in your menu bar (top-right).\n\n' "$bold" "$reset"
printf '  1. Click the hand icon → %sEnable AirControl%s, then allow Camera access.\n' "$bold" "$reset"
printf '  2. When the Accessibility prompt appears, flip the AirControl switch\n'
printf '     in System Settings yourself — the prompt only opens the page.\n'
printf '  3. Run %sCalibrate hand range…%s from the menu. Two pinches, ten seconds.\n\n' "$bold" "$reset"
printf 'Update any time by re-running this same command. Everything stays on your Mac.\n'
