import AppKit
import Foundation

/// Safari has no File System Access picker. A native, explicit folder grant
/// exposes the same small text/CSV/JSON contract as Chromium's folder broker.
final class SafariFileBroker {
    private let bookmarkURL: URL
    private let grantedRoot: URL?
    static let byteLimit = 1024 * 1024

    init(directory: URL, profile: String, grantedRoot: URL? = nil) {
        bookmarkURL = directory.appendingPathComponent("folder-" + SafariConfiguration.profileKey(profile) + ".bookmark")
        self.grantedRoot = grantedRoot
    }
    func status() -> [String: Any] {
        guard let root = rootURL() else { return ["ok": true, "connected": false, "name": ""] }
        return ["ok": true, "connected": true, "name": root.lastPathComponent]
    }
    func choose(completion: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Choose a folder for Safari Vault custom rules"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let root = panel.url else {
                completion(self.status())
                return
            }
            do {
                try FileManager.default.createDirectory(at: self.bookmarkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let bookmark = try root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                try bookmark.write(to: self.bookmarkURL, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.bookmarkURL.path)
                completion(["ok": true, "connected": true, "name": root.lastPathComponent])
            } catch { completion(["ok": false, "error": "Could not retain the selected folder grant."] ) }
        }
    }
    func revoke() -> [String: Any] {
        try? FileManager.default.removeItem(at: bookmarkURL)
        return ["ok": true, "connected": false, "name": ""]
    }
    private func rootURL() -> URL? {
        if let grantedRoot { return grantedRoot }
        guard let data = try? Data(contentsOf: bookmarkURL) else { return nil }
        var stale = false
        guard let root = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, root.startAccessingSecurityScopedResource() {
            defer { root.stopAccessingSecurityScopedResource() }
            if let fresh = try? root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                try? fresh.write(to: bookmarkURL, options: [.atomic])
            }
        }
        return root
    }
    func perform(_ request: [String: Any]) -> [String: Any] {
        let action = request["action"] as? String ?? ""
        let path = request["path"] as? String ?? ""
        let requestedDirectory = request["directoryPath"] as? String ?? ""
        let directoryPath = requestedDirectory.isEmpty ? path : requestedDirectory
        var reply: [String: Any] = ["ok": false, "action": action, "path": path, "directoryPath": directoryPath,
                                   "requestId": request["requestId"] as? String ?? "", "eventName": "error"]
        guard let root = rootURL() else { reply["error"] = "local-folder-not-connected"; return reply }
        let access = root.startAccessingSecurityScopedResource()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        guard access || grantedRoot != nil else { reply["error"] = "local-folder-permission-required"; return reply }
        if action == "status" {
            reply.merge(["ok": true, "eventName": "status", "hasFolder": true, "permission": "granted", "error": ""]) { _, new in new }
            return reply
        }
        do {
            let relative = action == "list" ? directoryPath : path
            let target = try safeURL(relative, root: root, isDirectory: action == "list")
            if action != "list", action != "exists", FileManager.default.fileExists(atPath: target.path),
               try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile != true {
                // Named pipes/devices can block Foundation reads indefinitely.
                // The browser contract exposes regular text files only.
                throw FileError.unsupportedFileType
            }
            switch action {
            case "exists":
                reply["exists"] = (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                reply["eventName"] = "exists"
            case "read", "readJson":
                let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                reply["bytes"] = size
                guard size <= Self.byteLimit else { throw FileError.tooLarge }
                let data = try Data(contentsOf: target)
                guard data.count <= Self.byteLimit else { throw FileError.tooLarge }
                let text = decodeText(data)
                reply["text"] = text
                reply["bytes"] = data.count
                if action == "readJson" {
                    guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else { throw FileError.invalidJSON }
                    reply["value"] = object
                }
                reply["eventName"] = "read"
            case "write", "writeJson", "append":
                var data = action == "writeJson"
                    ? try JSONSerialization.data(withJSONObject: request["value"] ?? NSNull(), options: [.prettyPrinted, .fragmentsAllowed])
                    : Data((request["text"] as? String ?? "").utf8)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                reply["bytes"] = data.count
                guard data.count <= Self.byteLimit else { throw FileError.tooLarge }
                if action == "append", FileManager.default.fileExists(atPath: target.path) {
                    let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    reply["bytes"] = size
                    guard size <= Self.byteLimit else { throw FileError.tooLarge }
                    let existing = try Data(contentsOf: target)
                    data = Data(decodeText(existing).utf8) + data
                    reply["bytes"] = data.count
                    guard data.count <= Self.byteLimit else { throw FileError.tooLarge }
                }
                try data.write(to: target, options: [.atomic])
                reply["bytes"] = data.count
                reply["eventName"] = action == "append" ? "append" : "write"
            case "list":
                let entries = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                let normalized = target.path == root.standardizedFileURL.resolvingSymlinksInPath().path
                    ? "" : String(target.path.dropFirst(root.standardizedFileURL.resolvingSymlinksInPath().path.count + 1))
                reply["directoryPath"] = normalized
                reply["entries"] = try entries.compactMap { entry -> [String: Any]? in
                    let metadata = try entry.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                    guard metadata.isSymbolicLink != true else { return nil }
                    if metadata.isDirectory == true { return ["name": entry.lastPathComponent, "path": normalized.isEmpty ? entry.lastPathComponent : normalized + "/" + entry.lastPathComponent, "kind": "directory"] }
                    if metadata.isRegularFile == true, allowedExtension(entry.pathExtension) { return ["name": entry.lastPathComponent, "path": normalized.isEmpty ? entry.lastPathComponent : normalized + "/" + entry.lastPathComponent, "kind": "file", "extension": "." + entry.pathExtension.lowercased()] }
                    return nil
                }.sorted {
                    let left = ($0["kind"] as? String ?? "") + "\0" + ($0["name"] as? String ?? "")
                    let right = ($1["kind"] as? String ?? "") + "\0" + ($1["name"] as? String ?? "")
                    return left.localizedCompare(right) == .orderedAscending
                }
                reply["eventName"] = "list"
            default: throw FileError.invalidOperation
            }
            reply["ok"] = true
            reply["error"] = ""
        } catch let error as FileError { reply["error"] = error.rawValue }
        catch { reply["error"] = "local-file-operation-failed" }
        return reply
    }
    private func allowedExtension(_ value: String) -> Bool { ["txt", "csv", "json"].contains(value.lowercased()) }
    // Blob.text() uses the UTF-8 replacement decoder and consumes a leading
    // BOM. Keep native reads/appends consistent with Chromium's file broker.
    private func decodeText(_ data: Data) -> String {
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
        return String(decoding: bytes, as: UTF8.self)
    }
    private func safeURL(_ path: String, root: URL, isDirectory: Bool) throws -> URL {
        var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        normalized = normalized.replacingOccurrences(of: "/+", with: "/", options: .regularExpression)
        if normalized.hasSuffix("/") { normalized.removeLast() }
        guard normalized.utf8.count <= 4096, !normalized.hasPrefix("/"), !normalized.contains("\0") else { throw FileError.invalidPath }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard normalized.isEmpty && isDirectory || !components.isEmpty && components.allSatisfy({
            !$0.isEmpty && !$0.hasPrefix(".") && $0.range(of: "^[A-Za-z0-9 _.,@()\\-]+$", options: .regularExpression) != nil
        }) else { throw FileError.invalidPath }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var target = canonicalRoot
        for component in components where !component.isEmpty {
            target.appendPathComponent(component)
            if FileManager.default.fileExists(atPath: target.path),
               try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw FileError.invalidPath }
        }
        let canonical = target.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.path == canonicalRoot.path && isDirectory || canonical.path.hasPrefix(canonicalRoot.path + "/") else { throw FileError.invalidPath }
        if !isDirectory, !allowedExtension(canonical.pathExtension) { throw FileError.unsupportedFileType }
        return canonical
    }
    private enum FileError: String, Error {
        case invalidPath = "invalid-path"
        case invalidOperation = "unsupported-action"
        case unsupportedFileType = "unsupported-file-type"
        case tooLarge = "file-too-large"
        case invalidJSON = "invalid-json"
    }
}
