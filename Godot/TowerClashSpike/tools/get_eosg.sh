#!/usr/bin/env bash
# Downloads the EOSG (Epic Online Services Godot) GDExtension release into addons/ (mirror of
# get_eosg.ps1). The addon is git-ignored; run once per checkout, then ./check.sh so Godot
# registers the extension.
#   ./get_eosg.sh              # this platform (macos on a Mac, linux on Linux)
#   ./get_eosg.sh macos 2.3.1
set -eu
case "$(uname -s)" in Darwin) DEF=macos ;; *) DEF=linux ;; esac
PLATFORM="${1:-$DEF}"
VERSION="${2:-2.3.1}"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(dirname "$TOOLS")"
URL=$(curl -sL "https://api.github.com/repos/3ddelano/epic-online-services-godot/releases/tags/$VERSION" \
  | grep -o "\"browser_download_url\": *\"[^\"]*epic-online-services-godot-$PLATFORM-[^\"]*\.zip\"" \
  | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
[ -n "$URL" ] || { echo "No $PLATFORM asset in EOSG $VERSION"; exit 1; }
TMP="$(mktemp -d)"
curl -sL -o "$TMP/eosg.zip" "$URL"
unzip -q "$TMP/eosg.zip" -d "$TMP/x"
mkdir -p "$PROJ/addons"
SRC=$(find "$TMP/x" -type d -path "*addons/epic-online-services-godot" | head -1)
[ -n "$SRC" ] || { echo "unexpected archive layout"; exit 1; }
cp -R "$SRC" "$PROJ/addons/"
find "$PROJ/addons/epic-online-services-godot/bin" -name "*.pdb" -delete 2>/dev/null || true
# Downloaded frameworks are quarantined by macOS Gatekeeper; clear it so Godot can load them.
[ "$(uname -s)" = Darwin ] && xattr -dr com.apple.quarantine "$PROJ/addons/epic-online-services-godot" 2>/dev/null || true
rm -rf "$TMP"
echo "EOSG $VERSION ($PLATFORM) installed. Run ./check.sh so Godot registers the extension."
