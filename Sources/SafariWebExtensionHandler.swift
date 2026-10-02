import AppKit
import Foundation
import SafariServices
import Darwin

enum SafariProfileContext {
    // Safari 17 also provides profiles on macOS 13. The SDK annotates this
    // exported constant with macOS 14 availability, so resolve its actual
    // presence in the loaded framework instead of using an OS-version gate.
    static let metadataKey: String? = {
        let defaultScope = UnsafeMutableRawPointer(bitPattern: -2) // Darwin RTLD_DEFAULT
        guard let symbol = dlsym(defaultScope, "SFExtensionProfileKey"),
              let value = symbol.assumingMemoryBound(to: UnsafeRawPointer?.self).pointee else { return nil }
        return Unmanaged<NSString>.fromOpaque(value).takeUnretainedValue() as String
    }()

    static func identifier(userInfo: [AnyHashable: Any]?, metadataKey: String? = Self.metadataKey) -> String {
        guard let metadataKey, let value = userInfo?[metadataKey] else { return "default" }
        return String(describing: value)
    }
}

@objc(SafariWebExtensionHandler)
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "com.adamancia.vault.safari.rules")
    private static var profiles: [String: ProfileRuntime] = [:]

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
              JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message), data.count <= 4 * 1024 * 1024 else {
            Self.respond(context, ["ok": false, "error": "Invalid native message."])
            return
        }
        let profile = SafariProfileContext.identifier(userInfo: item.userInfo)
        let type = message["type"] as? String ?? message["kind"] as? String ?? ""
        if type == "local-hub-challenge" { Self.respond(context, SafariConfiguration.proof(message: message)); return }
        if type == "safari-lifecycle-activate" {
            Self.activateContainingApp { Self.respond(context, $0) }
            return
        }
        if type == "ping" { Self.respond(context, ["ok": true, "environment": SafariConfiguration.environment]); return }
        let broker = SafariFileBroker(directory: SafariConfiguration.ruleDirectory, profile: profile)
        if type == "local-folder-choose" { broker.choose { Self.respond(context, $0) }; return }
        Self.queue.async {
            switch type {
            case "local-folder-status": Self.respond(context, broker.status())
            case "local-folder-revoke": Self.respond(context, broker.revoke())
            case "local-file-request":
                Self.respond(context, ["ok": true, "result": broker.perform(message["request"] as? [String: Any] ?? [:])])
            case "event-sandbox-request": Self.handleRule(context, profile: profile, payload: message["payload"] as? [String: Any] ?? [:])
            default: Self.respond(context, ["ok": false, "error": "Unsupported native message."])
            }
        }
    }
    private static func activateContainingApp(completion: @escaping ([String: Any]) -> Void) {
        // Native messaging cannot move execution into a Safari service worker.
        // Launch only our own signed containing app in the background through
        // Launch Services; never launch Safari or alter its security settings.
        guard Bundle.main.bundleURL.pathExtension == "appex" else {
            completion(["ok": false, "error": "The containing app is unavailable."])
            return
        }
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.arguments = ["--background"]
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                completion(error == nil ? ["ok": true] : ["ok": false, "error": "Safari Vault's background helper could not start."])
            }
        }
    }
    private static func handleRule(_ context: NSExtensionContext, profile: String, payload: [String: Any]) {
        guard let groupIDs = payload["groupIds"] as? [String],
              groupIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            respond(context, ["ok": false, "error": "An authoritative custom-group roster is required."])
            return
        }
        if payload["kind"] as? String == "load-source" {
            guard let group = payload["groupId"] as? String, groupIDs.contains(group) else {
                respond(context, ["ok": false, "error": "The custom group no longer exists."])
                return
            }
        }
        let fence = RequestFence(context: context)
        do {
            // The fence is active during restore as well: a crashing previous
            // process cannot leave a source that hangs every future request.
            let runtime: ProfileRuntime
            if let existing = profiles[profile] {
                runtime = existing
                fence.journal = runtime.journal
                fence.start()
                for group in try runtime.journal.reconcile(Set(groupIDs)) {
                    _ = try runtime.engine.handle(["kind": "unload-group", "groupId": group])
                }
            }
            else {
                let journal = try SafariRuleJournal(directory: SafariConfiguration.ruleDirectory, profile: profile)
                _ = try journal.reconcile(Set(groupIDs))
                fence.journal = journal
                let engine = try SafariRuleEngine(resources: Bundle.main.resourceURL!)
                engine.onGroup = { fence.group = $0 }
                runtime = ProfileRuntime(journal: journal, engine: engine)
                fence.start()
                try engine.restore(journal)
                profiles[profile] = runtime
            }
            fence.journal = runtime.journal
            runtime.engine.onGroup = { fence.group = $0 }
            fence.start()
            if payload["kind"] as? String == "load-source", let group = payload["groupId"] as? String,
               runtime.journal.wasQuarantined(group, source: payload["source"] as? String ?? ""),
               payload["run"] as? Bool != true {
                fence.finish(["ok": true, "result": ["ok": false, "quarantine": ["groupId": group, "reason": "native-hard-timeout"], "error": "The rule exceeded its execution deadline. Use Run to retry."]])
                return
            }
            if payload["kind"] as? String == "load-source" {
                fence.source = payload["source"] as? String
                fence.group = payload["groupId"] as? String ?? ""
            }
            var result = try runtime.engine.handle(payload)
            if payload["kind"] as? String == "dispatch-event", let group = runtime.journal.quarantine.keys.sorted().first {
                result["quarantine"] = ["groupId": group, "reason": "native-hard-timeout"]
            }
            guard !fence.expired else { return }
            try runtime.journal.commit(payload: payload, result: result)
            fence.finish(["ok": true, "result": result])
        } catch { fence.finish(["ok": false, "error": "Safari's native rule engine could not complete this request."]) }
    }
    private static func respond(_ context: NSExtensionContext, _ value: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: value]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
    private final class ProfileRuntime {
        let journal: SafariRuleJournal
        let engine: SafariRuleEngine
        init(journal: SafariRuleJournal, engine: SafariRuleEngine) { self.journal = journal; self.engine = engine }
    }
    /// Native JSC cannot be cancelled safely on another thread. Safari already
    /// isolates this handler in its own native-extension process. The watchdog
    /// records the offending group and returns the same quarantine contract,
    /// then exits only that handler process. Safari restarts it on demand and
    /// all other profiles/groups recover from their journal.
    private final class RequestFence {
        private let lock = NSLock()
        private var finished = false
        private var started = false
        private var activeGroup = ""
        var journal: SafariRuleJournal?
        var source: String?
        private let context: NSExtensionContext
        var group: String {
            get { lock.lock(); defer { lock.unlock() }; return activeGroup }
            set { lock.lock(); activeGroup = newValue; lock.unlock() }
        }
        var expired: Bool { lock.lock(); defer { lock.unlock() }; return finished }
        init(context: NSExtensionContext) { self.context = context }
        func start() {
            lock.lock()
            if started { lock.unlock(); return }
            started = true
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.5) { [self] in
                lock.lock()
                guard !finished else { lock.unlock(); return }
                finished = true
                let group = activeGroup
                lock.unlock()
                journal?.markQuarantined(group, reason: "native-hard-timeout", source: source ?? journal?.groups[group]?["source"] as? String)
                Self.replyTimeout(context, group: group)
                // Give the native message reply a bounded chance to flush.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { _exit(124) }
            }
        }
        func finish(_ result: [String: Any]) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            SafariWebExtensionHandler.respond(context, result)
        }
        private static func replyTimeout(_ context: NSExtensionContext, group: String) {
            var result: [String: Any] = ["ok": false, "error": "The rule exceeded its execution deadline."]
            if !group.isEmpty { result["quarantine"] = ["groupId": group, "reason": "native-hard-timeout"] }
            SafariWebExtensionHandler.respond(context, ["ok": true, "result": result])
        }
    }
}
