import Foundation
import NotchFocusFeature

// MARK: - AppLanguageProvider Tests

@MainActor
enum AppLanguageProviderTests {

    static func defaultLanguage_isEnglish() throws {
        let defaults = makeIsolatedUserDefaults()
        let provider = AppLanguageProvider(userDefaults: defaults)

        try expectEqual(provider.currentLanguage, "English")
    }

    static func settingLanguage_updatesCurrentLanguage() throws {
        let defaults = makeIsolatedUserDefaults()
        defaults.set("Tiếng Việt", forKey: AppLanguageProvider.storageKey)

        let provider = AppLanguageProvider(userDefaults: defaults)

        try expectEqual(provider.currentLanguage, "Tiếng Việt")
    }

    static func emptyString_isPreservedAsEmpty() throws {
        // Empty string is a stored value, not nil, so it's preserved as-is
        let defaults = makeIsolatedUserDefaults()
        defaults.set("", forKey: AppLanguageProvider.storageKey)

        let provider = AppLanguageProvider(userDefaults: defaults)

        try expectEqual(provider.currentLanguage, "")
    }

    static func refresh_readsLatestFromUserDefaults() throws {
        let defaults = makeIsolatedUserDefaults()
        let provider = AppLanguageProvider(userDefaults: defaults)

        defaults.set("Deutsch", forKey: AppLanguageProvider.storageKey)
        provider.refresh()

        try expectEqual(provider.currentLanguage, "Deutsch")
    }

    static func refresh_noOpWhenUnchanged() throws {
        let defaults = makeIsolatedUserDefaults()
        defaults.set("Français", forKey: AppLanguageProvider.storageKey)
        let provider = AppLanguageProvider(userDefaults: defaults)

        let initialLang = provider.currentLanguage
        provider.refresh()

        try expectEqual(provider.currentLanguage, initialLang)
    }

    static func arbitraryLanguage_isPreserved() throws {
        let defaults = makeIsolatedUserDefaults()
        defaults.set("한국어", forKey: AppLanguageProvider.storageKey)

        let provider = AppLanguageProvider(userDefaults: defaults)

        try expectEqual(provider.currentLanguage, "한국어")
    }

    private static func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "AppLanguageProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}