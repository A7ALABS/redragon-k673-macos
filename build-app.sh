#!/bin/sh
set -e
cd "$(dirname "$0")"
# UNIVERSAL=1 builds arm64 + x86_64 (needs full Xcode); VERSION sets the bundle version.
VERSION="${VERSION:-1.0.0}"
ARCHS=""
[ -n "$UNIVERSAL" ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"
APP="build/K673 Control.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/K673App" "$APP/Contents/MacOS/K673App"
cp "$BIN/k673ctl" build/k673ctl
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>K673 Control</string>
    <key>CFBundleIdentifier</key><string>com.a7alabs.k673control</string>
    <key>CFBundleExecutable</key><string>K673App</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
P
codesign --force --sign - "$APP"
echo "Built $APP and build/k673ctl"
