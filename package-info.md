# safariBlocker — Safari Vault

Read the group `AGENTS.md` and `../misc/project-memory/PROJECT-MEMORY.md` before working here.

- `extension/` is generated from canonical `customBlocker` browser source by `build.sh`; never hand edit it. It includes the same Classifier collectors, tagging UI and Activity feeder as Chrome, plus Safari lifecycle wake messages and an explicit native environment identity.
- `Sources/` holds the separate containing app, native app-extension handler, independent custom-rule runtime, and selected-folder broker. These have no Mac Vault build dependency.
- `scripts/build-app.sh` builds the containing app and `.appex` with Command Line Tools. `run-safari-vault.sh` is the supported development launcher.
- `Tests/` exercises native runtime/state/file security and packaging contracts on mini1. Live enabling and website access remain owner-controlled Safari settings.
- `build.sh` regenerates production assets by default; `--environment development` produces an isolated native development environment. `sync-engine.sh` is the existing Mac engine-copy helper for shared Mac source generation.
- `README.md` explains build, onboarding, independent rules, authentication, and verification limits.
- Public version follows `customBlocker/manifest.safari.json`; no release version bump is implied by this port.

Shared editor assets preserve current accepted translations, growing scrollable lists, per-group `v.log` logs, floating menus, and compact English Info explanations. Custom-rule engine errors remain developer diagnostics rather than rule logs.
