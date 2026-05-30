import Foundation
@testable import NotchShelfFeature

@MainActor
enum NotchShelfPreferencesTests {
    static func defaultsAndPersistence() throws {
        let suiteName = "dev.notch.shelf.preferences.tests.\(UUID().uuidString)"
        let defaults = try expectUnwrapped(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = NotchShelfPreferences(defaults: defaults)
        try expectEqual(preferences.itemSize, .medium)
        try expect(preferences.showItemNames)
        try expect(preferences.showDriveBadges)
        try expectEqual(preferences.autoUploadScope, .allItems)
        try expectEqual(preferences.retentionPolicy, NotchShelfRetentionPolicy())

        preferences.itemSize = .large
        preferences.showItemNames = false
        preferences.autoUploadEnabled = true
        preferences.autoUploadScope = .filesOnly
        preferences.setRetentionPolicy(.init(maximumItemCount: .twentyFive, expirationInterval: .sevenDays))

        let reloaded = NotchShelfPreferences(defaults: defaults)
        try expectEqual(reloaded.itemSize, .large)
        try expect(!reloaded.showItemNames)
        try expect(reloaded.autoUploadEnabled)
        try expectEqual(reloaded.autoUploadScope, .filesOnly)
        try expectEqual(
            reloaded.retentionPolicy,
            NotchShelfRetentionPolicy(maximumItemCount: .twentyFive, expirationInterval: .sevenDays)
        )
    }
}
