# Safari native sources

- `SafariApp.swift`: the separate macOS containing app's extension onboarding, Safari minimum-version notice, non-launching state refresh, and opt-in Sparkle update settings.
- `SafariVersionGate.swift`: Safari 18.4 minimum for loading direct-download Developer ID web extensions.
- `SafariHeartbeatGate.swift`: coalesced extension-state queries and stale callback isolation.
- `SafariWebExtensionHandler.swift`: browser-originated bounded heartbeat replies, authenticated proof bootstrap, profile routing and hard rule watchdog.
- `SafariRuntime.swift`: environment boundaries, per-profile durable journals and the canonical JavaScriptCore engine host.
- `SafariFileBroker.swift`: native selected-folder bookmarks and bounded relative text/CSV/JSON operations.
