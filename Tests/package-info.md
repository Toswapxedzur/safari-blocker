# Safari verification

- `run.sh`: builds a disposable native harness on mini1, then runs runtime/file and process-isolation checks.
- `main.swift`: actual native handler harness and JavaScriptCore/journal/folder contract checks. The test-directory override is compiled only with `SAFARI_TESTING` and excluded from the shipping handler.
- `native-process.py`: cold handler process rehydration, infinite-loop native watchdog, sibling recovery, quarantine, and profile boundaries.
- `profiles.py`: rejects invalid signing profile metadata using account-free fixtures; does not claim a signed runtime test.
- `native-language.py` / `native-language.swift`: exercise the shipping native loader in all 20 languages and an unsupported-locale fallback, without opening a window or browser.
- `heartbeat.swift`: disabled/re-enabled extension and closed/reopened browser heartbeat generations, query errors and stale callback isolation.
