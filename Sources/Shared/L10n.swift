import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }
}

enum L10n {
    static let languageKey = "settings.language"

    static var isEnglish: Bool {
        let raw = UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.system.rawValue
        switch AppLanguage(rawValue: raw) ?? .system {
        case .english:
            return true
        case .chinese:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            return preferred.lowercased().hasPrefix("en")
        }
    }

    static func t(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}
