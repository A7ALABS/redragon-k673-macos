#!/bin/sh
# Builds the app and packs it, with the CLI, into build/K673-Control-<version>.dmg
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
export VERSION
./build-app.sh
STAGE="build/dmg"
DMG="build/K673-Control-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/K673 Control.app" "$STAGE/"
cp build/k673ctl "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "K673 Control" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
