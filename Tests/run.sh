#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/native-tests"
APP="$OUT/SafariNativeTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/../customBlocker/rule-core.js" "$ROOT/../customBlocker/event-sandbox.js" "$APP/Contents/Resources/"
python3 - "$APP" <<'PY'
import pathlib,plistlib,sys
with (pathlib.Path(sys.argv[1])/'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.adamancia.vault.safari.tests','CFBundleExecutable':'SafariNativeTests',
                  'CFBundlePackageType':'APPL','VaultEnvironment':'development'},f)
PY
xcrun swiftc -D SAFARI_TESTING -sdk "$(xcrun --sdk macosx --show-sdk-path)" -application-extension \
  "$ROOT/Sources/SafariRuntime.swift" "$ROOT/Sources/SafariFileBroker.swift" "$ROOT/Sources/SafariWebExtensionHandler.swift" \
  "$ROOT/Tests/main.swift" -o "$APP/Contents/MacOS/SafariNativeTests"
"$APP/Contents/MacOS/SafariNativeTests"
python3 "$ROOT/Tests/native-process.py" "$APP/Contents/MacOS/SafariNativeTests"
python3 "$ROOT/Tests/profiles.py"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -application-extension -parse-as-library \
  "$ROOT/Sources/SafariHeartbeatGate.swift" "$ROOT/Tests/heartbeat.swift" -o "$OUT/SafariHeartbeatGateTests"
"$OUT/SafariHeartbeatGateTests"

NODE="${SAFARI_VAULT_TEST_NODE:-$(command -v node || true)}"
if [ -z "$NODE" ]; then NODE="$HOME/.local/node-v24.20.0-darwin-x64/bin/node"; fi
"$NODE" "$ROOT/../customBlocker/tests/runner-local-hub-auth.js"
"$NODE" "$ROOT/../customBlocker/tests/runner-local-hub-environment.js"
"$NODE" "$ROOT/../customBlocker/tests/runner-safari-packaging.js"
"$NODE" "$ROOT/../customBlocker/tests/runner-safari-native-lifecycle.js"
