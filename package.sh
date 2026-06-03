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

# 1b) Build AppIcon.icns from the menu-bar moon (SF Symbol moon.zzz)
echo "Rendering icon..."
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
# iconutil expects these exact names; @2x is the doubled pixel size.
gen() { swift make_icon.swift "$2" "$ICONSET/$1.png"; }
gen icon_16x16        16
gen icon_16x16@2x     32
gen icon_32x32        32
gen icon_32x32@2x     64
gen icon_128x128     128
gen icon_128x128@2x  256
gen icon_256x256     256
gen icon_256x256@2x  512
gen icon_512x512     512
gen icon_512x512@2x 1024
ICNS="$APP/Contents/Resources/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

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
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSHumanReadableCopyright</key>   <string>MIT License</string>
</dict>
</plist>
PLIST

# 3) Ad-hoc code signature (stable signature; NOT Apple-notarized)
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "Ad-hoc signed." \
    || echo "   (codesign skipped)"

# 4) Build the DMG with an /Applications drop target + custom icons
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ICNS" "$STAGE/.VolumeIcon.icns"          # Finder shows this for the mounted volume

# Build read-write first so we can flag the volume's custom-icon bit,
# then convert to a compressed read-only image for distribution.
TMP_DMG="$BUILD_DIR/tmp.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDRW "$TMP_DMG" >/dev/null
DEV="$(hdiutil attach "$TMP_DMG" -nobrowse -noverify -noautoopen | grep -Eo '/Volumes/.*' | head -1)"
SetFile -a C "$DEV"                            # kHasCustomIcon -> use .VolumeIcon.icns
hdiutil detach "$DEV" -quiet
hdiutil convert "$TMP_DMG" -format UDZO -o "$DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGE"

# Give the .dmg file itself a Finder icon (what you see in Downloads).
swift set_file_icon.swift "$ICNS" "$DMG" || echo "   (dmg file-icon skipped)"

echo "==> Done: $DMG"
