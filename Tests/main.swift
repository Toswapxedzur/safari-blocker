import AppKit
import Foundation
import SafariServices
import Darwin

final class TestExtensionContext: NSExtensionContext {
    let items: [Any]
    var afterReply: (() -> Void)?
    init(message: [String: Any], profile: String) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: message]
        if let key = SafariProfileContext.metadataKey { item.userInfo?[key] = profile }
        items = [item]
        super.init()
    }
    override var inputItems: [Any] { items }
    override func completeRequest(returningItems items: [Any]?, completionHandler: ((Bool) -> Void)? = nil) {
        let result = (items?.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) {
            print(json)
            fflush(stdout)
        }
        if let afterReply { afterReply(); return }
        // A real hung handler must terminate through its watchdog (exit124);
        // a healthy request exits cleanly after the native reply is observed.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { exit(0) }
    }
}

if CommandLine.arguments.contains("--native-messages") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let messages = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    let profile = ProcessInfo.processInfo.environment["SAFARI_TEST_PROFILE"] ?? "profile-one"
    let handler = SafariWebExtensionHandler()
    let contexts = messages.map { TestExtensionContext(message: $0, profile: profile) }
    for index in contexts.indices {
        contexts[index].afterReply = {
            if index + 1 < contexts.count { handler.beginRequest(with: contexts[index + 1]) }
            else { DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { exit(0) } }
        }
    }
    handler.beginRequest(with: contexts[0])
    withExtendedLifetime((contexts, handler)) { dispatchMain() }
}

if CommandLine.arguments.contains("--native-message") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let message = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let profile = ProcessInfo.processInfo.environment["SAFARI_TEST_PROFILE"] ?? "profile-one"
    let context = TestExtensionContext(message: message, profile: profile)
    let handler = SafariWebExtensionHandler()
    handler.beginRequest(with: context)
    withExtendedLifetime((context, handler)) { dispatchMain() }
}

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("PASS \(label)") }
    else { print("FAIL \(label)"); failures += 1 }
}
let profileKey = SafariProfileContext.metadataKey
check(profileKey != nil, "Safari 17 documented profile key resolves at runtime")
let profileMetadata: [AnyHashable: Any] = [profileKey ?? "fixture-key": "profile-one"]
check(SafariProfileContext.identifier(userInfo: profileMetadata) == "profile-one", "native profile metadata survives runtime availability lookup")
check(SafariProfileContext.identifier(userInfo: [profileKey ?? "fixture-key": "profile-two"]) == "profile-two", "second native profile retains distinct identity")
check(SafariProfileContext.identifier(userInfo: profileMetadata, metadataKey: nil) == "default", "absent framework export uses the single-profile default")
check(SafariProfileContext.identifier(userInfo: [:]) == "default", "messages without profile metadata use the single-profile default")
let profileUUID = UUID()
check(SafariProfileContext.identifier(userInfo: [profileKey ?? "fixture-key": profileUUID]) == String(describing: profileUUID), "Safari UUID metadata retains its exact profile identity")
let resources = Bundle.main.resourceURL!
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safari-native-tests-" + UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let engine = try SafariRuleEngine(resources: resources)
let journal = try SafariRuleJournal(directory: directory, profile: "one")
let load: [String: Any] = ["kind": "load-source", "groupId": "one", "source": "(on,v)=>{on('tick',ev=>{v.state.visits=(v.state.visits||0)+1;v.cover(ev.data.tabId,true,'focus');v.log(v.state.visits);})}", "state": ["visits": 10]]
let loaded = try engine.handle(load)
check(loaded["ok"] as? Bool == true, "canonical rule registration")
try journal.commit(payload: load, result: loaded)
let tick: [String: Any] = ["kind": "dispatch-event", "descriptor": ["type": "tick", "now": 1000, "data": ["tabId": 7]]]
let result = try engine.handle(tick)
check((result["actions"] as? [[String: Any]])?.first?["kind"] as? String == "cover", "browser action adapter")
check((result["states"] as? [String: [String: Any]])?["one"]?["visits"] as? Int == 11, "per-group JSON memory")
check((result["logs"] as? [[String: Any]])?.first?["source"] as? String == "v.log", "logs contain v.log output")
try journal.commit(payload: tick, result: result)
let coldJournal = try SafariRuleJournal(directory: directory, profile: "one")
let cold = try SafariRuleEngine(resources: resources)
try cold.restore(coldJournal)
let coldResult = try cold.handle(tick)
check((coldResult["states"] as? [String: [String: Any]])?["one"]?["visits"] as? Int == 12, "cold native restart restores committed state")
let other = try SafariRuleJournal(directory: directory, profile: "two")
check(other.groups.isEmpty && other.url != journal.url, "profile journals isolated")
_ = try cold.handle(["kind": "load-source", "groupId": "error", "source": "(on,v)=>on('tick',()=>{throw new Error('diagnostic')})", "state": [:]])
let errorResult = try cold.handle(tick)
check((errorResult["logs"] as? [[String: Any]])?.contains(where: { $0["groupId"] as? String == "error" }) == false, "runtime errors excluded from rule logs")
check((errorResult["diagnostics"] as? [[String: Any]])?.contains(where: { $0["groupId"] as? String == "error" }) == true, "runtime errors retained as diagnostics")
_ = try cold.handle(["kind": "suppress-group", "groupId": "one", "on": true])
let suppressed = try cold.handle(tick)
check((suppressed["actions"] as? [[String: Any]])?.isEmpty == true, "disabled rule emits no actions")
let badLoad = try cold.handle(["kind": "load-source", "groupId": "one", "source": "not valid syntax(", "state": [:]])
check(badLoad["ok"] as? Bool == false, "invalid source refused")
let broker = SafariFileBroker(directory: directory, profile: "one", grantedRoot: directory)
func file(_ action: String, _ path: String, _ text: String = "") -> [String: Any] {
    broker.perform(["action": action, "path": path, "directoryPath": action == "list" ? path : "", "text": text, "requestId": "one:9"])
}
check(file("write", "nested/notes.txt", "alpha")["ok"] as? Bool == true, "selected-folder write creates relative directories")
check(file("append", "nested/notes.txt", "beta")["ok"] as? Bool == true, "selected-folder append")
check(file("read", "nested/notes.txt")["text"] as? String == "alphabeta", "selected-folder UTF-8 read")
check(file("exists", "nested/notes.txt")["exists"] as? Bool == true, "selected-folder existence")
check(file("exists", "absent.txt")["exists"] as? Bool == false, "missing file existence is false")
let listed = file("list", "nested")["entries"] as? [[String: Any]]
check(listed?.first?["path"] as? String == "nested/notes.txt", "list has canonical relative path")
check(listed?.first?["extension"] as? String == ".txt", "list has canonical extension")
check(file("status", "")["permission"] as? String == "granted", "canonical file status")
check(file("list", " nested\\\\ ")["directoryPath"] as? String == "nested", "list normalizes directory path")
try Data([0xef, 0xbb, 0xbf, 0x61, 0xff]).write(to: directory.appendingPathComponent("replacement.txt"))
check(file("read", "replacement.txt")["text"] as? String == "a\u{fffd}", "UTF-8 replacement and BOM match Blob.text")
check(file("append", "replacement.txt", "b")["ok"] as? Bool == true && file("read", "replacement.txt")["text"] as? String == "a\u{fffd}b", "append reencodes decoded text like Chromium")
_ = file("write", "invalid.json", "invalid JSON")
check(file("readJson", "invalid.json")["error"] as? String == "invalid-json" && file("readJson", "invalid.json")["text"] as? String == "invalid JSON", "invalid JSON keeps text for the canonical file reply")
let largeDirectory = directory.appendingPathComponent("many", isDirectory: true)
try FileManager.default.createDirectory(at: largeDirectory, withIntermediateDirectories: true)
for index in 0..<4097 { FileManager.default.createFile(atPath: largeDirectory.appendingPathComponent("entry-\(index).txt").path, contents: Data()) }
check((file("list", "many")["entries"] as? [[String: Any]])?.count == 4097, "folder listings are complete")
for path in ["../escape.txt", "/tmp/escape.txt", "C:/escape.txt", ".hidden.txt", "bad/./notes.txt", "bad/../notes.txt", "x.html", "nested/shell.sh", "nul\0.txt"] {
    check(file("write", path, "bad")["ok"] as? Bool == false, "unsafe path refused: \(path.debugDescription)")
}
let outside = directory.deletingLastPathComponent().appendingPathComponent("outside-" + UUID().uuidString + ".txt")
try Data("outside".utf8).write(to: outside)
defer { try? FileManager.default.removeItem(at: outside) }
try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.txt"), withDestinationURL: outside)
check(file("read", "link.txt")["ok"] as? Bool == false, "symlink read refused")
check(file("write", "link.txt", "overwrite")["ok"] as? Bool == false, "symlink write refused")
let outsideText = try String(contentsOf: outside)
check(outsideText == "outside", "symlink target unchanged")
check(file("write", "large.txt", String(repeating: "x", count: SafariFileBroker.byteLimit + 1))["ok"] as? Bool == false, "file write limit enforced")
try Data(repeating: 120, count: SafariFileBroker.byteLimit + 1).write(to: directory.appendingPathComponent("large-read.txt"))
check(file("read", "large-read.txt")["ok"] as? Bool == false, "file read limit enforced")
let pipe = directory.appendingPathComponent("pipe.txt")
guard mkfifo(pipe.path, 0o600) == 0 else { fatalError("Could not create the disposable FIFO fixture.") }
check(file("read", "pipe.txt")["error"] as? String == "unsupported-file-type", "FIFO read refuses blocking special files")
check(file("write", "pipe.txt", "unsafe")["error"] as? String == "unsupported-file-type", "FIFO write refuses special files")
check(file("exists", "pipe.txt")["exists"] as? Bool == false, "FIFO is not a regular file")
print("SAFARI_NATIVE_RESULT: \(failures == 0 ? "OK" : "FAIL") (\(failures) failures)")
exit(failures == 0 ? 0 : 1)
