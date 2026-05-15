import AppKit
import SwiftUI

struct CompactLiveActivityView: View {
    @ObservedObject var playback: MediaProbeViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat
    let albumArtNamespace: Namespace.ID

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
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
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            CompactSpectrumView(
                accentColor: playback.hasTrack ? Color(nsColor: playback.accentColor) : .gray,
                isPlaying: playback.isPlaying
            )
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

struct CompactTalkView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    let closedNotchWidth: CGFloat
    let closedNotchHeight: CGFloat

    private var sideSize: CGFloat {
        max(0, closedNotchHeight - 12)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                } else if gemini.isModelThinking {
                    CompactTalkThinkingSpinner(tint: accentColor)
                } else {
                    CompactTalkLiveDot(connectionState: gemini.effectiveConnectionState)
                }
            }
            .frame(width: sideSize, height: sideSize)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, closedNotchWidth - NotchMetrics.closedCornerRadius.top))

            HStack {
                Spacer(minLength: 0)
                CompactTalkPulseView(
                    tint: accentColor,
                    inputLevel: gemini.microphoneInputLevel,
                    isListening: gemini.isActivelyListening,
                    isModelSpeaking: gemini.isModelSpeaking
                )
                Spacer(minLength: 0)
            }
            .frame(width: sideSize, height: sideSize)
        }
        .frame(height: closedNotchHeight, alignment: .center)
    }
}

/// Small “on air” dot for closed notch (no extra chrome — just the dot).
private struct CompactTalkThinkingSpinner: View {
    let tint: Color

    @State private var rotationDegrees: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 11, height: 11)
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

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
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

    var body: some View {
        if isListening {
            LiveLevelBars(tint: tint, level: inputLevel)
        } else if isModelSpeaking {
            AnimatedPulseBars(tint: tint)
        } else {
            StaticPulseBars(tint: tint)
        }
    }
}

struct LiveLevelBars: View {
    let tint: Color
    let level: Double

    private var normalizedLevel: CGFloat {
        CGFloat(min(max(level, 0), 1))
    }

    private var heights: [CGFloat] {
        let floor: CGFloat = 4
        let dynamic = normalizedLevel * 8
        return [
            floor + dynamic * 0.72,
            floor + dynamic,
            floor + dynamic * 0.82
        ]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.96))
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: normalizedLevel)
    }
}

struct StaticPulseBars: View {
    let tint: Color
    private let heights: [CGFloat] = [5, 9, 6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.35))
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
    }
}

struct AnimatedPulseBars: View {
    let tint: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: 3, height: phase ? [10, 5, 12][index] : [5, 11, 7][index])
            }
        }
        .frame(width: 18, height: 14, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }
}
