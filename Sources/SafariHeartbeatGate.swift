import Foundation

/// Main-thread extension-state query policy. Background state refresh never
/// dispatches to Safari; only browser-originated native requests drive ticks.
final class SafariHeartbeatGate {
    private(set) var extensionEnabled: Bool?
    private var pendingQuery: (id: Int, started: TimeInterval)?
    private var lastQuery: TimeInterval = -.infinity
    private var nextQuery = 0

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
        }
    }
}
