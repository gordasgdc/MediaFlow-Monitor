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

# Build number (CFBundleVersion) — incrementat automat la fiecare build,
# distinct de versiunea semantică (CFBundleShortVersionString), afișat în
# fereastra About ("v1.3.2 (build 7)").
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PKG_DIR/Resources/Info.plist" 2>/dev/null || echo 0)
NEXT_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PKG_DIR/Resources/Info.plist"
echo "→ Build number: $NEXT_BUILD"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/MediaFlowMonitor"
cp "$PKG_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

if [ -n "$BUNDLE_PATH" ]; then
  cp -R "$BUNDLE_PATH" "$APP_PATH/Contents/Resources/"
fi

# BUG FIX: manifestul GDC stătea liber lângă .app în zip ("fișiere scoase
# aiurea"). Acum e încapsulat ÎN bundle — nimic în afara .app la livrare.
mkdir -p "$APP_PATH/Contents/Resources/GDC"
cp "$ROOT/gdc-manifest.json" "$APP_PATH/Contents/Resources/GDC/"
cp "$ROOT/Resources/GDC/gdc-icon.png" "$APP_PATH/Contents/Resources/GDC/"

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

if [ -n "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
  echo "→ Semnare + notarizare oficială (APPLE_SIGN_IDENTITY_APP setată)…"
  "$PKG_DIR/codesigning/sign-and-notarize.sh" app "$APP_PATH"
else
  echo "→ Semnare ad-hoc (fără notarization — setează APPLE_SIGN_IDENTITY_APP pentru semnare reală)…"
  codesign --force --deep -s - "$APP_PATH"
fi

echo "→ Împachetare arhivă privată de test (dist/)…"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DIST_DIR="$ROOT/dist"
ZIP_NAME="MediaFlowMonitor-macOS-$VERSION.zip"
mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME"
STAGE="$BUILD_OUT/_staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
# Regula 6 — arhivă cu STRICT 3 fișiere la rădăcină: .app, uninstaller, PDF.
cp "$PKG_DIR/Dezinstalare_MediaFlowMonitor.command" "$STAGE/"
if [ -f "$ROOT/installer/Instructiuni_Utilizare.pdf" ]; then
  cp "$ROOT/installer/Instructiuni_Utilizare.pdf" "$STAGE/"
else
  echo "→ ⚠️  PDF lipsă — rulează 'python3 installer/generate_pdf.py' înainte de release."
fi
(cd "$STAGE" && zip -qr "$DIST_DIR/$ZIP_NAME" .)
rm -rf "$STAGE"

SHA256=$(shasum -a 256 "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')
python3 -c "
import json, pathlib
p = pathlib.Path('$DIST_DIR/version-manifest.json')
d = json.loads(p.read_text())
d['platforms']['macos']['sha256'] = '$SHA256'
d['platforms']['macos']['version'] = '$VERSION'
d['platforms']['macos']['packageUrl'] = 'dist/$ZIP_NAME'
d['latestVersion'] = '$VERSION'
p.write_text(json.dumps(d, indent=2) + '\n')
"
# gdc-manifest.json versiunea trebuie sa ramana in sincron cu fiecare release.
python3 -c "
import json, pathlib
p = pathlib.Path('$ROOT/gdc-manifest.json')
d = json.loads(p.read_text())
d['version'] = '$VERSION'
p.write_text(json.dumps(d, indent=2) + '\n')
"

echo ""
echo "✅ Gata: $APP_PATH (v$VERSION)"
echo "   Arhivă privată: $DIST_DIR/$ZIP_NAME (sha256: $SHA256) — .app + uninstaller + PDF (Regula 6)"
echo "   Deschide .app cu dublu-click din Finder, apoi testează Cmd+Shift+M."

# Sincronizează versiunea + update.json pe gordas.dev/media-flow-monitor —
# nu comite/pushuiește automat (repo diferit), doar scrie fișierele local.
bash "$ROOT/scripts/sync-site.sh" || echo "→ ⚠️  Sincronizarea site-ului a eșuat — vezi eroarea de mai sus."
