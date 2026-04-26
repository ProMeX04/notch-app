import Combine
import Foundation

enum NotchPlan: String, Codable, Equatable {
    case free
    case pro

    var badgeTitle: String {
        switch self {
        case .free:
            return "FREE"
        case .pro:
            return "PRO"
        }
    }
}

enum NotchFeatureRequirement: String, Codable, Equatable, Sendable {
    case free
    case pro
    case disabled
}

enum NotchEntitlementSource: String, Codable, Equatable {
    case backend
    case devBypass
    case cache
    case none
}

enum NotchEntitlementVerification: String, Codable, Equatable {
    case verified
    case gracePeriod
    case expired
    case unknown
}

struct NotchEntitlementSnapshot: Codable, Equatable {
    var plan: NotchPlan
    var backendIsPro: Bool
    var verifiedAt: Date?
    var source: NotchEntitlementSource
    var verification: NotchEntitlementVerification
    var accountID: String?
    var accountEmail: String?

    static let unknown = NotchEntitlementSnapshot(
        plan: .free,
        backendIsPro: false,
        verifiedAt: nil,
        source: .none,
        verification: .unknown,
        accountID: nil,
        accountEmail: nil
    )
}

enum NotchPermissionRecoveryAction: Equatable {
    case signIn
    case upgrade
    case refresh
    case none
}

enum NotchCommandCapability: Equatable {
    case panel
    case focus
    case media
    case talk
    case screen
    case caption
    case visibility
    case pin

    var policyKey: String {
        switch self {
        case .panel:
            return "panel"
        case .focus:
            return "focus"
        case .media:
            return "media"
        case .talk:
            return "talk"
        case .screen:
            return "screen"
        case .caption:
            return "caption"
        case .visibility:
            return "visibility"
        case .pin:
            return "pin"
        }
    }
}

enum NotchCapability: Equatable {
    case talkConnection
    case focusPomodoro
    case focusWebsiteBlocklist
    case browserBridge
    case mediaControls
    case panelAccess(NotchPanel)
    case deepLinkCommand(NotchCommandCapability)

    var policyKey: String {
        switch self {
        case .talkConnection:
            return "talk_connection"
        case .focusPomodoro:
            return "focus_pomodoro"
        case .focusWebsiteBlocklist:
            return "focus_website_blocklist"
        case .browserBridge:
            return "browser_bridge"
        case .mediaControls:
            return "media_controls"
        case let .panelAccess(panel):
            return "panel_\(panel.rawValue)"
        case let .deepLinkCommand(command):
            return "deep_link_\(command.policyKey)"
        }
    }

    var displayName: String {
        switch self {
        case .talkConnection:
            return "Talk"
        case .focusPomodoro:
            return "Focus"
        case .focusWebsiteBlocklist:
            return "website blocking"
        case .browserBridge:
            return "browser bridge"
        case .mediaControls:
            return "media controls"
        case let .panelAccess(panel):
            return "\(panel.rawValue) panel"
        case let .deepLinkCommand(command):
            return "\(command.policyKey) command"
        }
    }
}

struct NotchRemotePermissionPolicy: Codable, Equatable, Sendable {
    let version: Int
    let features: [String: NotchFeatureRequirement]
    let updatedAt: String?

    init(
        version: Int = 1,
        features: [String: NotchFeatureRequirement],
        updatedAt: String? = nil
    ) {
        self.version = version
        self.features = features
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case version
        case features
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)

        let rawFeatures = (try? container.decodeIfPresent([String: String].self, forKey: .features)) ?? [:]
        features = rawFeatures.compactMapValues { NotchFeatureRequirement(rawValue: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(features.mapValues(\.rawValue), forKey: .features)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    func requirement(for capability: NotchCapability) -> NotchFeatureRequirement? {
        features[capability.policyKey]
    }
}

enum NotchPermissionPolicySource: String, Codable, Equatable, Sendable {
    case localDefault
    case backend
    case cache
}

struct NotchPermissionPolicySnapshot: Codable, Equatable, Sendable {
    var remotePolicy: NotchRemotePermissionPolicy?
    var source: NotchPermissionPolicySource
    var receivedAt: Date?

    static let localDefault = NotchPermissionPolicySnapshot(
        remotePolicy: nil,
        source: .localDefault,
        receivedAt: nil
    )
}

struct NotchPermissionDecision: Equatable {
    let capability: NotchCapability
    let isAllowed: Bool
    let requiredPlan: NotchPlan?
    let verification: NotchEntitlementVerification
    let message: String
    let recoveryAction: NotchPermissionRecoveryAction

    static func allowed(
        _ capability: NotchCapability,
        verification: NotchEntitlementVerification
    ) -> NotchPermissionDecision {
        NotchPermissionDecision(
            capability: capability,
            isAllowed: true,
            requiredPlan: nil,
            verification: verification,
            message: "",
            recoveryAction: .none
        )
    }
}

@MainActor
final class NotchEntitlementStore: ObservableObject {
    static let defaultGraceInterval: TimeInterval = 72 * 60 * 60
    private static let localDefaultRequirements: [String: NotchFeatureRequirement] = [
        NotchCapability.talkConnection.policyKey: .pro,
        NotchCapability.focusPomodoro.policyKey: .free,
        NotchCapability.focusWebsiteBlocklist.policyKey: .free,
        NotchCapability.browserBridge.policyKey: .free,
        NotchCapability.mediaControls.policyKey: .free,
    ]

    @Published private(set) var snapshot: NotchEntitlementSnapshot
    @Published private(set) var policySnapshot: NotchPermissionPolicySnapshot

    private let userDefaults: UserDefaults
    private let cacheKey: String
    private let policyCacheKey: String
    private let graceInterval: TimeInterval
    private let dateProvider: () -> Date

    init(
        userDefaults: UserDefaults = .standard,
        cacheKey: String = "dev.notch.entitlement.snapshot.v1",
        policyCacheKey: String = "dev.notch.permission-policy.snapshot.v1",
        graceInterval: TimeInterval = NotchEntitlementStore.defaultGraceInterval,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.cacheKey = cacheKey
        self.policyCacheKey = policyCacheKey
        self.graceInterval = graceInterval
        self.dateProvider = dateProvider
        self.policySnapshot = Self.readCachedPolicySnapshot(
            userDefaults: userDefaults,
            policyCacheKey: policyCacheKey
        ) ?? .localDefault

        if NotchProEntitlement.isBypassActive {
            snapshot = Self.makeDevBypassSnapshot(now: dateProvider())
        } else if let cached = Self.readCachedSnapshot(
            userDefaults: userDefaults,
            cacheKey: cacheKey,
            graceInterval: graceInterval,
            now: dateProvider()
        ) {
            snapshot = cached
        } else {
            snapshot = .unknown
        }
    }

    var isProUser: Bool {
        switch snapshot.verification {
        case .verified, .gracePeriod:
            return snapshot.plan == .pro
        case .expired, .unknown:
            return false
        }
    }

    var planBadgeTitle: String {
        if isProUser { return NotchPlan.pro.badgeTitle }

        switch snapshot.verification {
        case .unknown:
            return "VERIFY"
        case .expired:
            return "EXPIRED"
        case .verified, .gracePeriod:
            return NotchPlan.free.badgeTitle
        }
    }

    var isUsingGracePeriod: Bool {
        snapshot.verification == .gracePeriod && snapshot.plan == .pro
    }

    func updateBackendEntitlement(
        isPro: Bool,
        accountID: String? = nil,
        accountEmail: String? = nil,
        permissionPolicy: NotchRemotePermissionPolicy? = nil
    ) {
        let now = dateProvider()

        guard !NotchProEntitlement.isBypassActive else {
            snapshot = Self.makeDevBypassSnapshot(now: now, backendIsPro: isPro, accountID: accountID, accountEmail: accountEmail)
            applyRemotePolicy(permissionPolicy, receivedAt: now)
            return
        }

        let newSnapshot = NotchEntitlementSnapshot(
            plan: NotchProEntitlement.isProUser(backendPro: isPro) ? .pro : .free,
            backendIsPro: isPro,
            verifiedAt: now,
            source: .backend,
            verification: .verified,
            accountID: accountID,
            accountEmail: accountEmail
        )
        snapshot = newSnapshot
        writeCache(newSnapshot)
        applyRemotePolicy(permissionPolicy, receivedAt: now)
    }

    func markSignedOut() {
        guard !NotchProEntitlement.isBypassActive else {
            snapshot = Self.makeDevBypassSnapshot(now: dateProvider())
            return
        }
        snapshot = .unknown
        clearCache()
        policySnapshot = .localDefault
        clearPolicyCache()
    }

    func markRefreshFailed() {
        guard !NotchProEntitlement.isBypassActive else {
            snapshot = Self.makeDevBypassSnapshot(now: dateProvider())
            return
        }

        if let cached = Self.readCachedSnapshot(
            userDefaults: userDefaults,
            cacheKey: cacheKey,
            graceInterval: graceInterval,
            now: dateProvider()
        ) {
            snapshot = cached
        } else {
            snapshot = .unknown
        }

        policySnapshot = Self.readCachedPolicySnapshot(
            userDefaults: userDefaults,
            policyCacheKey: policyCacheKey
        ) ?? .localDefault
    }

    func decision(for capability: NotchCapability) -> NotchPermissionDecision {
        switch requirement(for: capability) {
        case .free:
            return .allowed(capability, verification: snapshot.verification)
        case .pro:
            return proRequiredDecision(for: capability)
        case .disabled:
            return NotchPermissionDecision(
                capability: capability,
                isAllowed: false,
                requiredPlan: nil,
                verification: snapshot.verification,
                message: "This feature is currently disabled.",
                recoveryAction: .none
            )
        }
    }

    private func requirement(for capability: NotchCapability) -> NotchFeatureRequirement {
        let isPolicyValid = policySnapshot.receivedAt.map { dateProvider().timeIntervalSince($0) <= graceInterval } ?? false
        
        if isPolicyValid, let req = policySnapshot.remotePolicy?.requirement(for: capability) {
            return req
        }

        return Self.localDefaultRequirements[capability.policyKey] ?? .disabled
    }

    private func proRequiredDecision(for capability: NotchCapability) -> NotchPermissionDecision {
        guard !isProUser else {
            return .allowed(capability, verification: snapshot.verification)
        }

        switch snapshot.verification {
        case .unknown:
            return NotchPermissionDecision(
                capability: capability,
                isAllowed: false,
                requiredPlan: .pro,
                verification: .unknown,
                message: signInMessage(for: capability),
                recoveryAction: .signIn
            )
        case .expired:
            return NotchPermissionDecision(
                capability: capability,
                isAllowed: false,
                requiredPlan: .pro,
                verification: .expired,
                message: expiredMessage(for: capability),
                recoveryAction: .refresh
            )
        case .verified, .gracePeriod:
            return NotchPermissionDecision(
                capability: capability,
                isAllowed: false,
                requiredPlan: .pro,
                verification: snapshot.verification,
                message: proRequiredMessage(for: capability),
                recoveryAction: .upgrade
            )
        }
    }

    private func signInMessage(for capability: NotchCapability) -> String {
        if capability == .talkConnection {
            return "Sign in or refresh your Notch account to verify Pro access for Talk."
        }
        return "Sign in or refresh your Notch account to verify Pro access for \(capability.displayName)."
    }

    private func expiredMessage(for capability: NotchCapability) -> String {
        if capability == .talkConnection {
            return "Notch Pro access could not be verified. Refresh your account to continue using Talk."
        }
        return "Notch Pro access could not be verified. Refresh your account to continue using \(capability.displayName)."
    }

    private func proRequiredMessage(for capability: NotchCapability) -> String {
        if capability == .talkConnection {
            return "Notch Pro is required to use Talk."
        }
        return "Notch Pro is required to use \(capability.displayName)."
    }

    private func applyRemotePolicy(_ policy: NotchRemotePermissionPolicy?, receivedAt: Date) {
        guard let policy else {
            policySnapshot = .localDefault
            clearPolicyCache()
            return
        }

        let newSnapshot = NotchPermissionPolicySnapshot(
            remotePolicy: policy,
            source: .backend,
            receivedAt: receivedAt
        )
        policySnapshot = newSnapshot
        writePolicyCache(newSnapshot)
    }

    private func writeCache(_ snapshot: NotchEntitlementSnapshot) {
        guard snapshot.source == .backend else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: cacheKey)
    }

    private func clearCache() {
        userDefaults.removeObject(forKey: cacheKey)
    }

    private func writePolicyCache(_ snapshot: NotchPermissionPolicySnapshot) {
        guard snapshot.source == .backend else { return }
        var cached = snapshot
        cached.source = .cache
        guard let data = try? JSONEncoder().encode(cached) else { return }
        userDefaults.set(data, forKey: policyCacheKey)
    }

    private func clearPolicyCache() {
        userDefaults.removeObject(forKey: policyCacheKey)
    }

    private static func makeDevBypassSnapshot(
        now: Date,
        backendIsPro: Bool = true,
        accountID: String? = nil,
        accountEmail: String? = nil
    ) -> NotchEntitlementSnapshot {
        NotchEntitlementSnapshot(
            plan: .pro,
            backendIsPro: backendIsPro,
            verifiedAt: now,
            source: .devBypass,
            verification: .verified,
            accountID: accountID,
            accountEmail: accountEmail
        )
    }

    private static func readCachedSnapshot(
        userDefaults: UserDefaults,
        cacheKey: String,
        graceInterval: TimeInterval,
        now: Date
    ) -> NotchEntitlementSnapshot? {
        guard let data = userDefaults.data(forKey: cacheKey),
              var cached = try? JSONDecoder().decode(NotchEntitlementSnapshot.self, from: data) else {
            return nil
        }

        cached.source = .cache

        guard cached.plan == .pro else {
            cached.verification = .verified
            return cached
        }

        guard let verifiedAt = cached.verifiedAt else {
            cached.verification = .expired
            return cached
        }

        cached.verification = now.timeIntervalSince(verifiedAt) <= graceInterval ? .gracePeriod : .expired
        return cached
    }

    private static func readCachedPolicySnapshot(
        userDefaults: UserDefaults,
        policyCacheKey: String
    ) -> NotchPermissionPolicySnapshot? {
        guard let data = userDefaults.data(forKey: policyCacheKey),
              var cached = try? JSONDecoder().decode(NotchPermissionPolicySnapshot.self, from: data),
              cached.remotePolicy != nil else {
            return nil
        }

        cached.source = .cache
        return cached
    }
}
