import Foundation

enum Language: String, CaseIterable, Identifiable {
    case system, chinese, english
    var id: String { rawValue }
    static var current: Language {
        Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system
    }
    static var isChinese: Bool {
        switch current {
        case .chinese: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }
}

func L(_ chinese: String, _ english: String) -> String {
    Language.isChinese ? chinese : english
}
