#!/usr/bin/env bash
# codesigning/sign-and-notarize.sh — copiat neschimbat din modulul comun GDC
# (GDCPluginManager/codesigning/), vezi acel README.md pentru cablare completă.
#
# NU face nimic (iese cu succes, fără să semneze) dacă identitatea cerută
# pentru tipul respectiv (APPLE_SIGN_IDENTITY_APP / APPLE_SIGN_IDENTITY_INSTALLER)
# nu e setată — build-ul rămâne ad-hoc/nesemnat, ca înainte.
#
# Usage:
#   codesigning/sign-and-notarize.sh app /path/to/MediaFlowMonitor.app
#   codesigning/sign-and-notarize.sh pkg /path/to/MediaFlowMonitor-1.4.1.pkg
set -euo pipefail

KIND="${1:?Usage: sign-and-notarize.sh <app|pkg> <path>}"
TARGET="${2:?Usage: sign-and-notarize.sh <app|pkg> <path>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sign_app() {
    local app_path="$1"
    echo "==> [codesigning] Semnez binarele bundle-uite (dinauntru spre afara)…"
    find "$app_path" \( -name "*.so" -o -name "*.dylib" -o -perm +111 -type f \) -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            codesign --force --timestamp --options runtime \
                --entitlements "$SCRIPT_DIR/entitlements.plist" \
                --sign "$APPLE_SIGN_IDENTITY_APP" "$f" 2>/dev/null || true
        done

    echo "==> [codesigning] Semnez bundle-ul principal…"
    codesign --force --deep --timestamp --options runtime \
        --entitlements "$SCRIPT_DIR/entitlements.plist" \
        --sign "$APPLE_SIGN_IDENTITY_APP" "$app_path"

    echo "==> [codesigning] Verific semnatura…"
    codesign --verify --deep --strict --verbose=2 "$app_path"
}

notarize() {
    local target="$1"
    local upload_path

    echo "==> [codesigning] Impachetez pentru notarizare…"
    if [ -d "$target" ]; then
        upload_path="/tmp/notarize-$$.zip"
        ditto -c -k --keepParent "$target" "$upload_path"
    else
        local ext="${target##*.}"
        upload_path="/tmp/notarize-$$.${ext}"
        cp "$target" "$upload_path"
    fi

    echo "==> [codesigning] Trimit la Apple (poate dura 1-15 min)…"
    if [ -n "${APPLE_NOTARY_KEY_ID:-}" ]; then
        local key_p8_path="/tmp/notary-key-$$.p8"
        printf '%s' "$APPLE_NOTARY_KEY_P8" > "$key_p8_path"
        xcrun notarytool submit "$upload_path" \
            --key "$key_p8_path" --key-id "$APPLE_NOTARY_KEY_ID" \
            --issuer "$APPLE_NOTARY_ISSUER_ID" --wait
        rm -f "$key_p8_path"
    elif [ -n "${APPLE_NOTARY_APPLE_ID:-}" ]; then
        xcrun notarytool submit "$upload_path" \
            --apple-id "$APPLE_NOTARY_APPLE_ID" --team-id "$APPLE_NOTARY_TEAM_ID" \
            --password "$APPLE_NOTARY_PASSWORD" --wait
    else
        xcrun notarytool submit "$upload_path" --keychain-profile "gdc-notary" --wait
    fi
    rm -f "$upload_path"

    echo "==> [codesigning] Staplez biletul de notarizare…"
    xcrun stapler staple "$target"
}

sign_pkg() {
    local pkg_path="$1"
    if [ -z "${APPLE_SIGN_IDENTITY_INSTALLER:-}" ]; then
        echo "==> [codesigning] APPLE_SIGN_IDENTITY_INSTALLER nesetata - pachetul .pkg ramane nesemnat (Gatekeeper va afisa avertisment la instalare)."
        return 1
    fi
    echo "==> [codesigning] Semnez pachetul .pkg cu certificatul Developer ID Installer…"
    local signed_path="${pkg_path%.pkg}-signed.pkg"
    productsign --sign "$APPLE_SIGN_IDENTITY_INSTALLER" "$pkg_path" "$signed_path"
    mv -f "$signed_path" "$pkg_path"
    echo "==> [codesigning] Verific semnătura pachetului…"
    pkgutil --check-signature "$pkg_path"
}

case "$KIND" in
    app)
        if [ -z "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
            echo "==> [codesigning] APPLE_SIGN_IDENTITY_APP nesetata - sar peste semnare/notarizare (build ramane nesemnat, ca inainte)."
            exit 0
        fi
        sign_app "$TARGET"; notarize "$TARGET"
        ;;
    pkg)
        if sign_pkg "$TARGET"; then
            notarize "$TARGET"
        else
            echo "==> [codesigning] Sar peste notarizarea .pkg (nesemnat)."
        fi
        ;;
    *) echo "Prim argument necunoscut: '$KIND' (astept 'app' sau 'pkg')" >&2; exit 1 ;;
esac

echo "==> [codesigning] Gata: $TARGET"
