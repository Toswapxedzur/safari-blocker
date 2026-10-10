import Foundation
import CryptoKit
import JavaScriptCore

/// Packaging chooses an environment explicitly; browser messages cannot switch
/// the native handler's port, App Group or authentication material.
enum SafariConfiguration {
    static var environment: String {
        Bundle.main.object(forInfoDictionaryKey: "VaultEnvironment") as? String == "development"
            ? "development" : "production"
    }
    static var appGroup: String {
        "group.com.adamancia.vault" + (environment == "development" ? ".development" : "")
    }
    static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
    static var ruleDirectory: URL {
        #if SAFARI_TESTING
        if let directory = ProcessInfo.processInfo.environment["SAFARI_TEST_DIRECTORY"] {
            return URL(fileURLWithPath: directory, isDirectory: true)
        }
        #endif
        let root = sharedContainer ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("SafariVault-" + environment, isDirectory: true)
    }
    static func profileKey(_ profile: String) -> String {
        SHA256.hash(data: Data(profile.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func proof(message: [String: Any]) -> [String: Any] {
        guard message["v"] as? Int == 4, message["program"] as? String == "safari",
              let challenge = message["challenge"] as? String,
              challenge.utf8.count == 43, challenge.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let container = sharedContainer,
              let secret = try? Data(contentsOf: container.appendingPathComponent("safari-local-hub-secret-v4")),
              secret.count == 32 else {
            return ["ok": false, "error": "Local Vault authentication is unavailable.", "environment": environment]
        }
        let canonical = "vault-local-hub-v4\nprogram=safari\nchallenge=\(challenge)"
        let proof = Data(HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: SymmetricKey(data: secret)))
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return ["ok": true, "proof": proof, "environment": environment]
    }
}

/// Sources and JSON memory survive Safari's native-handler process being
/// reclaimed. Each Safari profile/web app has its own journal and folder grant.
final class SafariRuleJournal {
    let url: URL
    private(set) var groups: [String: [String: Any]] = [:]
    private(set) var quarantine: [String: String] = [:]
    private var quarantinedSources: [String: String] = [:]

    init(directory: URL, profile: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        url = directory.appendingPathComponent("rules-" + SafariConfiguration.profileKey(profile) + ".json")
        if let data = try? Data(contentsOf: url), data.count <= 16 * 1024 * 1024,
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           value["version"] as? Int == 1 {
            groups = value["groups"] as? [String: [String: Any]] ?? [:]
            quarantine = value["quarantine"] as? [String: String] ?? [:]
            quarantinedSources = value["quarantinedSources"] as? [String: String] ?? [:]
            // A malformed old journal is a bounded crash guard, never code.
            groups = groups.filter { !$0.key.isEmpty && $0.key.utf8.count <= 256 && (($0.value["source"] as? String)?.utf8.count ?? Int.max) <= 4 * 1024 * 1024 }
        }
    }
    private let lock = NSRecursiveLock()
    /// Browser storage is authoritative. A killed background or storage reset
    /// may have missed its unload message; never restore those stale sources.
    func reconcile(_ groupIDs: Set<String>) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        let retained = Set(groups.keys).union(quarantine.keys).union(quarantinedSources.keys)
        let removed = retained.subtracting(groupIDs)
        guard !removed.isEmpty else { return [] }
        for group in removed {
            groups.removeValue(forKey: group)
            quarantine.removeValue(forKey: group)
            quarantinedSources.removeValue(forKey: group)
        }
        try save()
        return removed.sorted()
    }
    func commit(payload: [String: Any], result: [String: Any]) throws {
        lock.lock(); defer { lock.unlock() }
        let oldGroups = groups
        let oldQuarantine = quarantine
        let oldSources = quarantinedSources
        do {
            let kind = payload["kind"] as? String ?? ""
            if let group = payload["groupId"] as? String, !group.isEmpty, group.utf8.count <= 256 {
                if kind == "load-source", result["ok"] as? Bool == true {
                    let source = payload["source"] as? String ?? ""
                    if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { groups.removeValue(forKey: group) }
                    else {
                        groups[group] = ["source": source, "state": payload["state"] as? [String: Any] ?? [:],
                                         "suppressed": groups[group]?["suppressed"] as? Bool ?? false]
                    }
                    quarantine.removeValue(forKey: group)
                    quarantinedSources.removeValue(forKey: group)
                } else if kind == "unload-group" {
                    groups.removeValue(forKey: group)
                    quarantine.removeValue(forKey: group)
                    quarantinedSources.removeValue(forKey: group)
                } else if kind == "suppress-group", groups[group] != nil {
                    groups[group]?["suppressed"] = payload["on"] as? Bool == true
                }
            }
            for (group, state) in result["states"] as? [String: [String: Any]] ?? [:] where groups[group] != nil {
                groups[group]?["state"] = state
            }
            try save()
        } catch {
            groups = oldGroups
            quarantine = oldQuarantine
            quarantinedSources = oldSources
            throw error
        }
    }

    func wasQuarantined(_ group: String, source: String) -> Bool {
        quarantine[group] != nil && (quarantinedSources[group] == SafariConfiguration.profileKey(source)
            || groups[group]?["source"] as? String == source)
    }
    func markQuarantined(_ group: String, reason: String, source: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard !group.isEmpty else { return }
        quarantine[group] = reason
        if let source { quarantinedSources[group] = SafariConfiguration.profileKey(source) }
        try? save()
    }
    private func save() throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "groups": groups, "quarantine": quarantine, "quarantinedSources": quarantinedSources], options: [.sortedKeys])
        guard data.count <= 16 * 1024 * 1024 else { throw SafariRuntimeError.invalidRequest }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum SafariRuntimeError: Error { case missingResources, engineUnavailable, invalidRequest, invalidReply }

/// Runs the canonical engine in Safari's isolated native extension process.
/// There are no DOM/network/timer/file bridges available to JavaScript. Native
/// file operations happen through the separately validated message broker.
final class SafariRuleEngine {
    private let context: JSContext
    private var result: [String: Any]?
    private var nextID = 0
    var onGroup: ((String) -> Void)?
    private var pendingLoads: [String: (payload: [String: Any], result: [String: Any])] = [:]
    private var pendingOrder: [String] = []

    init(resources: URL) throws {
        guard let context = JSContext() else { throw SafariRuntimeError.engineUnavailable }
        self.context = context
        let reply: @convention(block) (Int, String) -> Void = { [weak self] _, json in
            guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
            self?.result = value
        }
        let group: @convention(block) (String) -> Void = { [weak self] id in self?.onGroup?(id) }
        context.setObject(reply, forKeyedSubscript: "__safariReply" as NSString)
        context.setObject(group, forKeyedSubscript: "__safariGroup" as NSString)
        context.evaluateScript("""
        (() => {
          let deliver;
          const parent = { postMessage(message) {
            if (message && message.type === "reply") __safariReply(message.id, JSON.stringify(message.result));
            if (message && message.type === "handler-start") __safariGroup(String(message.groupId || ""));
          }};
          globalThis.window = { parent, addEventListener(type, fn) { if (type === "message") deliver = fn; } };
          globalThis.self = globalThis;
          globalThis.__safariDeliver = (id, payload) => deliver({
            data: { source: "custom-blocker-offscreen", id, payload }, source: parent, origin: ""
          });
        })();
        """)
        for file in ["rule-core.js", "event-sandbox.js"] {
            let source = try String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8)
            context.evaluateScript(source)
            guard context.exception == nil else { throw SafariRuntimeError.engineUnavailable }
        }
    }
    func handle(_ payload: [String: Any]) throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(payload) else { throw SafariRuntimeError.invalidRequest }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard data.count <= 4 * 1024 * 1024, let literal = String(data: data, encoding: .utf8) else { throw SafariRuntimeError.invalidRequest }
        result = nil
        nextID += 1
        context.evaluateScript("__safariDeliver(\(nextID),\(literal));")
        if context.exception != nil { context.exception = nil; throw SafariRuntimeError.invalidReply }
        guard let result else { throw SafariRuntimeError.invalidReply }
        return result
    }
    /// Browser registration is staged until its source/memory write succeeds.
    /// The native recovery journal is saved before activating that candidate.
    func handleJournaled(_ payload: [String: Any], journal: SafariRuleJournal) throws -> [String: Any] {
        let kind = payload["kind"] as? String ?? ""
        if let roster = payload["groupIds"] as? [String] {
            for token in pendingOrder where !roster.contains(pendingLoads[token]?.payload["groupId"] as? String ?? "") {
                _ = try handle(["kind": "discard-source", "token": token])
                pendingLoads.removeValue(forKey: token)
            }
            pendingOrder.removeAll { pendingLoads[$0] == nil }
        }
        if kind == "prepare-source" || kind == "load-source" {
            var request = payload
            request["kind"] = "prepare-source"
            let prepared = try handle(request)
            guard prepared["ok"] as? Bool == true, let token = prepared["token"] as? String else { return prepared }
            let group = payload["groupId"] as? String ?? ""
            for old in pendingOrder where pendingLoads[old]?.payload["groupId"] as? String == group { pendingLoads.removeValue(forKey: old) }
            pendingOrder.removeAll { pendingLoads[$0] == nil }
            while pendingOrder.count >= 64 { pendingLoads.removeValue(forKey: pendingOrder.removeFirst()) }
            var committed = payload
            committed["kind"] = "load-source"
            pendingLoads[token] = (committed, prepared)
            pendingOrder.append(token)
            if kind == "prepare-source" { return prepared }
            return try commitPrepared(token, group: group, journal: journal)
        }
        if kind == "commit-source" {
            return try commitPrepared(payload["token"] as? String ?? "", group: payload["groupId"] as? String ?? "", journal: journal)
        }
        if kind == "discard-source" {
            let token = payload["token"] as? String ?? ""
            pendingLoads.removeValue(forKey: token)
            pendingOrder.removeAll { $0 == token }
            return try handle(payload)
        }
        if kind == "unload-group" {
            let group = payload["groupId"] as? String ?? ""
            for token in pendingOrder where pendingLoads[token]?.payload["groupId"] as? String == group { pendingLoads.removeValue(forKey: token) }
            pendingOrder.removeAll { pendingLoads[$0] == nil }
        }
        let reply = try handle(payload)
        try journal.commit(payload: payload, result: reply)
        return reply
    }
    private func commitPrepared(_ token: String, group: String, journal: SafariRuleJournal) throws -> [String: Any] {
        guard let candidate = pendingLoads[token], candidate.payload["groupId"] as? String == group else {
            return ["ok": false, "error": "Prepared rule is no longer available."]
        }
        defer { pendingLoads.removeValue(forKey: token); pendingOrder.removeAll { $0 == token } }
        // The save callback exists only during commit, after registration has
        // finished. User initialization cannot invoke it before validation.
        let save: @convention(block) () -> String? = {
            do { try journal.commit(payload: candidate.payload, result: candidate.result); return nil }
            catch { return "Safari's rule recovery journal could not be saved." }
        }
        context.setObject(save, forKeyedSubscript: "__safariCommitSave" as NSString)
        defer { context.evaluateScript("delete globalThis.__safariCommitSave;") }
        let literal = String(data: try JSONSerialization.data(withJSONObject: [token]), encoding: .utf8)!
        let reply = context.evaluateScript("JSON.stringify(engine.commitLoad((\(literal))[0],()=>{const error=__safariCommitSave();if(error)throw Error(error);}));")
        guard context.exception == nil, let json = reply?.toString(), let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            context.exception = nil
            throw SafariRuntimeError.invalidReply
        }
        return value
    }
    func restore(_ journal: SafariRuleJournal) throws {
        for group in journal.groups.keys.sorted() where journal.quarantine[group] == nil {
            guard let record = journal.groups[group] else { continue }
            let result = try handleJournaled(["kind": "load-source", "groupId": group, "source": record["source"] ?? "", "state": record["state"] ?? [:]], journal: journal)
            guard result["ok"] as? Bool == true else { continue }
            if record["suppressed"] as? Bool == true { _ = try handle(["kind": "suppress-group", "groupId": group, "on": true]) }
        }
    }
}
