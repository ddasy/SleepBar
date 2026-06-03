#!/bin/bash
#
# SleepBar one-line installer
#   - From a cloned repo:   ./install.sh
#   - Remote one-liner:     curl -fsSL https://raw.githubusercontent.com/ddasy/SleepBar/main/install.sh | bash
#
# What it does: check Swift toolchain -> compile -> install to Application Support
#               -> set up launch-at-login -> start.
#
set -e

# NOTE: before publishing, set this to your repository URL (used by the remote one-liner).
REPO_URL="https://github.com/ddasy/SleepBar.git"

APP_NAME="SleepBar"
INSTALL_DIR="$HOME/Library/Application Support/SleepBar"
PLIST="$HOME/Library/LaunchAgents/com.sleepbar.app.plist"
LABEL="com.sleepbar.app"

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

# 3) Compile (optimized)
echo "==> Compiling..."
mkdir -p "$INSTALL_DIR"
swiftc -O "$SRC_DIR/main.swift" -o "$INSTALL_DIR/$APP_NAME" -framework AppKit

# 4) Launch at login (LaunchAgent)
echo "==> Setting up launch-at-login..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

# 5) Start (stop any old instance first)
pkill -x "$APP_NAME" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "Done! The SleepBar icon (moon) is now in your menu bar."
echo "It will start automatically at login. To remove it, run ./uninstall.sh"
