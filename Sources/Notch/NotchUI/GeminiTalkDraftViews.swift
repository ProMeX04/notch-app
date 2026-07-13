import AppKit
import SwiftUI

struct GeminiTalkDraftHomeView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let appLanguage: String
    let themeAccent: Color
    let statusColor: Color
    let selectedAgentAvatarSymbolName: String
    let selectedAgentAvatarImageURL: URL?
    let selectAgent: () -> Void
    let openSettingsPanel: () -> Void

    var body: some View {
        GeminiTalkAgentHubDraft(
            gemini: gemini,
            appLanguage: appLanguage,
            themeAccent: themeAccent,
            statusColor: statusColor,
            selectedAgentAvatarSymbolName: selectedAgentAvatarSymbolName,
            selectedAgentAvatarImageURL: selectedAgentAvatarImageURL,
            selectAgent: selectAgent
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct GeminiTalkAgentHubDraft: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let appLanguage: String
    let themeAccent: Color
    let statusColor: Color
    let selectedAgentAvatarSymbolName: String
    let selectedAgentAvatarImageURL: URL?
    let selectAgent: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Button(action: selectAgent) {
                GeminiTalkPlainAvatarFigure(
                    tint: statusColor,
                    symbolName: selectedAgentAvatarSymbolName,
                    imageURL: selectedAgentAvatarImageURL,
                    size: 94
                )
            }
            .buttonStyle(.plain)
            .frame(width: 108)
            .frame(maxHeight: .infinity)
            .padding(.leading, 10)

            GeminiTalkHubControlSurface(
                gemini: gemini,
                appLanguage: appLanguage,
                themeAccent: themeAccent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct GeminiTalkHubControlSurface: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let appLanguage: String
    let themeAccent: Color

    private var agentName: String {
        formattedAgentDisplayName(gemini.selectedSystemPromptPreset.title)
    }

    private var modelDisplayName: String {
        gemini.selectedModel.displayName
    }

    private var modelThinkingLabel: String {
        guard gemini.thinkingLevel != .off else { return modelDisplayName }
        return "\(modelDisplayName) - \(gemini.thinkingLevel.rawValue)"
    }

    var body: some View {
        matrixSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var headerRow: some View {
        HStack(spacing: 7) {
            Text(agentName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(themeAccent)

            GeminiTalkMiniStatusPill(
                icon: "circle.fill",
                title: Localization.get("Online", lang: appLanguage),
                tint: themeAccent
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var matrixSurface: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow

                Text(modelThinkingLabel)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
            }
            .frame(width: 210, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)

            GeminiTalkHubConnectTile(
                gemini: gemini,
                appLanguage: appLanguage,
                tint: themeAccent,
                style: .vertical
            )
            .frame(width: 70)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 2)

            VStack(spacing: 6) {
                GeminiTalkHubTinyChip(icon: "waveform", title: gemini.selectedVoice.rawValue, tint: themeAccent)
                GeminiTalkHubTinyChip(icon: "wrench.and.screwdriver", title: "\(gemini.enabledTools.count) tools", tint: themeAccent)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum GeminiTalkHubConnectTileStyle {
    case horizontal
    case vertical
    case compact
}

private struct GeminiTalkHubConnectTile: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let appLanguage: String
    let tint: Color
    let style: GeminiTalkHubConnectTileStyle

    private var activeTint: Color {
        gemini.lifecycleState.isBusy ? Color.red : tint
    }

    private var isDisabled: Bool {
        !gemini.canStartConnection && !gemini.lifecycleState.isBusy
    }

    private var icon: String {
        gemini.lifecycleState.isBusy ? "stop.fill" : "play.fill"
    }

    private var title: String {
        gemini.lifecycleState.isBusy ? Localization.get("Disconnect", lang: appLanguage) : Localization.get("Connect", lang: appLanguage)
    }

    var body: some View {
        Button {
            gemini.toggleConnection()
        } label: {
            Group {
                switch style {
                case .horizontal:
                    horizontalLabel
                case .vertical:
                    verticalLabel
                case .compact:
                    compactLabel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(GrowingButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var horizontalLabel: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(activeTint.opacity(0.72))
                .frame(width: 4, height: 28)
                .shadow(color: activeTint.opacity(0.45), radius: 6)

            GeminiTalkConnectCircleLabel(
                icon: icon,
                isBusy: gemini.lifecycleState.isBusy,
                tint: tint,
                size: 32
            )

            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var verticalLabel: some View {
        GeminiTalkConnectCircleLabel(
            icon: icon,
            isBusy: gemini.lifecycleState.isBusy,
            tint: tint,
            size: 52
        )
        .padding(.vertical, 4)
    }

    private var compactLabel: some View {
        ZStack(alignment: .topTrailing) {
            GeminiTalkConnectCircleLabel(
                icon: icon,
                isBusy: gemini.lifecycleState.isBusy,
                tint: tint,
                size: 34
            )

            Circle()
                .fill(activeTint)
                .frame(width: 7, height: 7)
                .shadow(color: activeTint.opacity(0.55), radius: 5)
                .offset(x: -6, y: 6)
        }
        .padding(5)
    }
}

private struct GeminiTalkHubTinyChip: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 11)
            Text(title)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 28)
    }
}

private struct GeminiTalkConnectCircleLabel: View {
    let icon: String
    let isBusy: Bool
    let tint: Color
    let size: CGFloat

    var body: some View {
        let activeTint = isBusy ? Color.red : tint

        ZStack {
            Circle()
                .fill(activeTint.opacity(0.16))
                .frame(width: size + 10, height: size + 10)
                .blur(radius: 8)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeTint.opacity(0.82),
                            activeTint
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: activeTint.opacity(0.58), radius: 8, x: 0, y: 0)

            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect)
        }
    }
}

private struct GeminiTalkPlainAvatarFigure: View {
    let tint: Color
    let symbolName: String
    let imageURL: URL?
    let size: CGFloat

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.78))
                .frame(width: size + 6, height: size + 6)
                .shadow(color: tint.opacity(isHovering ? 0.58 : 0.34), radius: isHovering ? 22 : 14)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(isHovering ? 0.52 : 0.3), lineWidth: isHovering ? 2 : 1.4)
                }

            GeminiAgentAvatarArtwork(
                imageURL: imageURL,
                symbolName: symbolName,
                symbolFont: .system(size: size * 0.38, weight: .semibold),
                size: size
            )
            .clipShape(Circle())
        }
        .frame(width: size + 14, height: size + 10)
        .scaleEffect(isHovering ? 1.035 : 1)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isHovering)
    }
}

private struct GeminiTalkOrbAvatar: View {
    let tint: Color
    let symbolName: String
    let imageURL: URL?
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(tint.opacity(index == 0 ? 0.24 : 0.12), lineWidth: 1)
                    .frame(width: index == 0 ? 118 : 86, height: index == 0 ? 118 : 86)
                    .scaleEffect(1 + (phase * CGFloat(index + 1) * 0.018))
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.26), Color.white.opacity(0.055), Color.black.opacity(0.2)],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 60
                    )
                )
                .frame(width: 90, height: 90)
                .shadow(color: tint.opacity(0.35), radius: 22)
            GeminiAgentAvatarArtwork(
                imageURL: imageURL,
                symbolName: symbolName,
                symbolFont: .system(size: 34, weight: .semibold),
                size: 78
            )
            .clipShape(Circle())
        }
        .frame(width: 126, height: 112)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

private struct GeminiTalkMiniStatusPill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.045)))
        .overlay(Capsule().stroke(Color.white.opacity(0.075), lineWidth: 1))
    }
}

private struct GeminiTalkCompactInfoPill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 12)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 27)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.052))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct GeminiTalkMetricPill: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
    }
}

private struct GeminiTalkCommandTile: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(GeminiTalkDraftPanelBackground(cornerRadius: 13, tint: tint.opacity(0.22)))
    }
}

private struct GeminiTalkTabLabel: View {
    let title: String
    let isSelected: Bool
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isSelected ? .black.opacity(0.86) : .white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint : Color.white.opacity(0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0 : 0.07), lineWidth: 1)
            }
    }
}

private struct GeminiTalkMeterRow: View {
    let title: String
    let value: CGFloat
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * value)))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct GeminiTalkWaveformMark: View {
    let tint: Color

    private let heights: [CGFloat] = [10, 18, 26, 16, 23, 12]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule(style: .continuous)
                    .fill(tint.opacity(index == 2 ? 0.95 : 0.5))
                    .frame(width: 4, height: height)
                    .shadow(color: tint.opacity(0.28), radius: 5)
            }
        }
    }
}

private struct GeminiTalkFlowStep: View {
    let index: String
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var usesSystemIcon = true

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                Text(index)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(tint))
                    .offset(x: 4, y: -4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(GeminiTalkDraftPanelBackground(cornerRadius: 15, tint: tint.opacity(0.28)))
    }
}

private struct GeminiTalkFlowConnector: View {
    let tint: Color

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(tint.opacity(0.62))
            .frame(width: 14)
    }
}

private struct GeminiTalkDockButton: View {
    let icon: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GeminiTalkDraftPanelBackground: View {
    let cornerRadius: CGFloat
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.064),
                        Color.white.opacity(0.034)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: 1)
            }
    }
}
