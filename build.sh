#!/usr/bin/env bash
# Assemble canonical browser assets; native packaging lives in scripts/build-app.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CUSTOM_BLOCKER="$(cd "$ROOT/../customBlocker" && pwd)"
ENVIRONMENT=production
if [ "${1:-}" = --environment ]; then ENVIRONMENT="${2:-}"; shift 2; fi
if [ "$#" -ne 0 ]; then echo "Usage: ./build.sh [--environment production|development]" >&2; exit 2; fi
case "$ENVIRONMENT" in production|development) ;; *) echo "Invalid Safari environment" >&2; exit 2;; esac
python3 "$CUSTOM_BLOCKER/tools/package.py" --target safari --environment "$ENVIRONMENT"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$CUSTOM_BLOCKER/manifest.safari.json")"
ZIP="$CUSTOM_BLOCKER/dist/AdamanciaVault-extension-safari-v${VERSION}.zip"
OUT_DIR="$ROOT/extension"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
unzip -q "$ZIP" -d "$OUT_DIR"
# Platform branding stays local even when shared browser code is regenerated.
cp "$ROOT/Assets/Branding/BrowserIcons/"*.{png,svg} "$OUT_DIR/icons/"
echo "[safariBlocker] generated $ENVIRONMENT browser assets -> $OUT_DIR"
echo "Build the separate containing app: SAFARI_VAULT_ENVIRONMENT=$ENVIRONMENT ./scripts/build-app.sh"
