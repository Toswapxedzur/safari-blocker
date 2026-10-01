# safariBlocker — Safari Vault (Safari repackaging of customBlocker)

> 🤖 **AI protocol:** Read `../package-info.md` (group), the group `AGENTS.md`, and `../misc/project-memory/PROJECT-MEMORY.md` before working here. Update this file when the folder changes. Never delete without owner consent; keep secrets out of git.

- **Growing editor lists (owner 2026-10-01):** regenerated from the shared bounded-list UI. Navigation, sites/apps, creator filters and tag suggestions stay inside scroll containers; no entries are truncated.

- **Custom-rule logs (owner 2026-10-01):** the Log panel contains only `v.log()` output, independently retained by immutable group ID (200 entries per rule). Clear and Download operate on the selected rule. Engine errors and collection/transport diagnostics stay in developer diagnostics. Browser feed tests: `customBlocker/tests/runner-rule-log-isolation.js`; native persistence tests: `macosBlocker/Tests/RuleLogShim.test.js`.

- **What:** the Safari front of the extension (public name **Safari Vault**). Not a re-implementation: `extension/` is a **generated unpack** of customBlocker's `safari` package target. Custom-rule groups are forwarded over native messaging to Mac Vault, which runs the verbatim engine in JavaScriptCore.
- **Own git repo:** `Toswapxedzur/safari-blocker`, branch `main`; version = `customBlocker/manifest.safari.json` (2.4.0); tags mirror the extension version each rebuild was made from.
- **Scripts:** `sync-engine.sh` copies `rule-core.js` + `event-sandbox.js` into macosBlocker Resources (macosBlocker's `sync-webui.sh` copies them too); `build.sh` runs `customBlocker/tools/package.py --target safari` and regenerates `extension/`, then prints the `safari-web-extension-converter` wrapping steps. Rerun both whenever customBlocker changes; never hand-edit `extension/`.
- **No automated tests** here; the engine is covered by customBlocker's suite and macosBlocker's Swift tests.

- **English preparation (2026-10-01):** Generated editor is refreshed from the accepted shared browser code, including English terminology and the current custom-rule manual. No hand edits to extension/.
