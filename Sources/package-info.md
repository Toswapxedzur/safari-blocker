# Safari native sources

- `SafariApp.swift`: the separate macOS containing app's extension onboarding and native heartbeat.
- `SafariHeartbeatGate.swift`: state/dispatch generations and known-disabled resource cleanup for the heartbeat.
- `SafariWebExtensionHandler.swift`: authenticated proof bootstrap, profile routing and hard rule watchdog.
- `SafariRuntime.swift`: environment boundaries, per-profile durable journals and the canonical JavaScriptCore engine host.
- `SafariFileBroker.swift`: native selected-folder bookmarks and bounded relative text/CSV/JSON operations.
