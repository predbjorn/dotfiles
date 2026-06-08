#!/usr/bin/env bash
# install.sh — build Keymapper.app and install it to ~/Applications/.
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
PACKAGE="$DOTFILES/tools/keymapper"
APP_NAME="Keymapper"
DEST="$HOME/Applications/${APP_NAME}.app"

echo "→ Building $APP_NAME (release)…"
cd "$PACKAGE"
swift build --configuration release

BIN=".build/release/KeymapperApp"

if [ ! -f "$BIN" ]; then
  echo "✗ Build failed: $BIN not found." >&2
  exit 1
fi

echo "→ Assembling ${APP_NAME}.app…"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
mkdir -p "$DEST/Contents/Resources"

cp "$BIN"      "$DEST/Contents/MacOS/KeymapperApp"
cp Info.plist  "$DEST/Contents/"
chmod +x       "$DEST/Contents/MacOS/KeymapperApp"

echo "✓ Installed → $DEST"
echo ""
echo "Run with:  open ~/Applications/${APP_NAME}.app"
echo "Or add an alias:  alias keymapper='open ~/Applications/${APP_NAME}.app'"
