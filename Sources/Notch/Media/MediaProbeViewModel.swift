import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MediaProbeViewModel: ObservableObject {
    @Published private(set) var state: PlaybackState = .init(bundleIdentifier: "")
    @Published private(set) var albumArt: NSImage?
    @Published private(set) var accentColor: NSColor = .white
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var usingAppIconForArtwork = false
    @Published private(set) var showCompactLiveActivity = false
    @Published private(set) var isPlayerIdle = true
    
    @AppStorage("app_language") private var appLanguage: String = "English"

    private let controller: (any MediaControllerProtocol)?
    private let workspace: MediaWorkspaceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var artworkComputationToken: UUID?
    private var debounceIdleTask: Task<Void, Never>?
    private var visualSignature = VisualSignature.empty

    init(
        controller: (any MediaControllerProtocol)? = NowPlayingController(),
        workspace: MediaWorkspaceProtocol = MediaWorkspace.shared
    ) {
        self.controller = controller
        self.workspace = workspace
        updateVisualState(for: state)

        controller?.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }

                let previousState = self.state
                let playbackChanged = state.isPlaying != previousState.isPlaying
                self.state = state

                if playbackChanged {
                    withAnimation(.smooth) {
                        self.updateIdleState(isPlaying: state.isPlaying)
                    }
                }

                self.refreshLiveActivityVisibility()
                self.updateVisualState(for: state)
            }
            .store(in: &cancellables)
    }

    var primaryText: String {
        state.title.isEmpty ? Localization.get("Nothing Playing", lang: appLanguage) : state.title
    }

    var secondaryText: String {
        if !state.artist.isEmpty {
            return state.artist
        }

        return sourceLabel
    }

    var sourceLabel: String {
        switch state.bundleIdentifier {
        case "com.apple.Music":
            return "Apple Music"
        case "com.spotify.client":
            return "Spotify"
        case let bundleID where bundleID.contains("youtube"):
            return "YouTube Music"
        default:
            return "System Media"
        }
    }

    var isPlaying: Bool {
        state.isPlaying
    }

    var canTogglePlayback: Bool {
        state.canTogglePlayback
    }

    var canSkipToPreviousTrack: Bool {
        state.canSkipToPreviousTrack
    }

    var canSkipToNextTrack: Bool {
        state.canSkipToNextTrack
    }

    var canSkipBackward15Seconds: Bool {
        state.canSkipBackward15Seconds
    }

    var canSkipForward15Seconds: Bool {
        state.canSkipForward15Seconds
    }

    var volume: Double {
        state.volume
    }

    var supportsVolumeControl: Bool {
        controller?.supportsVolumeControl ?? false
    }

    var supportsFavorite: Bool {
        controller?.supportsFavorite ?? false
    }

    var isFavoriteTrack: Bool {
        state.isFavorite
    }

    var hasTrack: Bool {
        state.hasTrackMetadata
    }

    func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard state.isPlaying else {
            return min(state.currentTime, state.duration)
        }

        let timeDifference = date.timeIntervalSince(state.lastUpdated)
        let estimated = state.currentTime + (timeDifference * state.playbackRate)
        return min(max(0, estimated), state.duration)
    }

    func togglePlay() {
        Task {
            await controller?.togglePlay()
        }
    }

    func play() {
        Task {
            await controller?.play()
        }
    }

    func pause() {
        Task {
            await controller?.pause()
        }
    }

    func stop() {
        Task {
            await controller?.stop()
        }
    }

    func nextTrack() {
        Task {
            await controller?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await controller?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await controller?.seek(to: position)
        }
    }

    func skip(seconds: TimeInterval) {
        let newPosition = min(max(0, state.currentTime + seconds), state.duration)
        seek(to: newPosition)
    }

    func toggleFavoriteTrack() {
        Task {
            await controller?.setFavorite(!state.isFavorite)
        }
    }

    func setVolume(to level: Double) {
        Task {
            await controller?.setVolume(level)
        }
    }

    func openCurrentApp() {
        let bundleID = state.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }

        guard let url = workspace.applicationURL(forBundleIdentifier: bundleID) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration)
    }

    func shutdown() {
        debounceIdleTask?.cancel()
        controller?.shutdown()
    }

    private func updateVisualState(for state: PlaybackState) {
        let nextSignature = VisualSignature(
            bundleIdentifier: state.bundleIdentifier,
            artwork: state.artwork
        )

        guard nextSignature != visualSignature else { return }
        visualSignature = nextSignature

        updateAppIcon(for: state.bundleIdentifier)
        updateAlbumArt(using: state)
        updateAccentColor()
    }

    private func updateAppIcon(for bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty,
              let appURL = workspace.applicationURL(forBundleIdentifier: bundleIdentifier) else {
            appIcon = nil
            return
        }

        appIcon = workspace.icon(forFile: appURL.path)
    }

    private func updateAlbumArt(using state: PlaybackState) {
        guard state.hasMediaContext else {
            albumArt = nil
            usingAppIconForArtwork = false
            return
        }

        if let artworkData = state.artwork, let image = NSImage(data: artworkData) {
            albumArt = image
            usingAppIconForArtwork = false
            return
        }

        if shouldPreserveCurrentArtwork(for: state) {
            return
        }

        albumArt = nil
        usingAppIconForArtwork = false
    }

    private func shouldPreserveCurrentArtwork(for state: PlaybackState) -> Bool {
        guard albumArt != nil else { return false }
        return state.hasMediaContext || showCompactLiveActivity || !isPlayerIdle
    }

    private func updateAccentColor() {
        artworkComputationToken = nil

        guard let image = albumArt else {
            accentColor = .white
            return
        }
        let token = UUID()
        artworkComputationToken = token

        image.averageColor { [weak self] color in
            Task { @MainActor in
                guard let self, self.artworkComputationToken == token else { return }
                self.accentColor = color ?? .white
            }
        }
    }

    private func updateIdleState(isPlaying: Bool) {
        if isPlaying {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
            return
        }

        debounceIdleTask?.cancel()
        debounceIdleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            withAnimation(.smooth) {
                self.isPlayerIdle = !self.state.isPlaying
                self.refreshLiveActivityVisibility()
            }
        }
    }

    private func refreshLiveActivityVisibility() {
        let previousValue = showCompactLiveActivity
        let shouldShowCompactLiveActivity = state.hasMediaContext && (state.isPlaying || !isPlayerIdle)

        if showCompactLiveActivity != shouldShowCompactLiveActivity {
            withAnimation(.smooth) {
                showCompactLiveActivity = shouldShowCompactLiveActivity
            }
        } else {
            showCompactLiveActivity = shouldShowCompactLiveActivity
        }

        if previousValue && !showCompactLiveActivity {
            updateAlbumArt(using: state)
            updateAccentColor()
        }
    }
}

private struct VisualSignature: Equatable {
    let bundleIdentifier: String
    let artwork: Data?

    static let empty = VisualSignature(bundleIdentifier: "", artwork: nil)
}
