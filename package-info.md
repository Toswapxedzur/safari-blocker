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

- `VERSIONS.md`: owner-approved 2026-10-04 capability split; current source version **3.1.4 alpha**. Historical tags/packages remain immutable.

- Public customer audit on owner-selected mini2 reproduces and verifies website recording off-to-on transitions. Generated feeder regression lives in canonical `customBlocker/tests/runner-activity-resume.js`.

- Public customer-audit patch 3.1.2 mirrors the dedicated Bilibili home-card author-name selector and preserves native authentication/permissions.
