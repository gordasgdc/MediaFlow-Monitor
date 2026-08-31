#!/usr/bin/env bash
# Builds "MediaFlowMonitor.app" (Mac, SPM), il impacheteaza intr-un .pkg
# semnat + notarizat, cu panou de licenta (Terms & Conditions), instalare
# DIRECTA in /Applications. Port 1:1 al tiparului deja folosit in
# GDCVault/CGConvertor/CursorPro (build_installer.sh).
set -euo pipefail
cd "$(dirname "$0")/macOS/MediaFlowMonitor"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
PKG_ID="com.gdc.mediaflowmonitor.installer"
APP_NAME="MediaFlowMonitor.app"
DIST_DIR="../../dist"
PAYLOAD_ROOT="$DIST_DIR/payload"
COMPONENT_PKG="$DIST_DIR/MediaFlowMonitor-component.pkg"
FINAL_PKG="$DIST_DIR/MediaFlowMonitor-$VERSION.pkg"

echo "==> Building app (version $VERSION)…"
swift build -c release --product MediaFlowMonitor
BUILD_OUT="/tmp/MediaFlowMonitor.app.build-$$"
rm -rf "$BUILD_OUT"
mkdir -p "$BUILD_OUT/Contents/MacOS" "$BUILD_OUT/Contents/Resources"
cp .build/release/MediaFlowMonitor "$BUILD_OUT/Contents/MacOS/MediaFlowMonitor"
cp Resources/Info.plist "$BUILD_OUT/Contents/Info.plist"
if [ -f "../../Build/macOS/MediaFlowMonitor.app/Contents/Resources/AppIcon.icns" ]; then
    cp "../../Build/macOS/MediaFlowMonitor.app/Contents/Resources/AppIcon.icns" "$BUILD_OUT/Contents/Resources/AppIcon.icns"
fi
if [ -f "../../installer/Instructiuni_Utilizare.pdf" ]; then
    cp "../../installer/Instructiuni_Utilizare.pdf" "$BUILD_OUT/Contents/Resources/"
fi

if [ -n "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
    ./codesigning/sign-and-notarize.sh app "$BUILD_OUT"
else
    echo "AVERTISMENT: APPLE_SIGN_IDENTITY_APP nesetat - semnez ad-hoc (pachetul final va ramane nesemnat)."
    codesign --force --deep --sign - "$BUILD_OUT"
fi

rm -rf "$DIST_DIR"
mkdir -p "$PAYLOAD_ROOT/Applications"
cp -R "$BUILD_OUT" "$PAYLOAD_ROOT/Applications/$APP_NAME"
rm -rf "$BUILD_OUT"

echo "==> Building component package…"
pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts "../../installer/scripts" \
    "$COMPONENT_PKG"

echo "==> Writing distribution definition…"
cat > "$DIST_DIR/Distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>MediaFlow Monitor $VERSION</title>
    <license file="License.txt" mime-type="text/plain"/>
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

cp ../../installer/License.txt "$DIST_DIR/License.txt"

echo "==> Building final installer package…"
productbuild \
    --distribution "$DIST_DIR/Distribution.xml" \
    --package-path "$DIST_DIR" \
    --resources "$DIST_DIR" \
    "$FINAL_PKG"

rm -rf "$PAYLOAD_ROOT" "$COMPONENT_PKG"

./codesigning/sign-and-notarize.sh pkg "$FINAL_PKG"

cp "$FINAL_PKG" "$DIST_DIR/MediaFlowMonitor.pkg"

echo "==> Copying uninstaller…"
cp "Dezinstalare_MediaFlowMonitor.command" "$DIST_DIR/Dezinstalare_MediaFlowMonitor.command"
chmod +x "$DIST_DIR/Dezinstalare_MediaFlowMonitor.command"

echo "==> Building MediaFlowMonitor-macOS.zip (pkg + uninstaller + instructiuni)…"
ZIP_STAGE="$DIST_DIR/zip_stage"
rm -rf "$ZIP_STAGE"
mkdir -p "$ZIP_STAGE"
cp "$DIST_DIR/MediaFlowMonitor.pkg" "$ZIP_STAGE/"
cp "../../installer/Instructiuni_Utilizare.pdf" "$ZIP_STAGE/" 2>/dev/null || true
cp "$DIST_DIR/Dezinstalare_MediaFlowMonitor.command" "$ZIP_STAGE/"
chmod +x "$ZIP_STAGE/Dezinstalare_MediaFlowMonitor.command"
( cd "$ZIP_STAGE" && zip -q -r -y "../MediaFlowMonitor-macOS.zip" . )
rm -rf "$ZIP_STAGE"

echo "==> Done: $FINAL_PKG"
echo "==> Also: $DIST_DIR/MediaFlowMonitor.pkg, $DIST_DIR/MediaFlowMonitor-macOS.zip"
