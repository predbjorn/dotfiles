#!/usr/bin/env bash
set -euo pipefail

# Runs from anywhere: resolve to the tool root regardless of caller's CWD.
cd "$(dirname "$0")/.."

APP_DIR="$HOME/Applications/LaunchDashboard.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
LOG_DIR="$HOME/Library/Logs/LaunchDashboard"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENT_DIR/com.prebenhafnor.launch-dashboard.plist"
BIN_PATH="$MACOS_DIR/LaunchDashboard"

mkdir -p "$MACOS_DIR" "$LOG_DIR" "$LAUNCH_AGENT_DIR"

echo "Building release binary..."
swift build -c release

echo "Assembling LaunchDashboard.app bundle..."
cp -f .build/release/LaunchDashboard "$BIN_PATH"
chmod +x "$BIN_PATH"
cp -f scripts/Info.plist "$APP_DIR/Contents/Info.plist"

echo "Writing LaunchAgent plist..."
sed -e "s|__BIN_PATH__|$BIN_PATH|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    scripts/com.prebenhafnor.launch-dashboard.plist.template > "$PLIST_PATH"

UID_NUM=$(id -u)
DOMAIN_TARGET="gui/$UID_NUM/com.prebenhafnor.launch-dashboard"
launchctl bootout "$DOMAIN_TARGET" 2>/dev/null || true
# bootout is asynchronous; wait for the job to fully unload before bootstrapping,
# otherwise a re-install races and bootstrap fails with EIO (5: Input/output error).
for _ in $(seq 1 20); do
    launchctl print "$DOMAIN_TARGET" >/dev/null 2>&1 || break
    sleep 0.5
done
launchctl bootstrap "gui/$UID_NUM" "$PLIST_PATH"

echo "Installed to $APP_DIR"
echo "Tail logs with: tail -f $LOG_DIR/launch-dashboard.log"
echo "Bearer token (do NOT share):"
echo "  jq -r .bearerToken \"\$HOME/Library/Application Support/LaunchDashboard/config.json\""
