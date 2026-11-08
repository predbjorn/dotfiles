#!/usr/bin/env bash
# Build DiskCleaner and install it to ~/Applications/DiskCleaner.app.
# The sketchybar disk-cleanup button opens this app on left-click.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications/DiskCleaner.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

echo "Building release binary..."
swift build -c release

echo "Assembling $APP_DIR..."
# Quit a running copy so the new binary is picked up on next open.
osascript -e 'quit app id "com.prebenhafnor.disk-cleaner"' >/dev/null 2>&1 || true
mkdir -p "$MACOS_DIR" "$APP_DIR/Contents/Resources"
cp -f .build/release/DiskCleaner "$MACOS_DIR/DiskCleaner"
chmod +x "$MACOS_DIR/DiskCleaner"
cp -f scripts/Info.plist "$APP_DIR/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper and TCC treat it as one stable app.
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Installed. Open with: open -a DiskCleaner"
