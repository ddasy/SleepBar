#!/bin/bash
#
# SleepBar one-line installer
#   - From a cloned repo:   ./install.sh
#   - Remote one-liner:     curl -fsSL https://raw.githubusercontent.com/ddasy/SleepBar/main/install.sh | bash
#
# What it does: check Swift toolchain -> compile -> build ~/Applications/SleepBar.app
#               (Spotlight / Launchpad searchable) -> add the `sleepbar` shell alias
#               -> start with launch-at-login enabled (toggle anytime in the menu).
# No sudo required: everything lives in your home directory.
#
set -e

# NOTE: before publishing, set this to your repository URL (used by the remote one-liner).
REPO_URL="https://github.com/ddasy/SleepBar.git"

APP_NAME="SleepBar"
BUNDLE_ID="com.sleepbar.app"
APP_DIR="$HOME/Applications/$APP_NAME.app"

# Legacy locations used by older installs (bare binary + LaunchAgent); cleaned up below
OLD_INSTALL_DIR="$HOME/Library/Application Support/SleepBar"
OLD_PLIST="$HOME/Library/LaunchAgents/com.sleepbar.app.plist"

echo "==> Installing SleepBar"

# 1) Require the Swift compiler (Xcode Command Line Tools)
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "!! Swift compiler not found. Triggering Xcode Command Line Tools install..."
  xcode-select --install || true
  echo "   Finish the install in the system dialog, then re-run this script."
  exit 1
fi

# 2) Locate the source: use local main.swift if present, otherwise git clone (remote install)
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/main.swift" ]; then
  SRC_DIR="$SCRIPT_DIR"
else
  TMP="$(mktemp -d)"
  echo "==> Downloading source: $REPO_URL"
  git clone --depth 1 "$REPO_URL" "$TMP/SleepBar"
  SRC_DIR="$TMP/SleepBar"
fi

# 3) Compile into an .app bundle in ~/Applications (so Spotlight / Launchpad can find it)
echo "==> Compiling..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
swiftc -O "$SRC_DIR/main.swift" -o "$APP_DIR/Contents/MacOS/$APP_NAME" -framework AppKit

# Version for Info.plist. `git describe` only works when a tag is reachable from HEAD —
# in the `--depth 1` clone above it is not, unless the tip happens to carry the tag, so a
# remote install done between releases would otherwise be stamped 1.0.0 and then nagged
# by the update check forever. Fall back to the newest tag the remote knows about.
VERSION="$(git -C "$SRC_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$SRC_DIR" ls-remote --tags --refs origin 'v*' 2>/dev/null \
             | sed 's#.*refs/tags/v##' | sort -V | tail -1)"
fi
VERSION="${VERSION:-1.0.0}"

# 3b) App icon (the same moon as the menu bar); skip gracefully if rendering fails
render_icons() {
  for s in 16 32 128 256 512; do
    swift "$SRC_DIR/make_icon.swift" "$s"       "$1/icon_${s}x${s}.png"    || return 1
    swift "$SRC_DIR/make_icon.swift" "$((s*2))" "$1/icon_${s}x${s}@2x.png" || return 1
  done
}
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
if render_icons "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  :
else
  echo "   (icon rendering skipped — a generic app icon will be used)"
fi

# 3c) Info.plist — LSUIElement=1 keeps it menu-bar only (no Dock icon)
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSHumanReadableCopyright</key>   <string>MIT License</string>
</dict>
</plist>
PLIST

# Ad-hoc code signature (gives the app a stable identity for the Login Items toggle)
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

# 4) Clean up older installs (bare binary in Application Support + LaunchAgent)
# A DMG install lives in /Applications. Leaving it there means two Login Items, two icons
# in Launchpad/Spotlight and two moons in the menu bar, with updates landing on only one of
# them — so retire it. It goes to the Trash rather than being deleted: it is the same app
# the user just asked to install, and a wrong guess costs them nothing.
OTHER="/Applications/$APP_NAME.app"
if [ -d "$OTHER" ]; then
  echo "==> Found an earlier copy at $OTHER (installed from the DMG)"
  # Drop its Login Item before it goes: the registration is per bundle path, and a trashed
  # app that is still registered leaves a broken entry behind in Login Items.
  "$OTHER/Contents/MacOS/$APP_NAME" --unregister-login 2>/dev/null || true
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.3
  TRASHED="$HOME/.Trash/$APP_NAME $(date +%Y-%m-%d-%H%M%S).app"
  if mv "$OTHER" "$TRASHED" 2>/dev/null; then
    echo "    Moved to the Trash — recover it from there if that wasn't what you wanted."
  else
    echo "!!  Couldn't move it (no write access to /Applications?). Remove it yourself:"
    echo "      rm -rf \"$OTHER\""
  fi
fi

launchctl unload "$OLD_PLIST" 2>/dev/null || true
rm -f "$OLD_PLIST"
rm -rf "$OLD_INSTALL_DIR"

# 5) Start, registering launch-at-login (uncheck anytime: menu-bar icon -> Launch at Login)
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3
open "$APP_DIR" --args --register-login

# 6) Add the `sleepbar` alias for easy manual starts (e.g. after quitting by accident).
#    A plain ~/.zshrc alias — no sudo needed. Skipped if any `sleepbar` alias already exists.
ZSHRC="$HOME/.zshrc"
if ! grep -qsF "alias sleepbar=" "$ZSHRC"; then
  printf "\nalias sleepbar='open -a SleepBar'  # added by SleepBar install.sh\n" >> "$ZSHRC"
  echo "==> Added the 'sleepbar' alias to ~/.zshrc"
fi

echo ""
echo "Done! The SleepBar icon (moon) is now in your menu bar."
echo "  - Launch at login : ON  (toggle: menu-bar icon -> Launch at Login)"
echo "  - Manual start    : Spotlight (Cmd+Space) -> SleepBar, or type 'sleepbar'"
echo "                      in Terminal (new windows; this one needs: source ~/.zshrc)"
echo "  - Uninstall       : ./uninstall.sh"
