import AppKit
import NotchFocusCore
import SwiftUI

struct PanelSwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    let panels: [NotchPanel]
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(panels, id: \.rawValue) { panel in
                switcherButton(
                    icon: switcherIcon(for: panel),
                    panel: panel
                )
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func switcherIcon(for panel: NotchPanel) -> String {
        switch panel {
        case .media:
            return "playpause"
        case .focus:
            return "timer"
        case .talk:
            return "bubble.left.and.bubble.right"
        case .shelf:
            return "tray.full"
        case .shortcuts:
            return "command"
        }
    }

    private func switcherButton(icon: String, panel: NotchPanel) -> some View {
        return Button {
            guard let cap = capability(for: panel) else {
                presentationModel.selectPanel(panel)
                return
            }

            let decision = entitlementStore.decision(for: cap)
            if decision.isAllowed {
                presentationModel.selectPanel(panel)
            } else {
                NotchProWindowController.shared.show(for: cap, entitlementStore: entitlementStore, gemini: gemini)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
                .background(
                    Capsule()
                        .fill(presentationModel.selectedPanel == panel ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
                )
                .contentShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if let badge = badge(for: panel) {
                        PanelActivityBadge(
                            color: badge.color,
                            pulses: badge.pulses
                        )
                        .offset(x: -4, y: 4)
                        .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(switcherTitle(for: panel))
    }

    private func capability(for panel: NotchPanel) -> NotchCapability? {
        switch panel {
        case .media:
            return .mediaControls
        case .focus:
            return .focusPomodoro
        case .talk:
            return .talkConnection
        case .shelf:
            return .shelf
        case .shortcuts:
            return nil
        }
    }

    private func switcherTitle(for panel: NotchPanel) -> String {
        switch panel {
        case .media:
            return "Media"
        case .focus:
            return "Focus"
        case .talk:
            return "Talk"
        case .shelf:
            return ""
        case .shortcuts:
            return "Shortcuts"
        }
    }

    private func badge(for panel: NotchPanel) -> PanelSwitcherBadgeStyle? {
        switch panel {
        case .focus:
            guard pomodoro.isRunning else { return nil }
            return PanelSwitcherBadgeStyle(
                color: pomodoro.phase.accentSwiftUIColor.ensureMinimumBrightness(factor: 0.78),
                pulses: true
            )
        case .talk:
            switch gemini.effectiveConnectionState {
            case .connected:
                return PanelSwitcherBadgeStyle(
                    color: Color(nsColor: .systemGreen),
                    pulses: true
                )
            case .connecting:
                return PanelSwitcherBadgeStyle(
                    color: Color(nsColor: .systemOrange),
                    pulses: true
                )
            case .disconnected, .failed:
                return nil
            }
        case .media, .shelf, .shortcuts:
            return nil
        }
    }
}

private struct PanelSwitcherBadgeStyle {
    let color: Color
    let pulses: Bool
}

private struct PanelActivityBadge: View {
    let color: Color
    let pulses: Bool

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.92))
                .frame(width: 10, height: 10)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.5), radius: pulses ? 4 : 0)
                .scaleEffect(pulses && isPulsing ? 1.16 : 1.0)
        }
        .onAppear {
            guard pulses else { return }
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

struct HeaderUtilitySwitcher: View {
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var gemini: GeminiLiveViewModel
    var appSettingsController: AppSettingsControlling = AppSettingsController.shared

    var body: some View {
        HStack(spacing: 3) {
            Button {
                let cap = NotchCapability.shelf
                let decision = entitlementStore.decision(for: cap)
                if decision.isAllowed {
                    presentationModel.selectPanel(.shelf)
                } else {
                    NotchProWindowController.shared.show(for: cap, entitlementStore: entitlementStore, gemini: gemini)
                }
            } label: {
                utilityIcon(
                    "tray.full",
                    isSelected: presentationModel.selectedPanel == .shelf
                )
            }
            .buttonStyle(.plain)
            .help("Shelf")

            Button {
                presentationModel.selectPanel(.shortcuts)
            } label: {
                utilityIcon(
                    "command",
                    isSelected: presentationModel.selectedPanel == .shortcuts
                )
            }
            .buttonStyle(.plain)
            .help("Shortcuts")

            Button {
                appSettingsController.open(tab: .general)
            } label: {
                utilityIcon("gearshape", isSelected: false)
            }
            .buttonStyle(.plain)
            .help(Localization.get("Settings", lang: "English"))
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func utilityIcon(_ systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: StandardButtonMetrics.height, height: StandardButtonMetrics.height)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.001))
            )
            .contentShape(Capsule())
    }
}
