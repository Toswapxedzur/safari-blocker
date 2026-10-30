import Foundation

/// Reads only the interface preference and bundled strings; policy data is untouched.
enum SafariNativeLanguage {
    private static let updateStrings: [String: [String: String]] = [
        "zh": [
            "safari.updates.settings": "设置…",
            "safari.updates.title": "Safari Vault 更新",
            "safari.updates.auto": "自动安装更新",
            "safari.updates.check": "检查更新"
        ]
    ]
    public static var language: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = preferred.lowercased().split(separator: "-").first.map(String.init) ?? "en"
        return ["en", "ar", "bn", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pa", "pl", "pt", "ru", "th", "tr", "vi", "zh"].contains(code) ? code : "en"
    }
    public static func text(_ key: String, fallback: String, values: [String: String] = [:]) -> String {
        var result = updateStrings[language]?[key] ?? fallback
        if let root = Bundle.main.resourceURL,
           let data = try? Data(contentsOf: root.appendingPathComponent("translation/\(language).json")),
           let catalog = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            result = catalog[key] ?? result
        }
        for (name, value) in values { result = result.replacingOccurrences(of: "{\(name)}", with: value) }
        return result
    }
}
