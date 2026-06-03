#!/bin/bash
#
# Package SleepBar into a distributable .app bundle + DMG.
#   ./package.sh [version]      e.g. ./package.sh 1.0.1
#
# If no version is given, the latest git tag (vX.Y.Z) is used.
# Output: build/SleepBar.app  and  SleepBar-v<version>.dmg
#
set -e
cd "$(dirname "$0")"

APP_NAME="SleepBar"
BUNDLE_ID="com.sleepbar.app"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}"
VERSION="${VERSION:-1.0.0}"
DMG="$APP_NAME-v$VERSION.dmg"

echo "==> Packaging $APP_NAME v$VERSION"

# 1) Clean & compile (release optimization)
rm -rf "$BUILD_DIR" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "Compiling..."
swiftc -O main.swift -o "$APP/Contents/MacOS/$APP_NAME" -framework AppKit

# 2) Info.plist — LSUIElement=1 keeps it menu-bar only (no Dock icon)
cat > "$APP/Contents/Info.plist" <<PLIST
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
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSHumanReadableCopyright</key>   <string>MIT License</string>
</dict>
</plist>
PLIST

# 3) Ad-hoc code signature (stable signature; NOT Apple-notarized)
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "Ad-hoc signed." \
    || echo "   (codesign skipped)"

# 4) Build the DMG with an /Applications drop target
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG"
