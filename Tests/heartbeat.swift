import Foundation

@main
struct SafariHeartbeatTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            if condition { print("PASS \(label)") }
            else { failures += 1; print("FAIL \(label)") }
        }
        let gate = SafariHeartbeatGate()
        check(gate.beginDispatch(safariRunning: false) == nil, "closed Safari never gets a heartbeat")
        let query = gate.beginStateQuery(now: 0)!
        let first = gate.beginDispatch(safariRunning: true)!
        check(gate.isActive(safariRunning: true), "unknown state preserves active runtime while query is pending")
        check(gate.beginDispatch(safariRunning: true) == nil, "native dispatches never overlap")
        gate.completeStateQuery(query, enabled: false)
        check(!gate.isActive(safariRunning: true) && gate.beginDispatch(safariRunning: true) == nil, "known-disabled state stops heartbeat and activity")
        let reenabledQuery = gate.beginStateQuery(now: 1, force: true)!
        check(gate.beginStateQuery(now: 2, force: true) == nil, "state queries do not overlap while fresh")
        gate.completeStateQuery(reenabledQuery, enabled: true)
        let second = gate.beginDispatch(safariRunning: true)!
        gate.completeDispatch(first)
        check(gate.beginDispatch(safariRunning: true) == nil, "stale disabled-session reply cannot clear a reenabled dispatch")
        gate.completeDispatch(second)
        check(gate.beginDispatch(safariRunning: true) != nil, "reenabling resumes native heartbeat")
        _ = gate.beginDispatch(safariRunning: false)
        check(gate.beginDispatch(safariRunning: true) != nil, "browser restart clears a stalled previous-session dispatch")
        let stalledQuery = gate.beginStateQuery(now: 20)!
        let recoveredQuery = gate.beginStateQuery(now: 26, force: true)!
        gate.completeStateQuery(stalledQuery, enabled: false)
        check(gate.extensionEnabled == true, "stale query cannot disable a newer browser session")
        gate.completeStateQuery(recoveredQuery, enabled: nil)
        check(gate.extensionEnabled == true, "unavailable state query preserves last authorized state")
        let disable = gate.beginStateQuery(now: 27, force: true)!
        gate.completeStateQuery(disable, enabled: false)
        let unavailable = gate.beginStateQuery(now: 28, force: true)!
        gate.completeStateQuery(unavailable, enabled: nil)
        check(gate.extensionEnabled == false, "query error cannot reenable a known-disabled extension")
        print("SAFARI_HEARTBEAT_RESULT: \(failures == 0 ? "OK" : "FAIL") (\(failures) failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
