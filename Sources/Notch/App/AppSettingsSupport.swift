import AppKit
import NotchFocusFeature
import NotchShelfFeature
import SwiftUI

enum AppSettingsTab: String, CaseIterable, Identifiable {
    case account
    case general
    case shelf
    case focus
    case talk
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .shelf:
            return "Shelf"
        case .account:
            return "Account"
        case .focus:
            return "Focus"
        case .talk:
            return "Talk"
        case .shortcuts:
            return "Shortcuts"
        }
    }


    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .shelf:
            return "tray.full"
        case .account:
            return "person.crop.circle"
        case .focus:
            return "timer"
        case .talk:
            return "bubble.left.and.bubble.right"
        case .shortcuts:
            return "command"
        }
    }
}

@MainActor
protocol AppSettingsControlling: AnyObject {
    func configure(
        presentationModel: NotchPresentationModel,
        pomodoro: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        learningStats: LearningStatsStore,
        focusCloudSync: FocusCloudSyncCoordinator,
        portalAccount: PortalAccountCoordinator,
        gemini: GeminiLiveViewModel,
        entitlementStore: NotchEntitlementStore,
        shortcutStore: ShortcutStore,
        shelf: NotchShelfViewModel
    )
    func open(tab: AppSettingsTab)
}

@MainActor
final class AppSettingsController: ObservableObject, AppSettingsControlling {
    static let shared = AppSettingsController()

    private struct Dependencies {
        let presentationModel: NotchPresentationModel
        let pomodoro: PomodoroViewModel
        let focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore
        let learningStats: LearningStatsStore
        let focusCloudSync: FocusCloudSyncCoordinator
        let portalAccount: PortalAccountCoordinator
        let gemini: GeminiLiveViewModel
        let entitlementStore: NotchEntitlementStore
        let shortcutStore: ShortcutStore
        let shelf: NotchShelfViewModel
    }

    @Published var selectedTab: AppSettingsTab = .general
    private var dependencies: Dependencies?
    private var window: NSWindow?
    private var hostingController: NSHostingController<AppSettingsView>?

    func configure(
        presentationModel: NotchPresentationModel,
        pomodoro: PomodoroViewModel,
        focusWebsiteBlocklistStore: FocusWebsiteBlocklistStore,
        learningStats: LearningStatsStore,
        focusCloudSync: FocusCloudSyncCoordinator,
        portalAccount: PortalAccountCoordinator,
        gemini: GeminiLiveViewModel,
        entitlementStore: NotchEntitlementStore,
        shortcutStore: ShortcutStore,
        shelf: NotchShelfViewModel
    ) {
        dependencies = Dependencies(
            presentationModel: presentationModel,
            pomodoro: pomodoro,
            focusWebsiteBlocklistStore: focusWebsiteBlocklistStore,
            learningStats: learningStats,
            focusCloudSync: focusCloudSync,
            portalAccount: portalAccount,
            gemini: gemini,
            entitlementStore: entitlementStore,
            shortcutStore: shortcutStore,
            shelf: shelf
        )

        updateRootViewIfNeeded()
    }

    func open(tab: AppSettingsTab = .general) {
        selectedTab = tab
        guard let dependencies else { return }

        let window = makeWindowIfNeeded(using: dependencies)
        updateRootViewIfNeeded()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.center()
    }

    private func makeWindowIfNeeded(using dependencies: Dependencies) -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: makeRootView(using: dependencies))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Notch Settings"
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 900, height: 640)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        self.hostingController = hostingController
        self.window = window
        return window
    }

    private func updateRootViewIfNeeded() {
        guard let dependencies, let hostingController else { return }
        hostingController.rootView = makeRootView(using: dependencies)
    }

    private func makeRootView(using dependencies: Dependencies) -> AppSettingsView {
        AppSettingsView(
            presentationModel: dependencies.presentationModel,
            pomodoro: dependencies.pomodoro,
            focusWebsiteBlocklistStore: dependencies.focusWebsiteBlocklistStore,
            learningStats: dependencies.learningStats,
            focusCloudSync: dependencies.focusCloudSync,
            portalAccount: dependencies.portalAccount,
            gemini: dependencies.gemini,
            entitlementStore: dependencies.entitlementStore,
            shortcutStore: dependencies.shortcutStore,
            shelf: dependencies.shelf,
            initialTab: selectedTab
        )
    }
}

func settingsAccentColor(from rawValue: String) -> Color {
    NotchAccentColorOption.resolve(rawValue: rawValue).brightColor
}

func settingsFormattedAgentDisplayName(_ raw: String) -> String {
    let collapsed = raw
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    return collapsed.isEmpty ? "Untitled Agent" : collapsed
}

struct AppSettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                
                if let subtitle, !subtitle.isEmpty {
                    Text("—")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppSettingsRow<Content: View>: View {
    let showDivider: Bool
    let content: Content

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}

struct AppSettingsPageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AppSettingsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize()
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.top, 6)
    }
}

struct AppSettingsPaneStack<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: 920, alignment: .leading)
    }
}
