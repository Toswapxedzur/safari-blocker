# Safari verification

- `run.sh`: builds a disposable native harness on mini1, then runs runtime/file and process-isolation checks.
- `main.swift`: actual native handler harness and JavaScriptCore/journal/folder contract checks. The test-directory override is compiled only with `SAFARI_TESTING` and excluded from the shipping handler.
- `native-process.py`: bounded browser-originated heartbeat replies without journal writes, cold handler process rehydration, infinite-loop native watchdog, sibling recovery, quarantine, profile boundaries, and rejection of browser-supplied Activity authority/provenance.
- `profiles.py`: rejects invalid signing profile metadata using account-free fixtures; does not claim a signed runtime test.
- `native-language.py` / `native-language.swift`: exercise the shipping native loader in all 20 languages and an unsupported-locale fallback, without opening a window or browser.
- `heartbeat.swift`: disabled/re-enabled extension-state queries, coalescing, query errors and stale callback isolation.
- `safari-version.swift`: Safari 18.4 minimum for Developer ID extensions, including older, missing and newer version strings.
- `bridge-origin.js`: actual generated background socket source preserves native-hub provenance, rejects an obsolete connection, and refuses classifier-origin Activity authority. These inert socket fixtures do not prove an authenticated native provider or live Safari acceptance.

- `main.swift` also verifies managed timer panels/completion, website usage and shared fail-closed journal restart in the actual Safari JavaScriptCore adapter.
- `main.swift` also checks generic HTML/CSS attachment intent, user-origin control events, record action forwarding and active reply delivery through the Safari JavaScriptCore adapter.
