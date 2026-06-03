#!/bin/bash
#
# SleepBar uninstaller: stop the app -> remove launch-at-login -> delete binary and preferences.
#
set -e

APP_NAME="SleepBar"
INSTALL_DIR="$HOME/Library/Application Support/SleepBar"
PLIST="$HOME/Library/LaunchAgents/com.sleepbar.app.plist"

echo "==> Uninstalling SleepBar"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALL_DIR"

# Remove saved preferences (language / end action / custom duration)
defaults delete "$APP_NAME" 2>/dev/null || true

echo "Done. SleepBar has been removed."
