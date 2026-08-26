#!/bin/bash
# Construiește installer-ul nativ .pkg pentru MediaFlow Monitor — wizard
# clasic macOS ("Install MediaFlow Monitor"), instalare directă în
# /Applications la Continue/Install, fără drag-and-drop manual (Regula 5
# din CLAUDE.md). Presupune că build-macos-app.sh a rulat deja și
# Build/macOS/MediaFlowMonitor.app există, semnat+notarizat.
#
# Semnare: necesită APPLE_SIGN_IDENTITY_INSTALLER (certificatul "Developer
# ID Installer", distinct de "Developer ID Application" folosit pentru
# .app) — altfel .pkg rămâne nesemnat (avertisment Gatekeeper la instalare).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT/Build/macOS/MediaFlowMonitor.app"
PKG_DIR="$ROOT/macOS/MediaFlowMonitor"
DIST_DIR="$ROOT/dist"
PKG_ID="com.gdc.mediaflowmonitor.installer"

if [ ! -d "$APP_PATH" ]; then
  echo "→ ⚠️  $APP_PATH nu există — rulează întâi scripts/build-macos-app.sh."
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
PAYLOAD_ROOT="$DIST_DIR/pkg_payload"
COMPONENT_PKG="$DIST_DIR/MediaFlowMonitor-component.pkg"
FINAL_PKG="$DIST_DIR/MediaFlowMonitor-$VERSION.pkg"

echo "→ Pregătesc payload-ul (.app → /Applications)…"
rm -rf "$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_ROOT/Applications"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/Applications/MediaFlowMonitor.app"

echo "→ Construiesc component package…"
# --install-location "/" (NU "/Applications") pentru că $PAYLOAD_ROOT deja
# conține propriul subfolder Applications/ — vezi pitfall-ul deja documentat
# în GDCPluginManager/build_installer.sh (dublare /Applications/Applications/).
pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location "/" \
  --scripts "$ROOT/installer/scripts" \
  "$COMPONENT_PKG"

echo "→ Scriu definiția de distribuție…"
cat > "$DIST_DIR/Distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>MediaFlow Monitor $VERSION</title>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <domains enable_localSystem="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="$PKG_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$PKG_ID" visible="false">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">MediaFlowMonitor-component.pkg</pkg-ref>
</installer-gui-script>
EOF

echo "→ Construiesc pachetul final…"
productbuild \
  --distribution "$DIST_DIR/Distribution.xml" \
  --package-path "$DIST_DIR" \
  "$FINAL_PKG"

rm -rf "$PAYLOAD_ROOT" "$COMPONENT_PKG" "$DIST_DIR/Distribution.xml"

# Semnare (Developer ID Installer) + notarizare + staple — la fel ca .app,
# dacă certificatul e configurat; altfel rămâne nesemnat, cu avertisment
# Gatekeeper documentat clar în instrucțiuni.
"$PKG_DIR/codesigning/sign-and-notarize.sh" pkg "$FINAL_PKG" || true

# Copie stabilă, fără versiune în nume — ținta fixă pentru site/update.json
# (Regula 17, excepția explicită pentru linkul stabil de release).
cp "$FINAL_PKG" "$DIST_DIR/MediaFlowMonitor.pkg"

SHA256=$(shasum -a 256 "$FINAL_PKG" | awk '{print $1}')

# .pkg e artefactul PRINCIPAL de distribuție (site + update.json) — build-
# macos-app.sh scrie mai devreme packageUrl/sha256 spre .zip; suprascriem
# aici ca versiunea finală din version-manifest.json să reflecte mereu .pkg.
python3 -c "
import json, pathlib
p = pathlib.Path('$DIST_DIR/version-manifest.json')
d = json.loads(p.read_text())
d['platforms']['macos']['packageUrl'] = 'dist/MediaFlowMonitor-$VERSION.pkg'
d['platforms']['macos']['sha256'] = '$SHA256'
p.write_text(json.dumps(d, indent=2) + '\n')
"

echo ""
echo "✅ Gata: $FINAL_PKG (sha256: $SHA256)"
echo "   Copie stabilă: $DIST_DIR/MediaFlowMonitor.pkg"
