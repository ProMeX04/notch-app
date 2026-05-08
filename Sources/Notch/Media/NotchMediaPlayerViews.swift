
import SwiftUI

struct ExpandedAlbumArtView: View {
    @ObservedObject var playback: MediaProbeViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if playback.hasTrack, let albumArt = playback.albumArt {
                Image(nsImage: albumArt)
                    .resizable()
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(x: 1.1, y: 1.1)
                    .blur(radius: 40)
                    .opacity(0.5)
            }

            Button {
                playback.openCurrentApp()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let albumArt = playback.albumArt {
                            Image(nsImage: albumArt)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(width: 118, height: 118)
                    .shadow(color: Color(nsColor: playback.accentColor).opacity(0.4), radius: 20, x: 0, y: 4)

                    if let appIcon = playback.appIcon, !playback.usingAppIconForArtwork {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 1))
                            .offset(x: 8, y: 8)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(2)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(playback.isPlaying ? 1 : 0.95)

            Rectangle()
                .fill(Color.black)
                .opacity(playback.isPlaying ? 0 : 0.3)
                .blur(radius: 50)
                .frame(width: 118, height: 118)
        }
        .frame(width: 128, height: 128)
    }
}

struct ExpandedMediaControlsView: View {
    @ObservedObject var playback: MediaProbeViewModel
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    private var primaryText: String {
        let title = playback.state.title
        if title.isEmpty || title == "Nothing Playing" {
            return Localization.get("Nothing Playing", lang: appLanguage)
        }
        return title
    }

    private var sourceLabel: String {
        switch playback.state.bundleIdentifier {
        case "com.apple.Music":
            return "Apple Music"
        case "com.spotify.client":
            return "Spotify"
        case let bundleID where bundleID.contains("youtube"):
            return "YouTube Music"
        default:
            return Localization.get("System Media", lang: appLanguage)
        }
    }

    private var secondaryText: String {
        let artist = playback.state.artist
        if !artist.isEmpty && artist != "Notch" {
            return artist
        }
        return sourceLabel
    }

    private var accent: Color {
        Color(nsColor: playback.accentColor).ensureMinimumBrightness(factor: 0.72)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "music.note.square.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("ĐANG PHÁT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundColor(accent)
            .padding(.bottom, -2)
            
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    .constant(primaryText),
                    font: .system(size: 17, weight: .bold, design: .rounded),
                    nsFont: .title2,
                    textColor: .white,
                    frameWidth: 320
                )
                
                HStack(spacing: 4) {
                    MarqueeText(
                        .constant(secondaryText),
                        font: .system(size: 13, weight: .medium, design: .rounded),
                        nsFont: .body,
                        textColor: .white.opacity(0.6),
                        frameWidth: 300
                    )
                    
                    if sourceLabel == "YouTube Music" || secondaryText.lowercased().contains("vevo") {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(accent)
                            .font(.system(size: 13))
                            .offset(y: -1)
                    }
                }
            }
            
            Spacer().frame(height: 4)

            // Slider with inline text
            TimelineView(.animation(minimumInterval: playback.state.playbackRate > 0 ? 0.1 : nil)) { timeline in
                MediaSliderView(
                    sliderValue: $sliderValue,
                    duration: playback.state.duration,
                    accentColor: accent,
                    labelColor: accent,
                    dragging: $dragging,
                    lastDragged: $lastDragged,
                    currentDate: timeline.date,
                    playback: playback
                )
            }
            .frame(height: 14)
            .padding(.top, 2)

            // Controls
            HStack(spacing: 12) {
                ForEach(MediaControlSlot.allControls) { slot in
                    slotView(for: slot)
                }
                
                Spacer()
                
                VolumeControlView(playback: playback, accent: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func slotView(for slot: MediaControlSlot) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: accent, scale: .medium, isEnabled: false) {}
        case .previous:
            HoverButton(icon: "backward.end.fill", iconColor: .white.opacity(0.6), scale: .medium, isEnabled: playback.canSkipToPreviousTrack) {
                playback.previousTrack()
            }
        case .playPause:
            Button {
                playback.togglePlay()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.8), accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: accent.opacity(0.6), radius: 8, x: 0, y: 0)
                    
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(playback.canTogglePlayback ? 1.0 : 0.9)
            .opacity(playback.canTogglePlayback ? 1.0 : 0.5)
            .disabled(!playback.canTogglePlayback)
        case .next:
            HoverButton(icon: "forward.end.fill", iconColor: .white.opacity(0.6), scale: .medium, isEnabled: playback.canSkipToNextTrack) {
                playback.nextTrack()
            }
        case .favorite:
            FavoriteControlButton(playback: playback, accent: accent)
        case .volume:
            Color.clear
        case .goBackward:
            HoverButton(icon: "gobackward.10", iconColor: .white.opacity(0.6), scale: .medium, isEnabled: playback.canSkipBackward15Seconds) {
                playback.skip(seconds: -10)
            }
        case .goForward:
            HoverButton(icon: "goforward.10", iconColor: .white.opacity(0.6), scale: .medium, isEnabled: playback.canSkipForward15Seconds) {
                playback.skip(seconds: 10)
            }
        case .repeatMode:
            HoverButton(icon: "repeat", iconColor: accent, scale: .medium, isEnabled: false) {}
        case .stop:
            Color.clear
        case .none:
            Color.clear
        }
    }
}

struct MediaSliderView: View {
    @Binding var sliderValue: Double
    let duration: Double
    let accentColor: Color
    let labelColor: Color
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let currentDate: Date
    let playback: MediaProbeViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(timeString(from: sliderValue))
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(accentColor)
                .fixedSize(horizontal: true, vertical: false)

            CustomSlider(
                value: $sliderValue,
                range: 0...max(duration, 1),
                color: accentColor,
                dragging: $dragging,
                lastDragged: $lastDragged
            ) { newValue in
                playback.seek(to: newValue)
            }
            .frame(height: 5)

            Text(timeString(from: duration))
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: true, vertical: false)
        }
        .onChange(of: currentDate) { _, newDate in
            guard !dragging, playback.state.lastUpdated.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = playback.estimatedPlaybackPosition(at: newDate)
        }
        .onAppear {
            sliderValue = playback.estimatedPlaybackPosition()
        }
    }

    private func timeString(from seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let onValueChange: (Double) -> Void
    var onDragChange: ((Double) -> Void)? = nil

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 8 : 5)
            let rangeSpan = range.upperBound - range.lowerBound
            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width
            let dotSize = CGFloat(dragging ? 12 : 0)

            ZStack(alignment: .leading) {
                // Track empty
                Capsule()
                    .fill(color.opacity(0.18))
                    .frame(height: height)

                // Track filled
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: filledTrackWidth, height: height)

                // Glowing playhead dot
                if progress > 0.01 {
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: color.opacity(0.8), radius: dragging ? 6 : 3)
                        .offset(x: filledTrackWidth - dotSize / 2)
                }
            }
            .frame(height: max(height, dotSize))
            .contentShape(Rectangle().size(CGSize(width: width, height: 20)).offset(y: -5))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}

struct HoverButton: View {
    let icon: String
    var iconColor: Color = .white
    var scale: Image.Scale = .medium
    var contentTransition: ContentTransition = .symbolEffect
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 32 : 24)
        let effectiveIconColor = isEnabled ? iconColor : iconColor.opacity(0.5)

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isEnabled && isHovering ? iconColor.opacity(0.15) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(effectiveIconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .title2 : .system(size: 13, weight: .semibold))
                        }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = isEnabled && hovering
            }
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var playback: MediaProbeViewModel
    let accent: Color

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            playback.toggleFavoriteTrack()
        }
        .disabled(!playback.supportsFavorite)
        .opacity(playback.supportsFavorite ? 1 : 0.35)
    }

    private var iconName: String {
        playback.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        playback.isFavoriteTrack ? accent : accent.opacity(0.55)
    }
}

struct VolumeControlView: View {
    @ObservedObject var playback: MediaProbeViewModel
    let accent: Color
    @State private var volumeSliderValue = 0.5
    @State private var dragging = false
    @State private var lastVolumeUpdateTime = Date.distantPast

    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeIcon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent.opacity(0.8))
                .frame(width: 14)
            
            CustomSlider(
                value: $volumeSliderValue,
                range: 0.0...1.0,
                color: accent,
                dragging: $dragging,
                lastDragged: .constant(.distantPast),
                onValueChange: { newValue in
                    setSystemVolume(newValue)
                },
                onDragChange: { newValue in
                    let now = Date()
                    if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                        setSystemVolume(newValue)
                        lastVolumeUpdateTime = now
                    }
                }
            )
            .frame(width: 46, height: 5)
            
            Text("\(Int(volumeSliderValue * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 26, alignment: .trailing)
        }
        .onAppear {
            volumeSliderValue = getSystemVolume()
        }
    }
    
    private func setSystemVolume(_ level: Double) {
        playback.setVolume(to: level)
    }

    private func getSystemVolume() -> Double {
        (try? SystemAudioOutput.currentVolume()) ?? playback.state.volume
    }

    private var volumeIcon: String {
        if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

enum MediaControlSlot: String, CaseIterable, Identifiable {
    case shuffle
    case previous
    case goBackward
    case playPause
    case goForward
    case next
    case repeatMode
    case volume
    case favorite
    case stop
    case none

    var id: String { rawValue }

    static let allControls: [MediaControlSlot] = [
        .shuffle,
        .previous,
        .goBackward,
        .playPause,
        .goForward,
        .next,
        .repeatMode
    ]
}

struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
            }
        )
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat

    @State private var animate = false
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0

    init(
        _ text: Binding<String>,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        textColor: Color = .primary,
        backgroundColor: Color = .clear,
        minDuration: Double = 3.0,
        frameWidth: CGFloat = 200
    ) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                HStack(spacing: 20) {
                    Text(text)
                    Text(text)
                        .opacity(needsScrolling ? 1 : 0)
                }
                .id(text)
                .font(font)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: animate ? offset : 0)
                .animation(
                    animate
                        ? .linear(duration: Double(textSize.width / 30))
                            .delay(minDuration)
                            .repeatForever(autoreverses: false)
                        : .none,
                    value: animate
                )
                .background(backgroundColor)
                .modifier(MeasureSizeModifier())
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    textSize = CGSize(
                        width: size.width / 2,
                        height: NSFont.preferredFont(forTextStyle: nsFont).pointSize
                    )
                    animate = false
                    offset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        if needsScrolling {
                            animate = true
                            offset = -(textSize.width + 10)
                        }
                    }
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: textSize.height * 1.3)
    }
}
