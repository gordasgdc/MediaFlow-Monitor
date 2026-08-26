#!/bin/bash
# Sincronizeaza versiunea + update.json de pe gordas.dev/media-flow-monitor
# cu dist/version-manifest.json — rulat automat de build-macos-app.sh dupa
# fiecare build reusit, ca sa nu mai editam manual site-ul la fiecare bump.
#
# NU face git commit/push singur (ar fi o actiune outward-facing pe alt
# repo) — doar scrie fisierele. Commit-ul/push-ul ramane un pas separat,
# vazut explicit inainte de a fi trimis pe gordas.dev.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_REPO="$ROOT/../gdc-plugin-manager-catalog-vendor"
SITE_DIR="$VENDOR_REPO/docs/media-flow-monitor"
MANIFEST="$ROOT/dist/version-manifest.json"

if [ ! -d "$VENDOR_REPO" ]; then
  echo "→ ⚠️  $VENDOR_REPO nu exista — sar peste sincronizarea site-ului."
  exit 0
fi
if [ ! -f "$MANIFEST" ]; then
  echo "→ ⚠️  $MANIFEST lipseste — rulati intai build-macos-app.sh."
  exit 1
fi

python3 -c "
import json, pathlib, datetime, re

manifest = json.loads(pathlib.Path('$MANIFEST').read_text())
version = manifest['platforms']['macos']['version']
notes = manifest.get('releaseNotes', '')
today = datetime.date.today().isoformat()

# update.json
update_path = pathlib.Path('$SITE_DIR/update.json')
u = json.loads(update_path.read_text())
old_version = u['version']
u['version'] = version
u['release_date'] = today
u['changes'] = notes
update_path.write_text(json.dumps(u, indent=2) + '\n')
print(f'update.json: {old_version} -> {version}')

# index.html — inlocuieste orice badge/footer cu versiunea veche
index_path = pathlib.Path('$SITE_DIR/index.html')
html = index_path.read_text()
html2 = re.sub(re.escape(f'v{old_version}'), f'v{version}', html)
index_path.write_text(html2)
print(f'index.html: v{old_version} -> v{version}' if html2 != html else 'index.html: nicio schimbare (versiune deja sincronizata)')
"

echo "✅ Site sincronizat local in $SITE_DIR — revizuieste diff-ul si fa commit+push manual din $VENDOR_REPO."
