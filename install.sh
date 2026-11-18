#!/usr/bin/env bash
# Verdant Hold installer for Apple Silicon Macs.
#
#   curl -fsSL https://raw.githubusercontent.com/kabrol98/hailo/main/install.sh | bash
#
# Options (as environment variables, or flags after `bash -s --`):
#   VERDANT_VERSION=v0.2.0   install a specific release tag (default: latest)
#   VERDANT_DIR=~/Games      install folder (default: where it's already installed, else
#                            /Applications if writable, else ~/Applications)
#   --force                  reinstall even if this version is already installed
#   --uninstall              remove the app (your settings are kept unless you also pass --purge)
#
# Re-running it upgrades in place: the existing app is found wherever it lives,
# the new one is staged next to it and swapped in with a rename, and the old one
# is only deleted once the new one is in place. Settings and best scores (kept in
# ~/Library/Application Support) are never touched except by --purge.
#
# Private repository? Either be logged in with the GitHub CLI (`gh auth login`)
# or export GITHUB_TOKEN; the script uses them to download the release.
set -euo pipefail

REPO="${VERDANT_REPO:-kabrol98/hailo}"
VERSION="${VERDANT_VERSION:-latest}"
ASSET="VerdantHold-macos-arm64.zip"
APP="Verdant Hold.app"
BUNDLE_ID="io.github.verdanthold.game"
USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/Verdant Hold"
# Remembers where the app was installed, so a custom VERDANT_DIR is found next time.
STATE="$HOME/Library/Application Support/Verdant Hold Installer/location"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Prints every installed copy, one path per line: the usual folders, plus any
# Spotlight knows about inside an Applications folder (e.g. a custom VERDANT_DIR
# from an earlier install).
find_installs() {
  {
    if [ -f "$STATE" ]; then
      local saved; saved="$(cat "$STATE" 2>/dev/null || true)"
      [ -n "$saved" ] && [ -d "$saved" ] && echo "$saved"
    fi
    for d in "${VERDANT_DIR:-}" /Applications "$HOME/Applications"; do
      [ -n "$d" ] && [ -d "$d/$APP" ] && echo "$d/$APP"
    done
    if command -v mdfind >/dev/null 2>&1; then
      mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | grep '/Applications/' || true
    fi
  } | awk 'NF && !seen[$0]++'
}

app_version() { defaults read "$1/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo ""; }

running_pid() { pgrep -f "$1/Contents/MacOS/" 2>/dev/null | head -1 || true; }

# Asks a yes/no question on the terminal even when the script is piped into bash.
confirm() {
  local reply
  # no terminal (e.g. run from a script or CI): don't prompt
  { : < /dev/tty; } 2>/dev/null || return 1
  printf '%s [Y/n] ' "$1" > /dev/tty 2>/dev/null || return 1
  read -r reply < /dev/tty 2>/dev/null || return 1
  case "$reply" in [nN]*) return 1 ;; *) return 0 ;; esac
}

stop_if_running() {
  local app="$1" pid i
  pid="$(running_pid "$app")"
  [ -n "$pid" ] || return 0
  if confirm "Verdant Hold is running. Quit it now so the update takes effect?"; then
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
    for i in 1 2 3 4 5 6 7 8 9 10; do
      [ -n "$(running_pid "$app")" ] || { say "Quit Verdant Hold"; return 0; }
      sleep 1
    done
    kill "$pid" 2>/dev/null || true
  else
    warn "Verdant Hold is still running; the new version is used the next time you open it"
  fi
}

UNINSTALL=0; PURGE=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,22p' "$0" 2>/dev/null || true; exit 0 ;;
    *) die "unknown option: $arg" ;;
  esac
done

if [ "$UNINSTALL" = 1 ]; then
  removed=0
  while IFS= read -r app; do
    stop_if_running "$app"
    rm -rf "${app:?}"; say "Removed $app"; removed=1
  done < <(find_installs)
  [ "$removed" = 1 ] || warn "Verdant Hold is not installed"
  rm -f "$STATE"; rmdir "$(dirname "$STATE")" 2>/dev/null || true
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

# Works out which tag "latest" means, so an up-to-date install can skip the download.
resolve_tag() {
  local loc
  if [ "$VERSION" != latest ]; then echo "$VERSION"; return; fi
  loc="$(curl -fsSI "https://github.com/$REPO/releases/latest" 2>/dev/null | tr -d '\r' \
    | awk 'tolower($1)=="location:" {print $2}' | tail -1)"
  case "$loc" in */releases/tag/*) echo "${loc##*/}"; return ;; esac
  if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null && return
  fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$TMP/latest.json" \
      "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null &&
      plutil -extract tag_name raw -o - "$TMP/latest.json" 2>/dev/null && return
  fi
  echo ""
}

EXISTING="$(find_installs | head -1)"
if [ "$(find_installs | wc -l | tr -d ' ')" -gt 1 ]; then
  warn "found more than one copy of Verdant Hold:"; find_installs | sed 's/^/    /' >&2
fi
TAG="$(resolve_tag)"
if [ -n "$EXISTING" ]; then
  have="$(app_version "$EXISTING")"
  say "Found Verdant Hold ${have:-?} at $EXISTING"
  if [ "$FORCE" = 0 ] && [ -n "$TAG" ] && [ -n "$have" ] && [ "$have" = "${TAG#v}" ]; then
    say "Already up to date (${TAG}). Use --force to reinstall."
    exit 0
  fi
fi

say "Downloading Verdant Hold (${TAG:-$VERSION}) from github.com/$REPO"
download_public || download_gh || download_token || die "could not download the release.
  - Check that a release exists: https://github.com/$REPO/releases
  - If the repository is private, run 'gh auth login' first or export GITHUB_TOKEN."

say "Verifying checksum"
expected="$(awk '{print $1}' "$TMP/$ASSET.sha256")"
actual="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "checksum mismatch (expected $expected, got $actual)"

# ---------------------------------------------------------------- install
# Upgrade where it already lives, unless VERDANT_DIR says otherwise.
if [ -n "${VERDANT_DIR:-}" ]; then DEST="$VERDANT_DIR"
elif [ -n "$EXISTING" ]; then DEST="$(dirname "$EXISTING")"
elif [ -w /Applications ]; then DEST=/Applications
else DEST="$HOME/Applications"; fi
mkdir -p "$DEST"
TARGET="$DEST/$APP"
STAGE="$DEST/.$APP.new.$$"
OLD="$DEST/.$APP.old.$$"
trap 'rm -rf "$TMP" "$STAGE"' EXIT

ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"
[ -d "$TMP/unpacked/$APP" ] || die "unexpected archive layout"
# Stage the new app in the destination folder so the swap below is a rename.
ditto "$TMP/unpacked/$APP" "$STAGE" || die "could not write to $DEST"
# Not notarized: drop the quarantine flag (if any) so Gatekeeper doesn't block it,
# and make sure the ad-hoc signature is intact.
xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null || true
codesign --verify --deep "$STAGE" 2>/dev/null || codesign --force --deep -s - "$STAGE" >/dev/null 2>&1 || true

[ -d "$TARGET" ] && stop_if_running "$TARGET"
say "Installing to $TARGET"
if [ -e "$TARGET" ]; then
  mv "$TARGET" "$OLD" || die "could not move the old version aside"
  if ! mv "$STAGE" "$TARGET"; then
    mv "$OLD" "$TARGET"   # put the old version back
    die "could not install the new version; the old one is unchanged"
  fi
  rm -rf "$OLD"
else
  mv "$STAGE" "$TARGET" || die "could not install to $DEST"
fi
# An explicit VERDANT_DIR moves the install: remove copies left in the old place.
if [ -n "$EXISTING" ] && [ "$EXISTING" != "$TARGET" ] && [ -n "${VERDANT_DIR:-}" ]; then
  stop_if_running "$EXISTING"
  rm -rf "${EXISTING:?}" && say "Removed the previous copy at $EXISTING"
fi

mkdir -p "$(dirname "$STATE")" && echo "$TARGET" > "$STATE" || true
version="$(app_version "$TARGET")"
say "Installed Verdant Hold ${version:-?}"
echo "    Open it from Launchpad / Spotlight, or run:  open \"$TARGET\""
echo "    Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall"
