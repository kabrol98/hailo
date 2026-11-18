#!/usr/bin/env bash
# Verdant Hold installer for Apple Silicon Macs.
#
#   curl -fsSL https://raw.githubusercontent.com/kabrol98/hailo/main/install.sh | bash
#
# Options (as environment variables, or flags after `bash -s --`):
#   VERDANT_VERSION=v0.2.0   install a specific release tag (default: latest)
#   VERDANT_DIR=~/Games      install folder (default: /Applications if writable, else ~/Applications)
#   --uninstall              remove the app (your settings are kept unless you also pass --purge)
#
# Private repository? Either be logged in with the GitHub CLI (`gh auth login`)
# or export GITHUB_TOKEN; the script uses them to download the release.
set -euo pipefail

REPO="${VERDANT_REPO:-kabrol98/hailo}"
VERSION="${VERDANT_VERSION:-latest}"
ASSET="VerdantHold-macos-arm64.zip"
APP="Verdant Hold.app"
USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/Verdant Hold"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

pick_dir() {
  if [ -n "${VERDANT_DIR:-}" ]; then echo "$VERDANT_DIR"
  elif [ -w /Applications ]; then echo /Applications
  else echo "$HOME/Applications"; fi
}

UNINSTALL=0; PURGE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,13p' "$0" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

if [ "$UNINSTALL" = 1 ]; then
  removed=0
  for d in "${VERDANT_DIR:-}" /Applications "$HOME/Applications"; do
    if [ -n "$d" ] && [ -d "$d/$APP" ]; then rm -rf "${d:?}/$APP"; say "Removed $d/$APP"; removed=1; fi
  done
  [ "$removed" = 1 ] || warn "Verdant Hold was not found in /Applications or ~/Applications"
  if [ "$PURGE" = 1 ] && [ -d "$USER_DATA" ]; then rm -rf "$USER_DATA"; say "Removed settings and stats"; fi
  exit 0
fi

# ---------------------------------------------------------------- checks
[ "$(uname -s)" = "Darwin" ] || die "this build is for macOS only"
if [ "$(uname -m)" != "arm64" ] && [ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" != "1" ]; then
  die "this build is for Apple Silicon (M1 or newer) Macs"
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "${major:-0}" -ge 11 ] || die "macOS 11 (Big Sur) or newer is required"
command -v curl >/dev/null || die "curl is required"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- download
download_public() {
  local base
  if [ "$VERSION" = latest ]; then base="https://github.com/$REPO/releases/latest/download"
  else base="https://github.com/$REPO/releases/download/$VERSION"; fi
  curl -fsSL --retry 3 -o "$TMP/$ASSET" "$base/$ASSET" 2>/dev/null &&
    curl -fsSL --retry 3 -o "$TMP/$ASSET.sha256" "$base/$ASSET.sha256" 2>/dev/null
}

download_gh() {
  command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || return 1
  local tag=()
  [ "$VERSION" = latest ] || tag=("$VERSION")
  gh release download ${tag[@]+"${tag[@]}"} --repo "$REPO" --dir "$TMP" --clobber \
    --pattern "$ASSET" --pattern "$ASSET.sha256"
}

download_token() {
  [ -n "${GITHUB_TOKEN:-}" ] || return 1
  local api="https://api.github.com/repos/$REPO/releases" rel name id
  if [ "$VERSION" = latest ]; then rel="$api/latest"; else rel="$api/tags/$VERSION"; fi
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$TMP/release.json" "$rel" || return 1
  for name in "$ASSET" "$ASSET.sha256"; do
    # look up the asset id with macOS's built-in plutil (no jq needed)
    local i=0 n=""; id=""
    while n="$(plutil -extract "assets.$i.name" raw -o - "$TMP/release.json" 2>/dev/null)"; do
      if [ "$n" = "$name" ]; then
        id="$(plutil -extract "assets.$i.id" raw -o - "$TMP/release.json")"; break
      fi
      i=$((i + 1))
    done
    [ -n "$id" ] || return 1
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/octet-stream" \
      -o "$TMP/$name" "$api/assets/$id" || return 1
  done
}

say "Downloading Verdant Hold ($VERSION) from github.com/$REPO"
download_public || download_gh || download_token || die "could not download the release.
  - Check that a release exists: https://github.com/$REPO/releases
  - If the repository is private, run 'gh auth login' first or export GITHUB_TOKEN."

say "Verifying checksum"
expected="$(awk '{print $1}' "$TMP/$ASSET.sha256")"
actual="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "checksum mismatch (expected $expected, got $actual)"

# ---------------------------------------------------------------- install
DEST="$(pick_dir)"
mkdir -p "$DEST"
say "Installing to $DEST/$APP"
ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"
[ -d "$TMP/unpacked/$APP" ] || die "unexpected archive layout"
rm -rf "${DEST:?}/$APP"
mv "$TMP/unpacked/$APP" "$DEST/"
# Not notarized: drop the quarantine flag (if any) so Gatekeeper doesn't block it,
# and make sure the ad-hoc signature is intact.
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true
codesign --verify --deep "$DEST/$APP" 2>/dev/null || codesign --force --deep -s - "$DEST/$APP" >/dev/null 2>&1 || true

version="$(defaults read "$DEST/$APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "?")"
say "Installed Verdant Hold $version"
echo "    Open it from Launchpad / Spotlight, or run:  open \"$DEST/$APP\""
echo "    Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall"
