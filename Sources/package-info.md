# Safari native sources

- `SafariApp.swift`: the separate macOS containing app's extension onboarding and non-launching state refresh.
- `SafariHeartbeatGate.swift`: coalesced extension-state queries and stale callback isolation.
- `SafariWebExtensionHandler.swift`: browser-originated bounded heartbeat replies, authenticated proof bootstrap, profile routing and hard rule watchdog.
- `SafariRuntime.swift`: environment boundaries, per-profile durable journals and the canonical JavaScriptCore engine host.
- `SafariFileBroker.swift`: native selected-folder bookmarks and bounded relative text/CSV/JSON operations.
