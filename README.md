# safariBlocker

The Safari front for `customBlocker`. It is **not** a re-implementation: it is
the same shared web extension source, packaged for Safari, wrapped in a native
app.

Safari splits the responsibility:

- **Default + platform groups** run entirely in the extension — native URL
  blocking via `declarativeNetRequest`, and per-platform feed hiding / overlays
  via the content scripts. No native dependency.
- **Custom (JavaScript) groups** run as a **thin client**. Safari has no
  `chrome.offscreen`, and its support for the eval-relaxing manifest `sandbox`
  key is unreliable, so the extension forwards each custom-rule
  `event-sandbox-request` to the **macosBlocker** app over native messaging.
  The app runs the *verbatim* engine (`helpers.js` + `event-sandbox.js`) in
  JavaScriptCore — which has no CSP, so `new Function` just works — and returns
  the same result the in-browser sandbox would, including DOM/redirect intents
  that the content script then applies.

```text
Safari content script ──► Safari background (CB_SANDBOX_TRANSPORT="native")
                              │  custom groups only
                              ▼  browser.runtime.sendNativeMessage
                       macosBlocker app extension
                       SafariWebExtensionHandler.swift
                              │
                              ▼
                       SafariCustomRuleBridge (MacBlockerCore)
                       JavaScriptCore + helpers.js + event-sandbox.js
                              │  { ok, result: { …, intents } }
                              ▼
                       reply ──► content script applies intents
```

## How the pieces map across the repo

| Piece | Location |
| --- | --- |
| Shared web source | `customBlocker/` |
| Safari manifest (no offscreen/sandbox, `nativeMessaging`) | `customBlocker/manifest.safari.json` |
| Native transport switch in the background | `customBlocker/background.js` (`sandboxTransportMode()` → `"native"`) |
| Cross-engine API bridge | `customBlocker/browser-compat.js` |
| Packaging (`--target safari`) | `customBlocker/tools/package.py` |
| Native message endpoint | `macosBlocker/XcodeScaffold/macosBlockerSafariExtension/SafariWebExtensionHandler.swift` |
| Native engine host (JSC) | `macosBlocker/Sources/MacBlockerCore/SafariCustomRuleBridge.swift` |
| Verbatim engine resources | `macosBlocker/Sources/MacBlockerCore/Resources/{helpers,event-sandbox}.js` |

## Build

```bash
./sync-engine.sh   # only if helpers.js / event-sandbox.js changed in customBlocker
./build.sh         # packages the safari target and unpacks it into ./extension
```

Then wrap and sign in Xcode — `build.sh` prints the exact
`safari-web-extension-converter` command and the target-wiring steps.

## Distribution

For an unofficial (non-App-Store) build: Developer ID sign + notarize the
container app (notarization is an automated malware scan, **not** App Store
review, so it does not gate the custom-rule engine). The simplest packaging is
to make **macosBlocker** itself the container app, so the system-layer blocker
and the Safari extension ship as one notarized, self-updating product sharing
one App Group.

## What does not survive on Safari

- The **local-folder** helper (File System Access API) — browser-only; returns
  `local-folder-not-available` in native mode.
- iOS Safari background persistence is weak; treat scheduled enforcement there
  as best-effort. For real system-wide enforcement on Apple devices, use
  macosBlocker's Screen Time path, not the Safari extension.
