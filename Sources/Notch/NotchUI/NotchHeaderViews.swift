import AppKit
import NotchFocusFeature
import SwiftUI

final class NotchHeaderAccessoryController: ObservableObject {
    @Published var leadingActions: [NotchHeaderAction] = []

    func clear() {
        leadingActions = []
    }
}

struct NotchHeaderAction: Identifiable {
    enum Style {
        case secondary
        case primary
    }

    let id: String
    let title: String
    let icon: String?
    let style: Style
    let isDisabled: Bool
    let action: () -> Void
}

struct CompactSpectrumView: View {
    let accentColor: Color
    let isPlaying: Bool
    var visualSize: CGFloat = 18

    private var spectrumWidth: CGFloat {
        max(16, visualSize * 0.6)
    }

    private var spectrumHeight: CGFloat {
        max(12, visualSize * 0.62)
    }

    private var spectrumScale: CGFloat {
        max(1, spectrumHeight / 14)
    }

    var body: some View {
        Rectangle()
            .fill(accentColor.gradient)
            .mask {
                AudioSpectrumView(isPlaying: isPlaying)
                    .scaleEffect(spectrumScale)
                    .frame(width: spectrumWidth, height: spectrumHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PomodoroPhaseProgressIndicator: View {
    enum Style {
        case compact
        case expanded

        var iconSize: CGFloat {
            switch self {
            case .compact: return 15
            case .expanded: return 11
            }
        }

        var stripWidth: CGFloat {
            switch self {
            case .compact: return 26
            case .expanded: return 58
            }
        }

        var stripHeight: CGFloat {
            switch self {
            case .compact: return 6
            case .expanded: return 8
            }
        }

        var segmentCount: Int {
            switch self {
            case .compact: return 5
            case .expanded: return 7
            }
        }

        var framePadding: EdgeInsets {
            switch self {
            case .compact:
                return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            case .expanded:
                return EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            }
        }

        var contentSpacing: CGFloat {
            switch self {
            case .compact: return 4
            case .expanded: return 8
            }
        }

        var showsContainer: Bool {
            switch self {
            case .compact: return false
            case .expanded: return true
            }
        }
    }

    let phase: PomodoroPhase
    let accentColor: Color
    let progress: Double
    var style: Style = .expanded

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        let content = Group {
            if style == .compact {
                compactPhaseBadge
            } else {
                HStack(spacing: style.contentSpacing) {
                    Image(systemName: phaseIndicatorSymbol)
                        .font(.system(size: style.iconSize, weight: .black))
                        .foregroundStyle(accentColor.opacity(0.9))

                    phaseStrip(progress: clampedProgress)
                }
            }
        }

        content
            .padding(style.framePadding)
            .background {
                if style.showsContainer {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.35))
                }
            }
            .overlay {
                if style.showsContainer {
                    Capsule(style: .continuous)
                        .stroke(accentColor.opacity(0.14), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(phase.rawValue))
    }

    private var phaseIndicatorSymbol: String {
        phase.symbolName
    }

    private var compactPhaseBadge: some View {
        Image(systemName: phaseIndicatorSymbol)
            .font(.system(size: style.iconSize, weight: .black))
            .foregroundStyle(accentColor.opacity(0.94))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phaseStrip(progress: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))

                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.92))
                    .frame(width: width * progress)

                HStack(spacing: max(2, height * 0.22)) {
                    ForEach(0..<style.segmentCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(segmentOpacity(at: index, progress: progress)))
                    }
                }
                .padding(.horizontal, max(2, height * 0.34))
                .padding(.vertical, max(1, height * 0.18))
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(width: style.stripWidth, height: style.stripHeight)
    }

    private func segmentOpacity(at index: Int, progress: Double) -> Double {
        let threshold = Double(index + 1) / Double(style.segmentCount)
        return progress >= threshold ? 0.22 : 0.08
    }
}

struct NotchHeaderView: View {
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    @ObservedObject var presentationModel: NotchPresentationModel
    @ObservedObject var accessoryController: NotchHeaderAccessoryController
    @ObservedObject var entitlementStore: NotchEntitlementStore
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var gemini: GeminiLiveViewModel

    private var displayHeight: CGFloat {
        max(22, closedNotchHeight - 6)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(accessoryController.leadingActions) { action in
                    StandardActionButton(
                        title: action.title,
                        icon: action.icon,
                        tint: action.style == .primary ? Color(nsColor: .systemBlue) : .white,
                        variant: action.style == .primary ? .primary : .secondary,
                        isDisabled: action.isDisabled,
                        action: action.action
                    )
                }

                PanelSwitcher(
                    presentationModel: presentationModel,
                    panels: [.media, .focus, .talk],
                    entitlementStore: entitlementStore,
                    pomodoro: pomodoro,
                    gemini: gemini
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .offset(y: 3)

            Rectangle()
                .fill(.clear)
                .frame(width: closedNotchWidth, height: displayHeight)
                .mask {
                    NotchShape()
                }

            HStack(spacing: 10) {
                HeaderUtilitySwitcher(
                    presentationModel: presentationModel,
                    entitlementStore: entitlementStore,
                    gemini: gemini
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .offset(y: 3)
        }
    }
}
