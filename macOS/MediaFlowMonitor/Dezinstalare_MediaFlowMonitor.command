#!/usr/bin/env bash
#
# Dezinstalare_MediaFlowMonitor.command
# Dezinstalare & curatare completa pentru MediaFlow Monitor.
#
# Bundle ID: com.gdc.mediaflowmonitor (Info.plist). Licenta e stocata in
# UserDefaults (nu Keychain) — curatata prin `defaults delete`.
#
# Rulare: dublu-click, sau click-dreapta -> Open (Terminal).
#
# NOTA: daca fisierul a fost descarcat separat (nu din arhiva .zip
# originala), poate avea flag de quarantine si/sau bitul de executie
# lipsa - ruleaza intai:
#   xattr -d com.apple.quarantine Dezinstalare_MediaFlowMonitor.command
#   chmod +x Dezinstalare_MediaFlowMonitor.command

set -uo pipefail

BUNDLE_ID="com.gdc.mediaflowmonitor"
APP_PATH="/Applications/MediaFlowMonitor.app"

echo "=================================================="
echo " MediaFlow Monitor — Dezinstalare & Curatare completa"
echo "=================================================="
echo ""

read -p "Sigur vrei sa stergi MediaFlow Monitor si toate datele lui? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Anulat."
    exit 0
fi
echo ""

echo "[1/2] Opresc orice instanta ramasa in fundal..."
pkill -x "MediaFlowMonitor" 2>/dev/null
pkill -f "MediaFlowMonitor.app" 2>/dev/null
sleep 1
echo "[+] Procese oprite."
echo ""

echo "[2/2] Sterg aplicatia si toate fisierele asociate..."

remove_if_exists() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return
    fi
    if rm -rf "$path" 2>/dev/null && [ ! -e "$path" ]; then
        echo "      - sters: $path"
        return
    fi
    echo "      - necesita permisiuni de administrator: $path"
    if sudo rm -rf "$path" && [ ! -e "$path" ]; then
        echo "      - sters (cu sudo): $path"
    else
        echo "      - EROARE: nu am putut sterge $path"
    fi
}

remove_if_exists "$APP_PATH"
remove_if_exists "$HOME/Library/Application Support/MediaFlow Monitor"
remove_if_exists "$HOME/Library/Caches/$BUNDLE_ID"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
remove_if_exists "$HOME/Library/Preferences/$BUNDLE_ID.plist"
remove_if_exists "$HOME/Library/Logs/MediaFlow Monitor"
remove_if_exists "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

echo "[+] Fisiere sterse."
echo ""
echo "=================================================="
echo " [+] Curatare completa finalizata cu succes!"
echo "=================================================="
echo ""
read -p "Apasa Enter pentru a inchide fereastra..."
