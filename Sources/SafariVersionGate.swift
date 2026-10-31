import Foundation

enum SafariVersionGate {
    static let minimumVersion = "18.4"

    static func supportsDeveloperIDExtensions(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return false }
        return major > 18 || (major == 18 && minor >= 4)
    }
}
