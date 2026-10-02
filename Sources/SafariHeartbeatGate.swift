import Foundation

/// Main-thread heartbeat policy. Unknown extension state keeps the current
/// runtime alive; a confirmed disabled extension releases it. Generation IDs
/// keep replies from an old browser session from completing a newer dispatch.
final class SafariHeartbeatGate {
    private(set) var extensionEnabled: Bool?
    private var pendingDispatch: Int?
    private var nextDispatch = 0
    private var pendingQuery: (id: Int, started: TimeInterval)?
    private var lastQuery: TimeInterval = -.infinity
    private var nextQuery = 0

    func isActive(safariRunning: Bool) -> Bool { safariRunning && extensionEnabled != false }

    func beginDispatch(safariRunning: Bool) -> Int? {
        if !safariRunning { pendingDispatch = nil }
        guard isActive(safariRunning: safariRunning), pendingDispatch == nil else { return nil }
        nextDispatch &+= 1
        pendingDispatch = nextDispatch
        return nextDispatch
    }
    func completeDispatch(_ id: Int) {
        if pendingDispatch == id { pendingDispatch = nil }
    }
    func beginStateQuery(now: TimeInterval, force: Bool = false) -> Int? {
        if let pendingQuery, now - pendingQuery.started < 5 { return nil }
        guard force || now - lastQuery >= 10 else { return nil }
        nextQuery &+= 1
        pendingQuery = (nextQuery, now)
        lastQuery = now
        return nextQuery
    }
    func completeStateQuery(_ id: Int, enabled: Bool?) {
        guard pendingQuery?.id == id else { return }
        pendingQuery = nil
        if let enabled {
            extensionEnabled = enabled
            if !enabled { pendingDispatch = nil }
        }
    }
}
