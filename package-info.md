# safariBlocker — Safari Vault

Read the group `AGENTS.md` and `../misc/project-memory/PROJECT-MEMORY.md` before working here.

- `extension/` is generated from canonical `customBlocker` browser source by `build.sh`; never hand edit it. It includes the same Classifier collectors, tagging UI and Activity feeder as Chrome, plus Safari lifecycle wake messages and an explicit native environment identity.
- `Sources/` holds the separate containing app, native app-extension handler, independent custom-rule runtime, and selected-folder broker. These have no Mac Vault build dependency.
- `scripts/build-app.sh` builds the containing app and `.appex` with Command Line Tools. `run-safari-vault.sh` is the supported development launcher.
- `Tests/` exercises native runtime/state/file security and packaging contracts on mini1. Live enabling and website access remain owner-controlled Safari settings.
- `build.sh` regenerates production assets by default; `--environment development` produces an isolated native development environment. The standalone native build embeds both custom-rule engine files directly from canonical browser source.
- `README.md` explains build, onboarding, independent rules, authentication, and verification limits.
- Public version follows `customBlocker/manifest.safari.json`; no release version bump is implied by this port.

Shared editor assets preserve current accepted translations, growing scrollable lists, per-group `v.log` logs, floating menus, and localized Info explanations for the fixed20 app languages. Custom-rule engine errors remain developer diagnostics rather than rule logs.

- `Assets/Branding/`: selected Safari 05 compass vector, native ICNS/master, and browser aliases. `build.sh` overlays these after generating shared assets; the native build embeds SafariVault.icns.

- `VERSIONS.md`: owner-approved 2026-10-04 capability split; current source version **3.1.5 alpha**. Historical tags/packages remain immutable.

- Public customer audit on owner-selected mini2 reproduces and verifies website recording off-to-on transitions. Generated feeder regression lives in canonical `customBlocker/tests/runner-activity-resume.js`.

- Public customer-audit patch 3.1.2 mirrors the dedicated Bilibili home-card author-name selector and preserves native authentication/permissions.

- First-link recovery uses the canonical serialized contribution-before-adoption browser path. Generated `extension/background.js` preserves original Website entries and policy until the hub accepts the first contribution, including reconnects. Native hub changes are delivered by Mac Vault or Windows Vault separately; Store/public publication remains held.

- Runtime custom-rule AI uses the canonical `rule-ai-client.js` preload and `rule-ai-ui.js` controls. Browser requests route through connected Mac Vault; the independent Safari JSC runtime emits generic AI actions and receives generation-bound AI events. `Tests/main.swift` covers an AI-driven cover, Run and cold-restart rejection. Generated production assets and the private development app build were checked on owner-selected Mini2 without replacing the public Safari app. New English text awaits the normal pre-release translation batch.

- Saved clickable content pills use canonical `content-items.js` and `rule-attachments.js`. Browser storage owns group-private records; Safari JSC emits attachment intents and receives click events. Mini2 native/process/packaging checks and private development build pass; actual pointer/restart UI evidence comes from isolated Chromium using the shared source. Public Safari is preserved.

- Generic record actions and passive HTML/CSS attachment intents use canonical browser source. `Tests/main.swift` exercises the native JSC action/reply contract; generated `extension/` mirrors the manifest's new content-view and record modules. The public Safari app stays in place.
