#!/usr/bin/env bash
# Build the containing app and native handler directly with Apple's SDK. This
# works with Command Line Tools and avoids requiring a generated Xcode project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENVIRONMENT="${SAFARI_VAULT_ENVIRONMENT:-development}"
IDENTITY="${SAFARI_VAULT_SIGNING_IDENTITY:--}"
ARCH="${SAFARI_VAULT_ARCH:-$(uname -m)}"
case "$ENVIRONMENT" in production|development) ;; *) echo "Invalid Safari environment" >&2; exit 2;; esac
if [ "$ENVIRONMENT" = production ] && [ "$IDENTITY" = - ]; then
  echo "Production Safari app requires an explicit Apple signing identity; use development for ad-hoc testing." >&2
  exit 2
fi
case "$ARCH" in x86_64|arm64|universal) ;; *) echo "Invalid Safari architecture" >&2; exit 2;; esac
EXTENSION="${SAFARI_VAULT_EXTENSION_SOURCE:-$ROOT/extension}"
OUT="${SAFARI_VAULT_BUILD_DIRECTORY:-$ROOT/.build/safari-$ENVIRONMENT}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SUFFIX=""; NAME="Safari Vault"
if [ "$ENVIRONMENT" = development ]; then SUFFIX=".development"; NAME="Safari Vault Development"; fi
BUNDLE="com.adamancia.vault.safari$SUFFIX"
GROUP="group.com.adamancia.vault$SUFFIX"
APP_PROFILE="${SAFARI_VAULT_APP_PROVISIONING_PROFILE:-}"
EXTENSION_PROFILE="${SAFARI_VAULT_EXTENSION_PROVISIONING_PROFILE:-}"
if [ "$IDENTITY" != - ] && { [ -z "$APP_PROFILE" ] || [ -z "$EXTENSION_PROFILE" ]; }; then
  echo "Signed Safari App Group builds require app and extension provisioning profiles." >&2
  exit 2
fi
APP="$OUT/$NAME.app"
APPEX="$APP/Contents/PlugIns/SafariVaultExtension.appex"
if [ ! -f "$EXTENSION/manifest.json" ]; then echo "Generate Safari assets first: ./build.sh --environment $ENVIRONMENT" >&2; exit 1; fi
python3 - "$EXTENSION" "$ENVIRONMENT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]); environment=sys.argv[2]
config=(root/'safari-runtime-config.js').read_text()
if '"environment": "'+environment+'"' not in config:
    raise SystemExit('Safari browser/native environments differ; regenerate assets with the requested environment.')
PY
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp -R "$EXTENSION/." "$APPEX/Contents/Resources/"
# These remain exact copies of the canonical custom-rule engine.
cp "$ROOT/../customBlocker/rule-core.js" "$ROOT/../customBlocker/event-sandbox.js" "$APPEX/Contents/Resources/"
python3 - "$APP" "$APPEX" "$BUNDLE" "$GROUP" "$ENVIRONMENT" "$NAME" <<'PY'
import json, pathlib, plistlib, sys
app,appex,bundle,group,environment,name=sys.argv[1:]
version=json.loads((pathlib.Path(appex)/'Contents/Resources/manifest.json').read_text())['version']
base={'CFBundleInfoDictionaryVersion':'6.0','CFBundleShortVersionString':version,'CFBundleVersion':version,
      'LSMinimumSystemVersion':'13.0','VaultEnvironment':environment}
a=dict(base,CFBundleIdentifier=bundle,CFBundleName=name,CFBundleDisplayName=name,CFBundleExecutable='SafariVault',
       CFBundlePackageType='APPL',NSPrincipalClass='NSApplication',VaultExtensionIdentifier=bundle+'.extension')
e=dict(base,CFBundleIdentifier=bundle+'.extension',CFBundleName='Safari Vault Extension',CFBundleExecutable='SafariVaultExtension',
       CFBundlePackageType='XPC!',NSExtension={'NSExtensionPointIdentifier':'com.apple.Safari.web-extension',
                                           'NSExtensionPrincipalClass':'SafariWebExtensionHandler'})
# NSOpenPanel yields only the user-selected security-scoped folder. The handler
# needs loopback client access to connect the authenticated desktop hub.
entitlements={'com.apple.security.app-sandbox':True,'com.apple.security.application-groups':[group],
              'com.apple.security.network.client':True,'com.apple.security.files.user-selected.read-write':True,
              'com.apple.security.files.bookmarks.app-scope':True}
for path,value in [(pathlib.Path(app)/'Contents/Info.plist',a),(pathlib.Path(appex)/'Contents/Info.plist',e),
                   (pathlib.Path(app).parent/'SafariVault.entitlements',entitlements)]:
    with path.open('wb') as f: plistlib.dump(value,f)
PY
ARCHES=("$ARCH")
if [ "$ARCH" = universal ]; then ARCHES=(x86_64 arm64); fi
for BUILD_ARCH in "${ARCHES[@]}"; do
  xcrun swiftc -sdk "$SDK" -target "$BUILD_ARCH-apple-macos13.0" -O \
    -module-name SafariVault "$ROOT/Sources/SafariApp.swift" -o "$OUT/SafariVault-$BUILD_ARCH"
  xcrun swiftc -sdk "$SDK" -target "$BUILD_ARCH-apple-macos13.0" -O -application-extension \
    -parse-as-library -module-name SafariVaultExtension \
    "$ROOT/Sources/SafariRuntime.swift" "$ROOT/Sources/SafariFileBroker.swift" "$ROOT/Sources/SafariWebExtensionHandler.swift" \
    -Xlinker -e -Xlinker _NSExtensionMain -o "$OUT/SafariVaultExtension-$BUILD_ARCH"
done
if [ "$ARCH" = universal ]; then
  xcrun lipo -create "$OUT/SafariVault-x86_64" "$OUT/SafariVault-arm64" -output "$APP/Contents/MacOS/SafariVault"
  xcrun lipo -create "$OUT/SafariVaultExtension-x86_64" "$OUT/SafariVaultExtension-arm64" -output "$APPEX/Contents/MacOS/SafariVaultExtension"
else
  cp "$OUT/SafariVault-$ARCH" "$APP/Contents/MacOS/SafariVault"
  cp "$OUT/SafariVaultExtension-$ARCH" "$APPEX/Contents/MacOS/SafariVaultExtension"
fi
APP_ENTITLEMENTS="$OUT/SafariVault.entitlements"
EXTENSION_ENTITLEMENTS="$OUT/SafariVault.entitlements"
if [ "$IDENTITY" != - ]; then
  python3 "$ROOT/scripts/embed-profiles.py" "$APP" "$APPEX" "$GROUP" "$APP_PROFILE" "$EXTENSION_PROFILE"
  APP_ENTITLEMENTS="$OUT/$NAME.app.entitlements"
  EXTENSION_ENTITLEMENTS="$OUT/SafariVaultExtension.appex.entitlements"
fi
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" != - ]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
codesign "${SIGN_FLAGS[@]}" --entitlements "$EXTENSION_ENTITLEMENTS" "$APPEX"
codesign "${SIGN_FLAGS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
if [ "$IDENTITY" != - ]; then
  python3 "$ROOT/scripts/embed-profiles.py" --verify "$APP" "$APPEX" "$GROUP" "$APP_PROFILE" "$EXTENSION_PROFILE"
fi
# Ad-hoc outputs are development-only. Production distribution uses an explicit
# Developer ID/App Store identity and the standard Apple notarization workflow.
printf '%s\n' "$APP"
