# Safari Vault

Safari Vault is the macOS Safari front of Adamancia Vault. Its small containing app is separate from Mac Vault. Website blocking, platform controls, schedules, snoozes and custom rules work without Mac Vault running. Tagging, shared groups and Activity connect to Mac Vault through the same authenticated protocol as Chrome.

The shared browser source lives in `../customBlocker`. `extension/` is generated; edit the canonical source and regenerate it instead of editing the copies.

## Build

All product testing and build verification run on mini1. Apple Command Line Tools with the macOS SDK are sufficient; the Safari extension converter and an Xcode project are not required.

```sh
./build.sh --environment development
SAFARI_VAULT_ENVIRONMENT=development ./scripts/build-app.sh
./run-safari-vault.sh
```

The native script creates a separate `Safari Vault Development.app` containing `SafariVaultExtension.appex`, compiles both with macOS 13 as the deployment target, and signs the complete bundle. The default architecture is the build host's architecture; use `SAFARI_VAULT_ARCH=universal` for Intel and Apple silicon binaries. A compiled architecture is not a substitute for testing it on matching hardware.

A production build uses `./build.sh --environment production` and `SAFARI_VAULT_ENVIRONMENT=production`. Set `SAFARI_VAULT_SIGNING_IDENTITY` to the appropriate Apple signing identity and provide `SAFARI_VAULT_APP_PROVISIONING_PROFILE` and `SAFARI_VAULT_EXTENSION_PROVISIONING_PROFILE`. Both profiles must authorize their bundle IDs and the shared Vault App Group under the same developer team. The script validates and embeds them without logging their private contents. Then use Apple's normal notarization or App Store submission process. Production builds reject ad-hoc signing.

An ad-hoc build verifies compilation and bundle structure, but is not a signed release. Safari's owner-controlled unsigned-extension development setting is required for browser loading, and valid Apple provisioning remains required for App Group access. On mini1, no Apple signing identity/profile is installed; a rebuilt ad-hoc sandboxed containing app stalled in macOS sandbox initialization. Native runtime harness tests do not prove successful App Group provisioning or live Safari activation.

## Enable

Run the containing app once, click **Open Safari Extensions**, enable Safari Vault, and allow access to **all websites**. Safari owns these permission settings. The app explains the grant but does not change the user's security settings.

The native app extension handles custom rules independently of Mac Vault. Closing the containing app window keeps its small heartbeat helper running in the background. The extension starts that helper through Launch Services when connecting its native port. It runs the exact `rule-core.js` and `event-sandbox.js` code in JavaScriptCore. The rule engine has no direct network, DOM, timer or file API. A native watchdog confines an infinite rule to the native handler process, quarantines its group and lets Safari recreate the handler. Other groups recover from a local journal of source and JSON memory. Safari profiles and web apps have separate journals and folder grants.

Safari has no Chromium folder picker. The Settings folder button opens a native folder picker and retains only the selected security-scoped bookmark. Custom rules can use relative text, CSV and JSON paths in that folder, with the same one-MiB limit as Chromium. Traversal, absolute paths, unsupported files and symlinks are refused; revoking the grant removes the bookmark.

## Mac connection

Safari's opaque extension runtime ID does not select a production or development host. Packaging embeds its environment explicitly and the native handler verifies it independently. Mac Vault publishes its existing local hub secret into the entitled App Group. Safari's native handler answers a fresh protocol-4 challenge with a proof; browser JavaScript never receives the secret. No Mac Vault connection is required for ordinary website enforcement or custom rules.

Classifier collectors and tag controls are generated from the same Chrome adapters. Their collection and Activity settings remain opt-in. Disconnection uses the existing Chrome pending-tag and reconnection behavior, including the user's cover-until-tagged setting.

Safari can suspend an MV3 background page. The separate containing app wakes it every second through Safari's native messaging port, so timer and file rules keep running even with no visible page. It sends pulses only while Safari is already running; quitting Safari does not cause it to reopen. Granted visible pages also wake the background and reconnect the authenticated hub. Schedule transition alarms and navigation handlers restore enforcement after suspension. These wake messages carry no rendered evidence or browsing data.

## Verification

Run `./Tests/run.sh` from a source export on mini1. It compiles the native handler with application-extension restrictions, exercises real JavaScriptCore execution and state recovery, validates native file limits, traversal and symlink refusal, and runs packaged browser/native identity checks. Live Safari verification additionally requires the owner to enable the extension and all-website access. Do not treat native tests or Chrome fixture tests as a completed live Safari run.
