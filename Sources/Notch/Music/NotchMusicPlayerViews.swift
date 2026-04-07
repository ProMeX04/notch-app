import SwiftUI
struct ExpandedAlbumArtView: View {
    @ObservedObject var playback: MusicProbeViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if playback.isPlaying {
                Image(nsImage: playback.albumArt)
                    .resizable()
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(x: 1.3, y: 1.4)
                    .rotationEffect(.degrees(92))
                    .blur(radius: 40)
                    .opacity(0.5)
            }

            Button {
                playback.openCurrentApp()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: playback.albumArt)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .frame(width: 90, height: 90)

                    if let appIcon = playback.appIcon, !playback.usingAppIconForArtwork {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .offset(x: 10, y: 10)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(2)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(playback.isPlaying ? 1 : 0.85)

            Rectangle()
                .fill(Color.black)
                .opacity(playback.isPlaying ? 0 : 0.8)
                .blur(radius: 50)
                .frame(width: 90, height: 90)
        }
        .frame(width: 100, height: 100)
    }
}

struct ExpandedMusicControlsView: View {
    @ObservedObject var playback: MusicProbeViewModel
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
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(
                            .constant(primaryText),
                            font: .headline,
                            nsFont: .headline,
                            textColor: .white,
                            frameWidth: geometry.size.width
                        )
                        MarqueeText(
                            .constant(secondaryText),
                            font: .headline,
                            nsFont: .headline,
                            textColor: accent.ensureMinimumBrightness(factor: 0.6),
                            frameWidth: geometry.size.width
                        )
                        .fontWeight(.medium)
                    }

                    TimelineView(.animation(minimumInterval: playback.state.playbackRate > 0 ? 0.1 : nil)) { timeline in
                        MusicSliderView(
                            sliderValue: $sliderValue,
                            duration: playback.state.duration,
                            labelColor: accent.ensureMinimumBrightness(factor: 0.6),
                            dragging: $dragging,
                            lastDragged: $lastDragged,
                            currentDate: timeline.date,
                            playback: playback
                        )
                    }
                    .padding(.top, 5)
                    .frame(height: 36)
                }
            }
            .frame(height: 76)
            .padding(.top, 10)
            .padding(.leading, 5)

            HStack(spacing: 4) {
                ForEach(MusicControlSlot.allControls) { slot in
                    slotView(for: slot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlSlot) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: playback.isShuffled ? .red : .primary, scale: .medium) {
                playback.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                playback.previousTrack()
            }
        case .playPause:
            HoverButton(icon: playback.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                playback.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                playback.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                playback.toggleRepeat()
            }
        case .favorite:
            FavoriteControlButton(playback: playback)
        case .volume:
            VolumeControlView(playback: playback)
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                playback.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                playback.skip(seconds: 15)
            }
        case .stop:
            HoverButton(icon: "stop.fill", scale: .medium) {
                playback.stop()
            }
        case .none:
            Color.clear.frame(width: 30, height: 30)
        }
    }

    private var repeatIcon: String {
        switch playback.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch playback.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    let duration: Double
    let labelColor: Color
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let currentDate: Date
    let playback: MusicProbeViewModel

    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...max(duration, 1),
                color: .white,
                dragging: $dragging,
                lastDragged: $lastDragged
            ) { newValue in
                playback.seek(to: newValue)
            }
            .frame(height: 10)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundStyle(labelColor)
            .font(.caption)
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound
            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
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
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var contentTransition: ContentTransition = .symbolEffect
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var playback: MusicProbeViewModel

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
        playback.isFavoriteTrack ? .red : .primary
    }
}

struct VolumeControlView: View {
    @ObservedObject var playback: MusicProbeViewModel
    @State private var volumeSliderValue = 0.5
    @State private var dragging = false
    @State private var showVolumeSlider = false
    @State private var lastVolumeUpdateTime = Date.distantPast

    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if playback.supportsVolumeControl {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(playback.supportsVolumeControl ? .white : .gray)
            }
            .buttonStyle(.plain)
            .disabled(!playback.supportsVolumeControl)
            .frame(width: 24)

            if showVolumeSlider && playback.supportsVolumeControl {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(.distantPast),
                    onValueChange: { newValue in
                        playback.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            playback.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onChange(of: playback.state.volume) { _, volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onChange(of: playback.supportsVolumeControl) { _, supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                volumeSliderValue = playback.volume
            }
        }
    }

    private var volumeIcon: String {
        if !playback.supportsVolumeControl {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
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

enum MusicControlSlot: String, CaseIterable, Identifiable {
    case shuffle
    case previous
    case playPause
    case next
    case repeatMode
    case volume
    case favorite
    case goBackward
    case goForward
    case stop
    case none

    var id: String { rawValue }

    /// Một hàng: không tăng chiều cao panel (stop/volume/favorite bỏ — không ổn định trên mọi app).
    static let allControls: [MusicControlSlot] = [
        .shuffle,
        .goBackward,
        .previous,
        .playPause,
        .next,
        .goForward,
        .repeatMode,
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
