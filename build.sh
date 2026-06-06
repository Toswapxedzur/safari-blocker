#!/usr/bin/env bash
# safariBlocker — assemble the Safari Web Extension from the shared
# customBlocker source, ready to be wrapped in an Xcode app via
# `xcrun safari-web-extension-converter`.
#
# Pipeline:
#   1. Build the `safari` target with customBlocker/tools/package.py. That
#      produces a package that:
#        - runs default + platform groups entirely in the extension, and
#        - pins CB_SANDBOX_TRANSPORT="native", so custom-rule groups forward
#          their event-sandbox-requests to the macosBlocker app over native
#          messaging (handled by SafariWebExtensionHandler.swift).
#   2. Unpack it into safariBlocker/extension/ (the unsigned web extension).
#   3. Print the converter command to wrap it into a macOS/iOS app.
#
# The native custom-rule engine itself lives in macosBlocker
# (SafariCustomRuleBridge + the verbatim helpers.js / event-sandbox.js in
# MacBlockerCore/Resources). Run sync-engine.sh first if you changed those.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CUSTOM_BLOCKER="$(cd "$ROOT/../customBlocker" && pwd)"
OUT_DIR="$ROOT/extension"

echo "[safariBlocker] building safari web-extension package…"
python3 "$CUSTOM_BLOCKER/tools/package.py" --target safari

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$CUSTOM_BLOCKER/manifest.safari.json")"
ZIP="$CUSTOM_BLOCKER/dist/custom-web-blocker-safari-${VERSION}.zip"

if [ ! -f "$ZIP" ]; then
  echo "[safariBlocker] ERROR: expected package not found: $ZIP" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
unzip -q "$ZIP" -d "$OUT_DIR"

echo "[safariBlocker] unpacked extension -> $OUT_DIR"
echo
echo "Next steps (macOS):"
echo "  1. Wrap the extension in an app:"
echo "       xcrun safari-web-extension-converter \"$OUT_DIR\" \\"
echo "         --project-location \"$ROOT/Xcode\" --macos-only --copy-resources"
echo "  2. In Xcode, add the extension target's SafariWebExtensionHandler:"
echo "       macosBlocker/XcodeScaffold/macosBlockerSafariExtension/SafariWebExtensionHandler.swift"
echo "     and macosBlocker/XcodeScaffold/Shared/AppGroupIdentifier.swift"
echo "  3. Link the extension target against the MacBlockerCore package."
echo "  4. Add the 'nativeMessaging' + App Group entitlements; Developer ID"
echo "     sign + notarize for unofficial (non-App-Store) distribution."
