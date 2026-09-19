# safariBlocker — Safari Vault (Safari repackaging of customBlocker)

> 🤖 **AI protocol:** Read `../package-info.md` (group), the group `AGENTS.md`, and `../misc/project-memory/PROJECT-MEMORY.md` before working here. Update this file when the folder changes. Never delete without owner consent; keep secrets out of git.

- **What:** the Safari front of the extension (public name **Safari Vault**). Not a re-implementation: `extension/` is a **generated unpack** of customBlocker's `safari` package target. Custom-rule groups are forwarded over native messaging to Mac Vault, which runs the verbatim engine in JavaScriptCore.
- **Own git repo:** `Toswapxedzur/safari-blocker`, branch `main`; version = `customBlocker/manifest.safari.json` (2.4.0); tags mirror the extension version each rebuild was made from.
- **Scripts:** `sync-engine.sh` copies `helpers.js` + `event-sandbox.js` into macosBlocker Resources; `build.sh` runs `customBlocker/tools/package.py --target safari` and regenerates `extension/`, then prints the `safari-web-extension-converter` wrapping steps. Rerun both whenever customBlocker changes; never hand-edit `extension/`.
- **No automated tests** here; the engine is covered by customBlocker's suite and macosBlocker's Swift tests.
