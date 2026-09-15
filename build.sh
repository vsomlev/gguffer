#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
cd "$ROOT"

APP_NAME="gguffer"
APP="build/$APP_NAME.app"
DIST_DIR="dist"
ACTOOL="${ACTOOL:-/Applications/Xcode.app/Contents/Developer/usr/bin/actool}"
ICON_SOURCE="$ROOT/Resources/icon/$APP_NAME.icon"
ICON_FALLBACK="$ROOT/Resources/icon/$APP_NAME.icns"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"
cp src/Info.plist "$PLIST"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Compiling"
swiftc -O -whole-module-optimization \
	-target "$(uname -m)-apple-macos13.0" \
	-o "$APP/Contents/MacOS/$APP_NAME" \
	src/main.swift src/MainWindowController.swift src/LogView.swift \
	src/ServerController.swift src/ServerStatus.swift src/Settings.swift src/Config.swift

echo "==> Icon"
if [ -x "$ACTOOL" ]; then
	# Xcode is here, so build the icon from its source. This produces both an
	# Assets.car (macOS 26 renders the icon from that) and a plain .icns.
	"$ACTOOL" --output-format human-readable-text \
		--app-icon "$APP_NAME" \
		--output-partial-info-plist "$(mktemp -t gguffer-icon)" \
		--target-device mac --platform macosx --minimum-deployment-target 13.0 \
		--compile "$ROOT/$APP/Contents/Resources" "$ICON_SOURCE" >/dev/null
	# Keep the committed fallback in step, so a machine without Xcode still
	# builds an app with an icon.
	cp "$APP/Contents/Resources/$APP_NAME.icns" "$ICON_FALLBACK"
	echo "    compiled from $ICON_SOURCE"
elif [ -f "$ICON_FALLBACK" ]; then
	cp "$ICON_FALLBACK" "$APP/Contents/Resources/"
	# No Assets.car to name, so drop the key rather than point it at nothing.
	plutil -remove CFBundleIconName "$PLIST" 2>/dev/null || true
	echo "    no Xcode; used prebuilt $ICON_FALLBACK"
else
	plutil -remove CFBundleIconName "$PLIST" 2>/dev/null || true
	plutil -remove CFBundleIconFile "$PLIST" 2>/dev/null || true
	echo "    no icon available; building without one"
fi

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null

echo "==> Disk image"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "==> Wrote $DMG ($(du -h "$DMG" | cut -f1))"
