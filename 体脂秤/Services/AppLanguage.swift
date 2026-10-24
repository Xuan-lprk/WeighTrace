import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "afu.display.language"
    case system, simplifiedChinese = "zh-Hans", english = "en"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(appLocalized: "跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }
    var bundle: Bundle {
        switch self {
        case .system: .main
        case .english: Self.englishBundle
        case .simplifiedChinese: Self.chineseBundle
        }
    }
    private static let englishBundle = languageBundle("en")
    private static let chineseBundle = languageBundle("zh-Hans")
    private static func languageBundle(_ code: String) -> Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

extension String {
    /// Keep Foundation-generated labels in the same language as SwiftUI's locale.
    init(appLocalized value: String.LocalizationValue) {
        let language = AppLanguage.selected
        self.init(localized: value, bundle: language.bundle, locale: language.locale)
    }
}
