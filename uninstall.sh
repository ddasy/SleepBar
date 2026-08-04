#!/bin/bash
#
# SleepBar uninstaller: remove launch-at-login -> stop the app -> delete the app,
#                       the `sleepbar` alias, legacy files, and preferences.
#
set -e

APP_NAME="SleepBar"
APP_DIR="$HOME/Applications/$APP_NAME.app"

# Legacy locations used by older installs (bare binary + LaunchAgent)
OLD_INSTALL_DIR="$HOME/Library/Application Support/SleepBar"
OLD_PLIST="$HOME/Library/LaunchAgents/com.sleepbar.app.plist"

echo "==> Uninstalling SleepBar"

# Unregister the Login Item (must run while the .app still exists)
"$APP_DIR/Contents/MacOS/$APP_NAME" --unregister-login 2>/dev/null || true

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP_DIR"

# A DMG install puts the same app in /Applications — remove that copy too, otherwise its
# icon stays behind in Launchpad/Spotlight after "uninstalling".
DMG_APP="/Applications/$APP_NAME.app"
if [ -d "$DMG_APP" ]; then
  "$DMG_APP/Contents/MacOS/$APP_NAME" --unregister-login 2>/dev/null || true
  rm -rf "$DMG_APP" 2>/dev/null \
    || echo "!! Could not remove $DMG_APP (try: sudo rm -rf \"$DMG_APP\")"
fi

# Remove the `sleepbar` alias added by install.sh (matched by its marker comment)
if [ -f "$HOME/.zshrc" ]; then
  sed -i '' '/# added by SleepBar install.sh$/d' "$HOME/.zshrc" 2>/dev/null || true
fi

# Legacy LaunchAgent install
launchctl unload "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
rm -rf "$OLD_INSTALL_DIR"

# Saved preferences (language / end action / custom duration / timed lock)
defaults delete "com.sleepbar.app" 2>/dev/null || true   # .app installs
defaults delete "$APP_NAME"        2>/dev/null || true   # legacy bare-binary installs

echo "Done. SleepBar has been removed."
