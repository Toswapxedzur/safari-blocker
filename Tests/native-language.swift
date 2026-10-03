import Foundation

@main
struct NativeLanguageProbe {
    static func main() throws {
        let keys = ["safari.setup.body", "safari.setup.open", "safari.setup.openFailed",
                    "safari.setup.enabled", "safari.setup.disabled", "safari.folderTitle"]
        var answer = ["language": SafariNativeLanguage.language]
        for key in keys {
            answer[key] = SafariNativeLanguage.text(key, fallback: "MISSING CATALOG ENTRY")
        }
        answer["unknown"] = SafariNativeLanguage.text("test.unknown", fallback: "Literal diagnostic <x>")
        let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
