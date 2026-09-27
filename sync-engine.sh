#!/usr/bin/env bash
# Keep the native custom-rule engine in sync with the browser source.
#
# Safari runs custom rules natively (JavaScriptCore) instead of in an
# offscreen sandbox, but it runs the SAME, verbatim engine: rule-core.js +
# event-sandbox.js. Those files are copied into macosBlocker so the Swift
# bridge (SafariCustomRuleBridge) can bundle them. This script refreshes
# those copies from the canonical customBlocker source (macosBlocker's
# sync-webui.sh copies them too).
#
# Run it whenever rule-core.js or event-sandbox.js change in customBlocker.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$ROOT/../customBlocker" && pwd)"
DST="$(cd "$ROOT/../macosBlocker/Sources/MacBlockerCore/Resources" && pwd)"

for f in rule-core.js event-sandbox.js; do
  cp "$SRC/$f" "$DST/$f"
  echo "[sync-engine] $f -> macosBlocker/Sources/MacBlockerCore/Resources/$f"
done

echo "[sync-engine] done. Rebuild macosBlocker (swift build) to pick up changes."
