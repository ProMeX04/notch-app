import Combine
import Foundation

public enum NotchShelfItemSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }
}

public enum NotchShelfDuplicateDropAction: String, CaseIterable, Identifiable, Sendable {
    case ignore
    case moveToTop

    public var id: String { rawValue }
}

public enum NotchShelfLinkDoubleClickAction: String, CaseIterable, Identifiable, Sendable {
    case open
    case copyURL

    public var id: String { rawValue }
}

public enum NotchShelfAutoUploadScope: String, CaseIterable, Identifiable, Sendable {
    case filesOnly
    case allItems

    public var id: String { rawValue }
}

public enum NotchShelfMaximumItemCount: String, CaseIterable, Identifiable, Sendable {
    case never
    case twentyFive
    case fifty
    case oneHundred

    public var id: String { rawValue }

    public var value: Int? {
        switch self {
        case .never: return nil
        case .twentyFive: return 25
        case .fifty: return 50
        case .oneHundred: return 100
        }
    }
}

public enum NotchShelfExpirationInterval: String, CaseIterable, Identifiable, Sendable {
    case never
    case oneDay
    case sevenDays
    case thirtyDays

    public var id: String { rawValue }

    public var timeInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .oneDay: return 24 * 60 * 60
        case .sevenDays: return 7 * 24 * 60 * 60
        case .thirtyDays: return 30 * 24 * 60 * 60
        }
    }
}

public struct NotchShelfRetentionPolicy: Equatable, Sendable {
    public var maximumItemCount: NotchShelfMaximumItemCount
    public var expirationInterval: NotchShelfExpirationInterval

    public init(
        maximumItemCount: NotchShelfMaximumItemCount = .never,
        expirationInterval: NotchShelfExpirationInterval = .never
    ) {
        self.maximumItemCount = maximumItemCount
        self.expirationInterval = expirationInterval
    }
}

public struct NotchShelfCleanupPreview: Equatable, Sendable {
    public let itemsToRemoveCount: Int
    public let driveItemsToDeleteCount: Int

    public init(itemsToRemoveCount: Int, driveItemsToDeleteCount: Int) {
        self.itemsToRemoveCount = itemsToRemoveCount
        self.driveItemsToDeleteCount = driveItemsToDeleteCount
    }
}

@MainActor
public final class NotchShelfPreferences: ObservableObject {
    public static let autoUploadEnabledKey = "notchShelfGoogleDriveAutoUploadEnabled"

    private enum Key {
        static let itemSize = "dev.notch.shelf.item-size"
        static let showItemNames = "dev.notch.shelf.show-item-names"
        static let showDriveBadges = "dev.notch.shelf.show-drive-badges"
        static let duplicateDropAction = "dev.notch.shelf.duplicate-drop-action"
        static let linkDoubleClickAction = "dev.notch.shelf.link-double-click-action"
        static let autoUploadScope = "dev.notch.shelf.auto-upload-scope"
        static let maximumItemCount = "dev.notch.shelf.maximum-item-count"
        static let expirationInterval = "dev.notch.shelf.expiration-interval"
        static let deleteDriveFilesDuringAutomaticCleanup = "dev.notch.shelf.delete-drive-on-cleanup"
    }

    private let defaults: UserDefaults

    @Published public var itemSize: NotchShelfItemSize { didSet { defaults.set(itemSize.rawValue, forKey: Key.itemSize) } }
    @Published public var showItemNames: Bool { didSet { defaults.set(showItemNames, forKey: Key.showItemNames) } }
    @Published public var showDriveBadges: Bool { didSet { defaults.set(showDriveBadges, forKey: Key.showDriveBadges) } }
    @Published public var duplicateDropAction: NotchShelfDuplicateDropAction { didSet { defaults.set(duplicateDropAction.rawValue, forKey: Key.duplicateDropAction) } }
    @Published public var linkDoubleClickAction: NotchShelfLinkDoubleClickAction { didSet { defaults.set(linkDoubleClickAction.rawValue, forKey: Key.linkDoubleClickAction) } }
    @Published public var autoUploadEnabled: Bool { didSet { defaults.set(autoUploadEnabled, forKey: Self.autoUploadEnabledKey) } }
    @Published public var autoUploadScope: NotchShelfAutoUploadScope { didSet { defaults.set(autoUploadScope.rawValue, forKey: Key.autoUploadScope) } }
    @Published public private(set) var maximumItemCount: NotchShelfMaximumItemCount
    @Published public private(set) var expirationInterval: NotchShelfExpirationInterval
    @Published public var deleteDriveFilesDuringAutomaticCleanup: Bool {
        didSet { defaults.set(deleteDriveFilesDuringAutomaticCleanup, forKey: Key.deleteDriveFilesDuringAutomaticCleanup) }
    }

    public var retentionPolicy: NotchShelfRetentionPolicy {
        NotchShelfRetentionPolicy(
            maximumItemCount: maximumItemCount,
            expirationInterval: expirationInterval
        )
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        itemSize = Self.value(NotchShelfItemSize.self, key: Key.itemSize, defaults: defaults) ?? .medium
        showItemNames = Self.bool(key: Key.showItemNames, defaultValue: true, defaults: defaults)
        showDriveBadges = Self.bool(key: Key.showDriveBadges, defaultValue: true, defaults: defaults)
        duplicateDropAction = Self.value(NotchShelfDuplicateDropAction.self, key: Key.duplicateDropAction, defaults: defaults) ?? .ignore
        linkDoubleClickAction = Self.value(NotchShelfLinkDoubleClickAction.self, key: Key.linkDoubleClickAction, defaults: defaults) ?? .open
        autoUploadEnabled = defaults.bool(forKey: Self.autoUploadEnabledKey)
        autoUploadScope = Self.value(NotchShelfAutoUploadScope.self, key: Key.autoUploadScope, defaults: defaults) ?? .allItems
        maximumItemCount = Self.value(NotchShelfMaximumItemCount.self, key: Key.maximumItemCount, defaults: defaults) ?? .never
        expirationInterval = Self.value(NotchShelfExpirationInterval.self, key: Key.expirationInterval, defaults: defaults) ?? .never
        deleteDriveFilesDuringAutomaticCleanup = defaults.bool(forKey: Key.deleteDriveFilesDuringAutomaticCleanup)
    }

    public func setRetentionPolicy(_ policy: NotchShelfRetentionPolicy) {
        maximumItemCount = policy.maximumItemCount
        expirationInterval = policy.expirationInterval
        defaults.set(policy.maximumItemCount.rawValue, forKey: Key.maximumItemCount)
        defaults.set(policy.expirationInterval.rawValue, forKey: Key.expirationInterval)
    }

    private static func bool(key: String, defaultValue: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    private static func value<T: RawRepresentable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key) else { return nil }
        return T(rawValue: rawValue)
    }
}
