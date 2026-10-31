import Foundation

@main
struct SafariVersionGateTests {
    static func main() {
        let cases: [(String?, Bool)] = [
            (nil, false), ("", false), ("17.2.1", false), ("18.3", false),
            ("18.4", true), ("18.4.1", true), ("18.6", true), ("26.0", true),
            ("18", false), ("18.4beta", false)
        ]
        for (version, expected) in cases {
            precondition(SafariVersionGate.supportsDeveloperIDExtensions(version) == expected,
                         "unexpected result for \(version ?? "missing")")
        }
        print("Safari version gate: \(cases.count) cases passed")
    }
}
