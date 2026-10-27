import AppKit
import Foundation
import SafariServices
import Darwin
import JavaScriptCore

final class TestExtensionContext: NSExtensionContext {
    let items: [Any]
    var afterReply: (([String: Any]) -> Void)?
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
        if let afterReply { afterReply(result); return }
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
        contexts[index].afterReply = { reply in
            if index + 1 < contexts.count {
                if let item = contexts[index + 1].items.first as? NSExtensionItem,
                   var message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
                   var payload = message["payload"] as? [String: Any], payload["token"] as? String == "$previousToken" {
                    payload["token"] = (reply["result"] as? [String: Any])?["token"] ?? "missing"
                    message["payload"] = payload
                    item.userInfo?[SFExtensionMessageKey] = message
                }
                handler.beginRequest(with: contexts[index + 1])
            }
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
// Registration memory must survive without relying on a later event.
let initEngine = try SafariRuleEngine(resources: resources)
let initJournal = try SafariRuleJournal(directory: directory, profile: "initialization")
let counterSource = "(on,v)=>{v.state.run=(v.state.run||0)+1;}"
func initLoad(_ source: String, _ state: [String: Any], kind: String = "load-source") throws -> [String: Any] {
    try initEngine.handleJournaled(["kind": kind, "groupId": "init", "source": source, "state": state], journal: initJournal)
}
let firstInit = try initLoad(counterSource, [:])
check((firstInit["states"] as? [String: [String: Any]])?["init"]?["run"] as? Int == 1, "initialization-only native load exports memory")
let secondInit = try initLoad(counterSource, initJournal.groups["init"]?["state"] as? [String: Any] ?? [:])
check((secondInit["states"] as? [String: [String: Any]])?["init"]?["run"] as? Int == 2, "native Run retains initialization-only memory")
let restoredInit = try SafariRuleEngine(resources: resources)
try restoredInit.restore(initJournal)
check(initJournal.groups["init"]?["state"] as? [String: Int] == ["run": 3], "native cold restore commits initialization-only changes before events")
let oldSource = "(on,v)=>{v.state.run=(v.state.run||0)+1;on('tick',()=>v.log(v.state.run));}"
_ = try initLoad(oldSource, [:])
let prepared = try initLoad("(on,v)=>{v.state.run=99;}", ["run": 1], kind: "prepare-source")
check(initJournal.groups["init"]?["source"] as? String == oldSource, "prepared candidate leaves the recovery journal unchanged")
let stagedCold = try SafariRuleJournal(directory: directory, profile: "initialization")
check(stagedCold.groups["init"]?["source"] as? String == oldSource, "cold journal cannot replay an uncommitted candidate")
_ = try initEngine.handleJournaled(["kind":"discard-source", "groupId":"init", "token":prepared["token"] ?? ""], journal: initJournal)
let invalidInitial = try initLoad("(on,v)=>{v.state.text='中'.repeat(22000);}", [:])
check(invalidInitial["ok"] as? Bool == false, "native registration applies UTF-8 state byte limit")
let pendingFailure = try initLoad("(on,v)=>{v.state.run=99;}", ["run":1], kind:"prepare-source")
let journalBackup = initJournal.url.appendingPathExtension("backup")
try FileManager.default.moveItem(at: initJournal.url, to: journalBackup)
try FileManager.default.createDirectory(at: initJournal.url, withIntermediateDirectories:false)
let failedSave = try initEngine.handleJournaled(["kind":"commit-source", "groupId":"init", "token":pendingFailure["token"] ?? ""], journal:initJournal)
check(failedSave["ok"] as? Bool == false && initJournal.groups["init"]?["source"] as? String == oldSource, "native journal write failure preserves saved source and state")
let stillOld = try initEngine.handle(["kind":"dispatch-event", "descriptor":["type":"tick", "targetGroupId":"init"]])
check((stillOld["logs"] as? [[String:Any]])?.first?["args"] as? [Int] == [1], "failed native commit preserves exact prior handler without initializer replay")
try FileManager.default.removeItem(at:initJournal.url)
try FileManager.default.moveItem(at:journalBackup,to:initJournal.url)
let errorField = try initLoad("(on,v)=>{v.state.error='ordinary memory';}", [:])
check((errorField["states"] as? [String:[String:Any]])?["init"]?["error"] as? String == "ordinary memory", "native user error field remains valid JSON state")
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
// Managed time contracts use the actual independent Safari JSC runtime and
// journal. They do not enable/install the extension or touch a browser profile.
let timed = try SafariRuleEngine(resources:resources)
let timeJournal = try SafariRuleJournal(directory:directory,profile:"managed-time")
let timeSource = #"(on,v)=>{const t=v.timer('clock',{durationMs:100});const r=v.rolling('budget',{windowMs:120000,limitMs:1000});r.assign({websites:['example.org']});v.panel('clock',{controls:[{type:'timer',timerId:'clock'}]});on('start',()=>t.start());on('tick',()=>{v.state.clock=t.snapshot();v.state.budget=r.snapshot();});on('timerEnded',()=>{v.state.ends=(v.state.ends||0)+1;});}"#
let timeLoaded = try timed.handleJournaled(["kind":"load-source","groupId":"time","source":timeSource,"state":[:]],journal:timeJournal)
check(timeLoaded["ok"] as? Bool == true,"Safari managed timer/tracker registration")
let clockPanel = (timeLoaded["panels"] as? [[String:Any]])?.first?["controls"] as? [[String:Any]]
check(clockPanel?.first?["type"] as? String == "text","Safari managed timer uses existing panel text renderer")
let timeNow = (Date().timeIntervalSince1970 * 1000).rounded(.down)
func timeEvent(_ engine:SafariRuleEngine,_ type:String,_ at:Double,_ data:[String:Any] = [:]) throws -> [String:Any] {
    try engine.handleJournaled(["kind":"dispatch-event","descriptor":["type":type,"targetGroupId":"time","now":at,"data":data]],journal:timeJournal)
}
_ = try timeEvent(timed,"start",timeNow)
let timeEnded = try timeEvent(timed,"tick",timeNow+101)
check((timeEnded["states"] as? [String:[String:Any]])?["time"]?["ends"] as? Int == 1,"Safari countdown delivers its managed completion")
_ = try timeEvent(timed,"visible",timeNow+1101,["url":"https://example.org","elapsedMs":1000])
let timeSpent = try timeEvent(timed,"tick",timeNow+1101)
let savedTime = (timeSpent["states"] as! [String:[String:Any]])["time"]!
check((savedTime["budget"] as? [String:Any])?["available"] as? Bool == false,"Safari observed website usage exhausts one named allowance")
_ = try timed.handleJournaled(["kind":"time-context","groupId":"time","context":["linked":true,"ready":false,"clusterId":"shared-test"]],journal:timeJournal)
let offline = try timeEvent(timed,"tick",timeNow+1200)
check((((offline["states"] as? [String:[String:Any]])?["time"]?["budget"]) as? [String:Any])?["ready"] as? Bool == false,"Safari shared state is unavailable while disconnected")
let timeCold = try SafariRuleEngine(resources:resources)
try timeCold.restore(try SafariRuleJournal(directory:directory,profile:"managed-time"))
let recoveredTime = try timeEvent(timeCold,"tick",timeNow+1300)
let coldState = (recoveredTime["states"] as! [String:[String:Any]])["time"]!
check((coldState["budget"] as? [String:Any])?["ready"] as? Bool == false && coldState["ends"] as? Int == 1,"Safari journal recovery preserves shared fail-closed state and completion receipt")
let deniedControl = try timeEvent(timeCold,"start",timeNow+1300)
check((deniedControl["diagnostics"] as? [[String:Any]])?.contains(where:{ String(describing:$0["args"] ?? "").contains("fresh hub") }) == true,"Safari recovered offline timer refuses controls")
// Exercise the canonical hub policy in actual JavaScriptCore. These tests use
// disposable journals and independent native runtimes, never browser profiles.
let timePolicy = JSContext()!
timePolicy.evaluateScript(try String(contentsOf: resources.appendingPathComponent("rule-core.js"), encoding: .utf8))
func policyTime(_ method: String, _ arguments: [Any]) throws -> [String:Any] {
    let json = String(data: try JSONSerialization.data(withJSONObject: arguments), encoding: .utf8)!
    let reply = timePolicy.evaluateScript("JSON.stringify(RuleCore.\(method)(...\(json)))")?.toString()
    guard timePolicy.exception == nil, let reply,
          let value = try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String:Any] else {
        timePolicy.exception = nil
        throw SafariRuntimeError.invalidReply
    }
    return value
}
func managedState(_ result: [String:Any], _ group: String) -> [String:Any] {
    (result["states"] as? [String:[String:Any]])?[group] ?? [:]
}
func managedEvent(_ engine: SafariRuleEngine, _ journal: SafariRuleJournal, _ group: String,
                  _ type: String, _ at: Double, _ data: [String:Any] = [:]) throws -> [String:Any] {
    try engine.handleJournaled(["kind":"dispatch-event", "descriptor":["type":type, "targetGroupId":group, "now":at, "data":data]], journal:journal)
}
let exactEngine = try SafariRuleEngine(resources:resources)
let exactJournal = try SafariRuleJournal(directory:directory,profile:"managed-exact-expiry")
let exactSource = #"(on,v)=>{const r=v.rolling('budget',{windowMs:10000,limitMs:3000});r.assign({websites:['example.org','example.net']});on('tick',()=>{v.state.budget=r.snapshot();});}"#
_ = try exactEngine.handleJournaled(["kind":"load-source","groupId":"exact","source":exactSource,"state":[:]],journal:exactJournal)
// Stay ahead of real registration time without sleeps in boundary assertions.
let exactStart = timeNow + 10000
_ = try managedEvent(exactEngine,exactJournal,"exact","visible",exactStart+5000,["url":"https://example.org","elapsedMs":5000])
_ = try managedEvent(exactEngine,exactJournal,"exact","visible",exactStart+6000,["url":"https://example.net","elapsedMs":5000])
func exactBudget(_ at:Double) throws -> [String:Any] {
    let result = try managedEvent(exactEngine,exactJournal,"exact","tick",at)
    // An unchanged snapshot is intentionally omitted from the event reply.
    let saved = exactJournal.groups["exact"]?["state"] as? [String:Any] ?? [:]
    return managedState(result,"exact")["budget"] as? [String:Any] ?? saved["budget"] as? [String:Any] ?? [:]
}
let overused = try exactBudget(exactStart+6000)
check(overused["usedMs"] as? Int == 6000 && overused["available"] as? Bool == false,"Safari counts all over-limit usage and deduplicates overlapping assigned websites")
let exactBoundary = try exactBudget(exactStart+10000)
let exactFirstCredit = try exactBudget(exactStart+10001)
if exactBoundary["usedMs"] as? Int != 6000 || exactFirstCredit["usedMs"] as? Int != 5999 {
    print("Safari exact expiry boundary diagnostic: \(exactBoundary); next millisecond: \(exactFirstCredit)")
}
check(exactBoundary["usedMs"] as? Int == 6000 && exactFirstCredit["usedMs"] as? Int == 5999 && exactFirstCredit["available"] as? Bool == false,"Safari expires exact milliseconds without restoring an overused allowance prematurely")
let exactLimit = try exactBudget(exactStart+13000)
let exactAvailable = try exactBudget(exactStart+13001)
check(exactLimit["usedMs"] as? Int == 3000 && exactLimit["available"] as? Bool == false && exactAvailable["usedMs"] as? Int == 2999 && exactAvailable["available"] as? Bool == true,"Safari availability returns only after full retained usage falls below the limit")
let expiredBudget = try exactBudget(exactStart+16000)
check(expiredBudget["usedMs"] as? Int == 0,"Safari exact rolling history fully expires at the final interval boundary")

let detachedSeed = coldState["$vaultTime"] as! [String:Any]
let finalMerge = try policyTime("mergeTime",[NSNull(),[["member":"safari/time","state":detachedSeed]],"safari/time",timeNow+1300])
var finalShared = finalMerge["state"] as! [String:Any]
var finalObjects = finalShared["objects"] as! [String:[String:Any]]
finalObjects["clock"]?["generation"] = 9
finalObjects["clock"]?["elapsedMs"] = 42
finalObjects["clock"]?["startedAtMs"] = NSNull()
finalObjects["budget"]?["websites"] = ["example.org","example.net"]
finalObjects["budget"]?["segments"] = [[timeNow+2000,timeNow+6000]]
finalObjects["budget"]?["bucketsMs"] = [:]
finalShared["objects"] = finalObjects
finalShared["confirmed"] = ["safari/time":true]
var staleSeed = detachedSeed
staleSeed["pending"] = [["id":"clock","op":"reset","serial":99,"atMs":timeNow+6000,"scope":"shared-test"]]
let transferred = try policyTime("detachTime",[staleSeed,finalShared,"safari/time","safari/time","shared-test","safari-retained-token",timeNow+6000])
check(transferred["ok"] as? Bool == true,"Safari JSC validates the retained final shared snapshot")
let detachedContext = try timeCold.handleJournaled(["kind":"time-context","groupId":"time","context":["linked":false,"detached":true,"state":transferred["state"] ?? [:]]],journal:timeJournal)
let detachedResult = try timeEvent(timeCold,"tick",timeNow+6000)
let detachedState = managedState(detachedResult,"time")
let detachedNamespace = detachedState["$vaultTime"] as? [String:Any] ?? [:]
let detachedObjects = detachedNamespace["objects"] as? [String:[String:Any]] ?? [:]
check(detachedContext["ok"] as? Bool == true && detachedObjects["clock"]?["generation"] as? Int == 9 && (detachedNamespace["pending"] as? [Any])?.isEmpty == true,"Safari final handover replaces stale timer state and discards old linked commands")
check((detachedState["budget"] as? [String:Any])?["usedMs"] as? Int == 4000 && detachedObjects["budget"]?["websites"] as? [String] == ["example.org"],"Safari final handover keeps shared overuse and restores this member's target assignments")
let detachedJournal = try SafariRuleJournal(directory:directory,profile:"managed-time")
let detachedCold = try SafariRuleEngine(resources:resources)
try detachedCold.restore(detachedJournal)
let detachedColdResult = try managedEvent(detachedCold,detachedJournal,"time","tick",timeNow+6100)
let detachedColdState = managedState(detachedColdResult,"time")
let detachedColdNamespace = detachedColdState["$vaultTime"] as? [String:Any] ?? [:]
check((detachedColdNamespace["detachedReceipt"] as? [String:Any])?["token"] as? String == "safari-retained-token" && (detachedColdState["budget"] as? [String:Any])?["usedMs"] as? Int == 4000 && (detachedColdState["clock"] as? [String:Any])?["ready"] as? Bool == true,"Safari cold journal restore preserves the final snapshot and pending handover receipt")
_ = try managedEvent(detachedCold,detachedJournal,"time","start",timeNow+6200)
let afterLocalControl = managedState(try managedEvent(detachedCold,detachedJournal,"time","tick",timeNow+6230),"time")
let acknowledged = try policyTime("detachTime",[afterLocalControl["$vaultTime"] ?? [:],finalShared,"safari/time","safari/time","shared-test","safari-retained-token",timeNow+6230,true])
let ackNamespace = acknowledged["state"] as? [String:Any] ?? [:]
let ackObjects = ackNamespace["objects"] as? [String:[String:Any]] ?? [:]
check(acknowledged["ok"] as? Bool == true && ackNamespace["detachedReceipt"] == nil && ackObjects["clock"]?["startedAtMs"] as? Double == timeNow+6200,"Safari final snapshot acknowledgement preserves timer controls performed after handover")

// The same hub timer completes once independently for each linked member.
let memberSource = #"(on,v)=>{const t=v.timer('clock',{durationMs:100});on('start',()=>t.start());on('timerEnded',()=>{v.state.ends=(v.state.ends||0)+1;});}"#
let memberA = try SafariRuleEngine(resources:resources), memberB = try SafariRuleEngine(resources:resources)
let memberAJournal = try SafariRuleJournal(directory:directory,profile:"managed-member-a")
let memberBJournal = try SafariRuleJournal(directory:directory,profile:"managed-member-b")
let memberALoad = try memberA.handleJournaled(["kind":"load-source","groupId":"a","source":memberSource,"state":[:]],journal:memberAJournal)
let memberBLoad = try memberB.handleJournaled(["kind":"load-source","groupId":"b","source":memberSource,"state":[:]],journal:memberBJournal)
let memberStart = timeNow+20000
let memberStarted = try managedEvent(memberA,memberAJournal,"a","start",memberStart)
let memberSeedA = managedState(memberStarted,"a")["$vaultTime"] ?? managedState(memberALoad,"a")["$vaultTime"] ?? [:]
let memberSeedB = managedState(memberBLoad,"b")["$vaultTime"] ?? [:]
let memberMerge = try policyTime("mergeTime",[NSNull(),[["member":"safari/a","state":memberSeedA],["member":"chrome/b","state":memberSeedB]],"safari/a",memberStart])
let memberShared = memberMerge["state"] as? [String:Any] ?? [:]
for (runtime,store,id) in [(memberA,memberAJournal,"a"),(memberB,memberBJournal,"b")] {
    let context: [String:Any] = ["linked":true,"ready":true,"clusterId":"completion-members","state":memberShared,"acknowledgedSerial":0]
    _ = try runtime.handleJournaled(["kind":"time-context","groupId":id,"context":context],journal:store)
    let ended = try managedEvent(runtime,store,id,"tick",memberStart+101)
    check(managedState(ended,id)["ends"] as? Int == 1,"Safari linked member \(id) receives its own completion once")
    _ = try runtime.handleJournaled(["kind":"time-context","groupId":id,"context":context],journal:store)
    let repeated = try managedEvent(runtime,store,id,"tick",memberStart+102)
    check(managedState(repeated,id)["ends"] as? Int == 1,"Safari linked member \(id) does not replay completion after the same shared snapshot")
}
let memberCold = try SafariRuleEngine(resources:resources)
let memberColdJournal = try SafariRuleJournal(directory:directory,profile:"managed-member-a")
try memberCold.restore(memberColdJournal)
_ = try memberCold.handleJournaled(["kind":"time-context","groupId":"a","context":["linked":true,"ready":true,"clusterId":"completion-members","state":memberShared,"acknowledgedSerial":0]],journal:memberColdJournal)
let memberReconnected = try managedEvent(memberCold,memberColdJournal,"a","tick",memberStart+103)
check(managedState(memberReconnected,"a")["ends"] as? Int == 1,"Safari member completion receipt survives journal restart and reconnect")
// AI responses are events of the exact native rule instance, not journaled
// operations that can replay after Run, disable or a cold restart.
let aiEngine = try SafariRuleEngine(resources:resources)
let aiJournal = try SafariRuleJournal(directory:directory,profile:"ai")
let aiSource = #"(on,v)=>{on('panel',()=>v.ai({prompt:'Summarize',input:{text:'fixture'}}));on('ai',({data})=>{v.state.answer=data.text;v.cover(7,data.ok,data.text);});}"#
let aiLoad: [String:Any] = ["kind":"load-source","groupId":"ai","source":aiSource,"state":[:]]
_ = try aiEngine.handleJournaled(aiLoad,journal:aiJournal)
let aiStart = try aiEngine.handleJournaled(["kind":"dispatch-event","descriptor":["type":"panel","groupId":"ai","data":[:]]],journal:aiJournal)
let aiAction = (aiStart["actions"] as? [[String:Any]])?.first ?? [:]
check(aiAction["kind"] as? String == "ai" && aiAction["generation"] as? String != nil,"Safari native forwards provider-neutral AI action with generation")
let aiReply: [String:Any] = ["kind":"dispatch-event","descriptor":["type":"ai","groupId":"ai","data":["requestId":aiAction["requestId"] ?? "", "generation":aiAction["generation"] ?? "", "ok":true,"text":"Summary"]]]
let aiResult = try aiEngine.handleJournaled(aiReply,journal:aiJournal)
check((aiResult["actions"] as? [[String:Any]])?.first?["kind"] as? String == "cover","Safari native AI event can drive an ordinary browser action")
_ = try aiEngine.handleJournaled(aiLoad,journal:aiJournal)
let aiStale = try aiEngine.handleJournaled(aiReply,journal:aiJournal)
check((aiStale["actions"] as? [[String:Any]])?.isEmpty == true,"Safari Run discards old AI reply")
let aiCold = try SafariRuleEngine(resources:resources)
try aiCold.restore(aiJournal)
let aiColdReply = try aiCold.handleJournaled(aiReply,journal:aiJournal)
check((aiColdReply["actions"] as? [[String:Any]])?.isEmpty == true,"Safari cold restart does not replay old AI result")
let attached = try SafariRuleEngine(resources:resources)
let attachmentJournal = try SafariRuleJournal(directory:directory,profile:"attachments")
let attachmentSource = #"(on,v)=>{on('items',({data})=>{if(!data.items[0].attachments.note)v.attach(data.tabId,data.items[0],'note',{type:'pill',text:'Read',tone:'blue'});});on('attachment',({data})=>v.log(data.eventName,data.attachmentId,data.item.contentId));}"#
_ = try attached.handleJournaled(["kind":"load-source","groupId":"attachment","source":attachmentSource,"state":[:]],journal:attachmentJournal)
let contentHandle: [String:Any] = ["ref":"i1","contentId":"youtube:video:fixture","instanceId":"page:1","attachments":[:]]
let attachmentAction = try attached.handleJournaled(["kind":"dispatch-event","descriptor":["type":"items","data":["tabId":7,"items":[contentHandle]]]],journal:attachmentJournal)
let intent = (attachmentAction["actions"] as? [[String:Any]])?.first ?? [:]
check(intent["kind"] as? String == "attach" && intent["attachmentId"] as? String == "note","Safari JSC emits provider-neutral content attachment intent")
check((intent["target"] as? [String:Any])?["instanceId"] as? String == "page:1","Safari attachment intent retains exact occurrence identity")
let clicked = try attached.handleJournaled(["kind":"dispatch-event","descriptor":["type":"attachment","data":["eventName":"click","tabId":7,"attachmentId":"note","item":contentHandle]]],journal:attachmentJournal)
check((clicked["logs"] as? [[String:Any]])?.first != nil,"Safari current rule receives content attachment click event")
var cachedHandle = contentHandle;cachedHandle["attachments"] = ["note":["type":"pill","text":"Saved"]]
let cachedAttachment = try attached.handleJournaled(["kind":"dispatch-event","descriptor":["type":"items","data":["tabId":7,"items":[cachedHandle]]]],journal:attachmentJournal)
check((cachedAttachment["actions"] as? [[String:Any]])?.isEmpty == true,"Safari rule can skip work for a saved content attachment")
print("SAFARI_NATIVE_RESULT: \(failures == 0 ? "OK" : "FAIL") (\(failures) failures)")
exit(failures == 0 ? 0 : 1)
