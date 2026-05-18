import AppKit
import SwiftUI

struct CompactLiveActivityView: View {
    @ObservedObject var playback: MediaProbeViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let contentWidth: CGFloat
    let albumArtNamespace: Namespace.ID

    private var verticalInset: CGFloat {
        min(6, max(2, closedNotchHeight * 0.18))
    }

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - (verticalInset * 2))
    }

    private var cornerRadius: CGFloat {
        max(3, sideSize * 0.18)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let albumArt = playback.albumArt {
                    Image(nsImage: albumArt)
                        .resizable()
                        .clipped()
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)

            CompactSpectrumView(
                accentColor: playback.hasTrack ? Color(nsColor: playback.accentColor) : .gray,
                isPlaying: playback.isPlaying,
                visualSize: sideSize
            )
            .frame(width: sideSize, height: sideSize)
        }
        .frame(width: contentWidth, height: closedNotchHeight, alignment: .center)
    }
}

struct CompactTalkView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let contentWidth: CGFloat

    private var verticalInset: CGFloat {
        min(6, max(2, closedNotchHeight * 0.18))
    }

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - (verticalInset * 2))
    }

    private var accentColor: Color {
        Color(nsColor: gemini.compactAccentColor).ensureMinimumBrightness(factor: 0.74)
    }

    private var leadingToolIcon: String? {
        gemini.lastToolAction?.icon
    }

    private var leadingStatusIcon: String? {
        if let leadingToolIcon {
            return leadingToolIcon
        }

        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let leadingStatusIcon {
                    Image(systemName: leadingStatusIcon)
                        .font(.system(size: max(12, sideSize * 0.62), weight: .semibold))
                        .foregroundStyle(accentColor)
                } else if gemini.isModelThinking {
                    CompactTalkThinkingSpinner(tint: accentColor, size: sideSize)
                } else {
                    CompactTalkLiveDot(connectionState: gemini.effectiveConnectionState, size: sideSize)
                }
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer(minLength: 0)
                CompactTalkPulseView(
                    tint: accentColor,
                    inputLevel: gemini.microphoneInputLevel,
                    isListening: gemini.isActivelyListening,
                    isModelSpeaking: gemini.isModelSpeaking,
                    size: sideSize
                )
                Spacer(minLength: 0)
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(width: contentWidth, height: closedNotchHeight, alignment: .center)
    }
}

/// Small “on air” dot for closed notch (no extra chrome — just the dot).
private struct CompactTalkThinkingSpinner: View {
    let tint: Color
    let size: CGFloat

    @State private var rotationDegrees: Double = 0

    private var spinnerSize: CGFloat {
        max(11, size * 0.62)
    }

    private var lineWidth: CGFloat {
        max(1.8, spinnerSize * 0.16)
    }

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: spinnerSize, height: spinnerSize)
            .rotationEffect(.degrees(rotationDegrees))
            .onAppear {
                rotationDegrees = 0
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    rotationDegrees = 360
                }
            }
    }
}

/// Small “on air” dot for closed notch (no extra chrome — just the dot).
private struct CompactTalkLiveDot: View {
    let connectionState: GeminiLiveConnectionState
    let size: CGFloat
    @State private var pulse = false

    private var dotColor: Color {
        switch connectionState {
        case .connected, .connecting:
            return Color(nsColor: .systemGreen)
        case .failed, .disconnected:
            return Color.white.opacity(0.45)
        }
    }

    private var shouldPulse: Bool {
        switch connectionState {
        case .connecting, .connected:
            return true
        case .failed, .disconnected:
            return false
        }
    }

    private var pulseDuration: Double {
        connectionState == .connecting ? 0.55 : 1.05
    }

    private var dotSize: CGFloat {
        max(7, size * 0.42)
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: dotSize, height: dotSize)
            .scaleEffect(shouldPulse && pulse ? 1.14 : 1.0)
            .onAppear {
                guard shouldPulse else { return }
                withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct CompactTalkPulseView: View {
    let tint: Color
    let inputLevel: Double
    let isListening: Bool
    let isModelSpeaking: Bool
    let size: CGFloat

    var body: some View {
        if isListening {
            LiveLevelBars(tint: tint, level: inputLevel, size: size)
        } else if isModelSpeaking {
            AnimatedPulseBars(tint: tint, size: size)
        } else {
            StaticPulseBars(tint: tint, size: size)
        }
    }
}

struct LiveLevelBars: View {
    let tint: Color
    let level: Double
    let size: CGFloat

    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }

    private var barWidth: CGFloat {
        max(3, size * 0.12)
    }

    private var spacing: CGFloat {
        max(3, size * 0.1)
    }

    private var heights: [CGFloat] {
        let floor = max(4, size * 0.2)
        let dynamic = normalizedLevel * max(8, size * 0.36)
        return [
            floor + dynamic * 0.72,
            floor + dynamic,
            floor + dynamic * 0.82
        ]
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.96))
                    .frame(width: barWidth, height: heights[index])
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: normalizedLevel)
    }
}

struct StaticPulseBars: View {
    let tint: Color
    let size: CGFloat

    private var barWidth: CGFloat {
        max(3, size * 0.12)
    }

    private var spacing: CGFloat {
        max(3, size * 0.1)
    }

    private var heights: [CGFloat] {
        [size * 0.24, size * 0.48, size * 0.32].map { max(5, $0) }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.35))
                    .frame(width: barWidth, height: heights[index])
            }
        }
        .frame(width: size, height: size, alignment: .center)
    }
}

struct AnimatedPulseBars: View {
    let tint: Color
    let size: CGFloat
    @State private var phase = false

    private var barWidth: CGFloat {
        max(3, size * 0.12)
    }

    private var spacing: CGFloat {
        max(3, size * 0.1)
    }

    private var lowHeights: [CGFloat] {
        [size * 0.24, size * 0.56, size * 0.36].map { max(5, $0) }
    }

    private var highHeights: [CGFloat] {
        [size * 0.5, size * 0.26, size * 0.62].map { max(5, $0) }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: barWidth, height: phase ? highHeights[index] : lowHeights[index])
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
