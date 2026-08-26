#!/bin/bash
# Build local .app bundle pentru MediaFlow Monitor (macOS) — unsigned/ad-hoc,
# conform fazei curente de dezvoltare privată.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT/macOS/MediaFlowMonitor"
APP_NAME="MediaFlowMonitor.app"
BUILD_OUT="$ROOT/Build/macOS"
APP_PATH="$BUILD_OUT/$APP_NAME"
ICONSET_SRC="$PKG_DIR/Resources/Assets.xcassets/AppIcon.appiconset"

echo "→ Compilare release (swift build)…"
cd "$PKG_DIR"
swift build -c release

BIN_PATH="$PKG_DIR/.build/release/MediaFlowMonitor"
BUNDLE_PATH="$(find -L "$PKG_DIR/.build/release" -maxdepth 1 -name "*.bundle" | head -n1)"

echo "→ Asamblare $APP_NAME…"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/MediaFlowMonitor"
cp "$PKG_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

if [ -n "$BUNDLE_PATH" ]; then
  cp -R "$BUNDLE_PATH" "$APP_PATH/Contents/Resources/"
fi

echo "→ Generare AppIcon.icns din AppIcon.appiconset…"
ICONSET_TMP="$BUILD_OUT/AppIcon.iconset"
rm -rf "$ICONSET_TMP"
mkdir -p "$ICONSET_TMP"
cp "$ICONSET_SRC"/icon_*.png "$ICONSET_TMP/"
iconutil -c icns "$ICONSET_TMP" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_TMP"

# Leagă icon-ul de Info.plist din bundle (fără să atingem sursa din Resources/)
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_PATH/Contents/Info.plist"

echo "→ Semnare ad-hoc (fără notarization, conform fazei curente)…"
codesign --force --deep -s - "$APP_PATH"

echo "→ Copiere manifest GDC + iconiță în $BUILD_OUT…"
cp "$ROOT/gdc-manifest.json" "$BUILD_OUT/"
mkdir -p "$BUILD_OUT/Resources/GDC"
cp "$ROOT/Resources/GDC/gdc-icon.png" "$BUILD_OUT/Resources/GDC/"
cp "$ROOT/Resources/GDC/gdc-icon.ico" "$BUILD_OUT/Resources/GDC/"

echo "→ Împachetare arhivă privată de test (dist/)…"
VERSION="1.0.0"
DIST_DIR="$ROOT/dist"
ZIP_NAME="MediaFlowMonitor-macOS-$VERSION.zip"
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME"
STAGE="$BUILD_OUT/_staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
cp "$ROOT/gdc-manifest.json" "$STAGE/"
(cd "$STAGE" && zip -qr "$DIST_DIR/$ZIP_NAME" .)
rm -rf "$STAGE"

SHA256=$(shasum -a 256 "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')
python3 -c "
import json, pathlib
p = pathlib.Path('$DIST_DIR/version-manifest.json')
d = json.loads(p.read_text())
d['platforms']['macos']['sha256'] = '$SHA256'
p.write_text(json.dumps(d, indent=2) + '\n')
"

echo ""
echo "✅ Gata: $APP_PATH"
echo "   Manifest GDC: $BUILD_OUT/gdc-manifest.json"
echo "   Arhivă privată: $DIST_DIR/$ZIP_NAME (sha256: $SHA256)"
echo "   Deschide .app cu dublu-click din Finder, apoi testează Cmd+Shift+M."
