#!/bin/bash
# Builds ~/Applications/WallpaperShow.app, a hidden helper that opens
# dotfiles-wallpaper://show/<set> links (the gallery's "Use today" button) by running
# `wallpaper.py --show <set>`. Run by setupfiles/sync.sh; safe to re-run.
set -e

DOTFILES=${DOTFILES:-"$HOME/.dotfiles"}
PYTHON_BIN=${PYTHON_BIN:-$(pyenv which python 2>/dev/null || echo "$HOME/.pyenv/versions/3.12.9/bin/python")}
APP="$HOME/Applications/WallpaperShow.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

SRC=$(mktemp -t wallpaper-url).applescript
cat > "$SRC" <<EOF
on open location theURL
	set AppleScript's text item delimiters to "/"
	set setKey to last text item of theURL
	set AppleScript's text item delimiters to ""
	do shell script quoted form of "$PYTHON_BIN" & " " & quoted form of "$DOTFILES/script/wallpaper.py" & " --show " & quoted form of setKey & " > /dev/null 2>&1 &"
end open location
EOF

mkdir -p "$HOME/Applications"
rm -rf "$APP"
osacompile -o "$APP" "$SRC"
rm -f "$SRC"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.predbjorn.wallpaper-show" "$PLIST" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.predbjorn.wallpaper-show" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string Wallpaper show" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string dotfiles-wallpaper" "$PLIST"
codesign --force --sign - "$APP" 2>/dev/null || true
"$LSREGISTER" -f "$APP"
echo "Installed $APP (dotfiles-wallpaper:// links)"
