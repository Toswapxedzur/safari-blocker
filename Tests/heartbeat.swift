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
        let query = gate.beginStateQuery(now: 0)!
        check(gate.beginStateQuery(now: 1, force: true) == nil, "state queries do not overlap while fresh")
        gate.completeStateQuery(query, enabled: false)
        check(gate.extensionEnabled == false, "disabled state is retained")
        let reenabledQuery = gate.beginStateQuery(now: 1, force: true)!
        gate.completeStateQuery(reenabledQuery, enabled: true)
        check(gate.extensionEnabled == true, "explicit refresh observes reenabled extension")
        check(gate.beginStateQuery(now: 5) == nil, "background state refresh is coalesced")
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
