import AppKit
import Combine
import NotchChatHistoryFeature
import SwiftUI
import AVFoundation

/// Accepts keyboard focus so the chat `TextField` works on a borderless panel.
private final class GeminiLiveChatKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class GeminiLiveChatHostingView<Content: View>: NSHostingView<Content> { }

// MARK: - PCM replay (Gemini voice turns)

@MainActor
private final class PCMAudioPlayerManager {
    static let shared = PCMAudioPlayerManager()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var onFinished: (() -> Void)?

    func play(_ pcmData: Data, sampleRate: Int = 24000, onFinished: @escaping () -> Void) {
        stop(notifyFinished: false)
        guard !pcmData.isEmpty else {
            onFinished()
            return
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            onFinished()
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        player.volume = 1

        self.engine = engine
        self.player = player
        self.onFinished = onFinished

        let scheduled = schedulePCMChunks(pcmData, format: format, player: player) { [weak self] in
            self?.finishPlayback()
        }
        guard scheduled else {
            finishPlayback()
            return
        }

        do {
            try engine.start()
            player.play()
        } catch {
            NotchLog.gemini.error("Chat PCM replay failed to start engine: \(error.localizedDescription, privacy: .public)")
            finishPlayback()
        }
    }

    func stop(notifyFinished: Bool = true) {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        if notifyFinished {
            onFinished?()
        }
        onFinished = nil
    }

    private func schedulePCMChunks(
        _ pcmData: Data,
        format: AVAudioFormat,
        player: AVAudioPlayerNode,
        completion: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        let bytesPerFrame = MemoryLayout<Int16>.size
        let framesTotal = pcmData.count / bytesPerFrame
        guard framesTotal > 0 else { return false }

        let maxFramesPerBuffer = 24_000
        var frameOffset = 0
        var buffersScheduled = 0

        while frameOffset < framesTotal {
            let framesThisBuffer = min(maxFramesPerBuffer, framesTotal - frameOffset)
            let byteOffset = frameOffset * bytesPerFrame
            let byteCount = framesThisBuffer * bytesPerFrame

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(framesThisBuffer)
            ) else {
                return false
            }
            buffer.frameLength = AVAudioFrameCount(framesThisBuffer)

            pcmData.withUnsafeBytes { raw in
                guard
                    let source = raw.baseAddress?.advanced(by: byteOffset),
                    let destination = buffer.int16ChannelData?.pointee
                else {
                    return
                }
                memcpy(destination, source, byteCount)
            }

            frameOffset += framesThisBuffer
            buffersScheduled += 1
            let isLast = frameOffset >= framesTotal
            player.scheduleBuffer(buffer) {
                if isLast {
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }

        return buffersScheduled > 0
    }

    private func finishPlayback() {
        let callback = onFinished
        onFinished = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        callback?()
    }
}

// MARK: - Typing Dots Indicator

private struct TypingIndicatorDots: View {
    @State private var dotOffset1: CGFloat = 0
    @State private var dotOffset2: CGFloat = 0
    @State private var dotOffset3: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.black.opacity(0.38))
                .frame(width: 6, height: 6)
                .offset(y: dotOffset1)
            Circle()
                .fill(Color.black.opacity(0.38))
                .frame(width: 6, height: 6)
                .offset(y: dotOffset2)
            Circle()
                .fill(Color.black.opacity(0.38))
                .frame(width: 6, height: 6)
                .offset(y: dotOffset3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .geminiChatGlassBubble(cornerRadius: 12)
        .onAppear {
            let animation = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
            withAnimation(animation) {
                dotOffset1 = -4
            }
            withAnimation(animation.delay(0.18)) {
                dotOffset2 = -4
            }
            withAnimation(animation.delay(0.36)) {
                dotOffset3 = -4
            }
        }
    }
}

// MARK: - Replay button (completed turns only)

private struct ReplayAudioButton: View {
    let audioData: Data
    let sampleRate: Int
    let replayPCM: (Data, Int, @escaping () -> Void) -> Void

    private let playbackInstanceID = UUID()
    @State private var isPlaying = false

    var body: some View {
        Button {
            if isPlaying {
                isPlaying = false
                PCMAudioPlayerManager.shared.stop()
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name("StopAllAudioPlayback"),
                    object: playbackInstanceID
                )
                isPlaying = true
                replayPCM(audioData, sampleRate) {
                    isPlaying = false
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isPlaying ? "stop.fill" : "speaker.wave.2")
                    .font(.system(size: 10, weight: .semibold))
                Text(Localization.get(isPlaying ? "Stop" : "Replay"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.87))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .geminiChatGlassCapsule()
        }
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StopAllAudioPlayback"))) { notification in
            if let senderID = notification.object as? UUID, senderID == playbackInstanceID {
                return
            }
            guard isPlaying else { return }
            isPlaying = false
            PCMAudioPlayerManager.shared.stop()
        }
    }
}

// MARK: - Turn Views

@MainActor
private func chatReplayPCM(_ data: Data, sampleRate: Int, onFinished: @escaping () -> Void) {
    PCMAudioPlayerManager.shared.play(data, sampleRate: sampleRate, onFinished: onFinished)
}

private enum GeminiChatMarkdownLayout {
    /// Matches caption overlay hug width, scaled for the 420pt chat panel.
    static let bubbleContentMaxWidth: CGFloat = 360
}

// MARK: - Glass morphism surfaces (floating bubbles on transparent panel)

private struct GeminiChatGlassSurface: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: cornerRadius
            )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.overlay)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}

private extension View {
    func geminiChatGlassBubble(cornerRadius: CGFloat = 16) -> some View {
        self
            .background {
                GeminiChatGlassSurface(cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .environment(\.colorScheme, .light)
    }

    func geminiChatGlassCapsule() -> some View {
        self
            .background {
                GeminiChatGlassSurface(cornerRadius: 999)
            }
            .clipShape(Capsule())
            .environment(\.colorScheme, .light)
    }
}

private struct GeminiChatUserBubble: View {
    let text: String

    var body: some View {
        NotchMarkdownView(
            text: text,
            isUser: true,
            widthMode: .hugContent(maxWidth: GeminiChatMarkdownLayout.bubbleContentMaxWidth)
        )
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .geminiChatGlassBubble()
    }
}

private struct GeminiChatModelBubble: View {
    let text: String
    let audioData: Data?
    let audioSampleRate: Int
    let replayPCM: (Data, Int, @escaping () -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchMarkdownView(
                text: text,
                isUser: false,
                widthMode: .hugContent(maxWidth: GeminiChatMarkdownLayout.bubbleContentMaxWidth)
            )
            .textSelection(.enabled)

            if let audioData, !audioData.isEmpty {
                ReplayAudioButton(
                    audioData: audioData,
                    sampleRate: audioSampleRate,
                    replayPCM: replayPCM
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .geminiChatGlassBubble()
    }
}

private struct UserTurnView: View {
    let msg: LiveChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            GeminiChatUserBubble(text: msg.text)
        }
    }
}

private struct ModelTurnView: View {
    let msg: LiveChatMessage
    let replayPCM: (Data, Int, @escaping () -> Void) -> Void

    var body: some View {
        HStack {
            GeminiChatModelBubble(
                text: msg.text,
                audioData: msg.audioData,
                audioSampleRate: msg.audioSampleRate,
                replayPCM: replayPCM
            )
            Spacer(minLength: 48)
        }
    }
}

private struct ToolCallTurnView: View {
    let action: ToolActionToast
    let count: Int

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                if count > 1 {
                    Text("×\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.08)))
                }
            }
            .foregroundStyle(Color.black.opacity(0.87))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .geminiChatGlassBubble()
            Spacer(minLength: 48)
        }
    }
}

private struct CompactResultRowView: View {
    let item: AgentResultItem
    @State private var isHovering = false
    @State private var thumbnail: NSImage? = nil

    var iconName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .file: return "doc.fill"
        }
    }

    var title: String {
        switch item.kind {
        case let .file(url):
            return url.lastPathComponent
        case let .link(url):
            if let t = item.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            return url.host ?? url.lastPathComponent
        case let .text(md):
            if let t = item.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            return String(md.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        }
    }

    var subtitle: String? {
        switch item.kind {
        case let .file(url):
            return url.pathExtension.uppercased()
        case let .link(url):
            return url.host
        case .text:
            return "Text"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isHovering {
                HStack(spacing: 5) {
                    if case let .file(url) = item.kind {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Localization.get("Open file"))

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Localization.get("Reveal in Finder"))
                    } else if case let .link(url) = item.kind {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.black.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Localization.get("Open link"))
                    }

                    Button {
                        copyToPasteboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(Localization.get("Copy"))
                }
                .foregroundStyle(Color.black.opacity(0.68))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.24))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            openItem()
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func openItem() {
        switch item.kind {
        case let .file(url), let .link(url):
            NSWorkspace.shared.open(url)
        case .text:
            copyToPasteboard()
        }
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case let .text(string):
            pasteboard.setString(string, forType: .string)
        case let .link(url):
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.writeObjects([url as NSURL])
        case let .file(url):
            pasteboard.writeObjects([url as NSURL])
        }
    }

    private func loadThumbnail() {
        guard case let .file(url) = item.kind else { return }
        let path = url.path
        let hasImageExtension = ["png", "jpg", "jpeg", "gif", "tiff", "heic"].contains(url.pathExtension.lowercased())
        if hasImageExtension {
            if let image = NSImage(contentsOfFile: path) {
                self.thumbnail = image
            }
        } else {
            self.thumbnail = NSWorkspace.shared.icon(forFile: path)
        }
    }
}

private struct InlineAgentResultsBubble: View {
    let batchId: UUID
    @ObservedObject var store = AgentResultStore.shared

    private var items: [AgentResultItem] {
        store.items.filter { $0.batchId == batchId }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .opacity(0.08)
                                .padding(.horizontal, 8)
                        }
                        CompactResultRowView(item: item)
                    }

                    if items.count > 4 {
                        Divider()
                            .opacity(0.08)
                            .padding(.horizontal, 8)
                        HStack {
                            Spacer()
                            Text(String(format: Localization.get("See more %d results…"), items.count - 4))
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.5))
                                .padding(.vertical, 5)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            AgentResultStore.shared.showingHistory = true
                            AgentResultsWindowController.shared.toggle()
                        }
                    }
                }
                .padding(.vertical, 3)
                .geminiChatGlassBubble()
                .frame(maxWidth: GeminiChatMarkdownLayout.bubbleContentMaxWidth)
            }
        }
    }
}

private struct InlineExecApprovalView: View {
    @ObservedObject var gemini: GeminiLiveViewModel

    var body: some View {
        if let approval = gemini.currentPendingExecApproval {
            HStack {
                GeminiExecApprovalCard(
                    request: approval,
                    queueCount: gemini.pendingExecApprovals.count,
                    onApproveOnce: { gemini.approveCurrentExecApprovalOnce() },
                    onApproveExact: { gemini.approveCurrentExecApprovalExact() },
                    onApproveFamily: { gemini.approveCurrentExecApprovalFamily() },
                    onDeny: { gemini.denyCurrentExecApproval() }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .geminiChatGlassBubble()
                .frame(maxWidth: GeminiChatMarkdownLayout.bubbleContentMaxWidth)
                Spacer(minLength: 48)
            }
            .id("inline-exec-approval")
        }
    }
}

// MARK: - Content View

private struct GeminiLiveChatInputContentView: View {
    @ObservedObject var gemini: GeminiLiveViewModel
    @State private var draft = ""
    @State private var suggestion = ""
    @State private var historyIndex: Int? = nil
    @State private var originalDraft = ""
    @State private var isConversationAutoHidden = false
    @State private var isConversationHovered = false
    @State private var isInputHovered = false
    @State private var isInputCollapsed = false
    @State private var autoHideTask: Task<Void, Never>?
    @State private var inputCollapseTask: Task<Void, Never>?

    private var suggestionColor: Color { .black.opacity(0.28) }
    private var inputTextColor: Color { .black.opacity(0.88) }
    private var sendIconColor: Color {
        let opacity = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.22 : 0.88
        return .black.opacity(opacity)
    }

    private var shouldShowConversation: Bool {
        if gemini.currentPendingExecApproval != nil { return true }
        return gemini.showTranscriptOverlay && (!gemini.transcriptOverlayAutoHide || !isConversationAutoHidden)
    }

    var body: some View {
        chatBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .onAppear {
                scheduleConversationAutoHide()
                applyInputDisplayMode()
            }
            .onChange(of: gemini.liveChatMessages) { _, _ in
                revealConversationAndScheduleAutoHide()
            }
            .onChange(of: gemini.userTranscript) { _, _ in
                revealConversationAndScheduleAutoHide()
            }
            .onChange(of: gemini.modelTranscript) { _, _ in
                revealConversationAndScheduleAutoHide()
            }
            .onChange(of: gemini.isModelThinking) { _, _ in
                revealConversationAndScheduleAutoHide()
            }
            .onChange(of: gemini.pendingExecApprovals) { _, _ in
                revealConversationAndScheduleAutoHide()
            }
            .onChange(of: gemini.showTranscriptOverlay) { _, showConversation in
                if showConversation {
                    revealConversationAndScheduleAutoHide()
                } else {
                    autoHideTask?.cancel()
                    isConversationAutoHidden = false
                }
            }
            .onChange(of: gemini.transcriptOverlayAutoHide) { _, enabled in
                if enabled {
                    scheduleConversationAutoHide()
                } else {
                    autoHideTask?.cancel()
                    isConversationAutoHidden = false
                }
            }
            .onChange(of: gemini.liveChatInputDisplayMode) { _, _ in
                applyInputDisplayMode()
            }
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            if shouldShowConversation {
                conversationArea
                    .transition(.opacity)
            }

            if gemini.showLiveChatInput {
                inputBar
                    .padding(.top, shouldShowConversation ? 0 : 12)
            }
        }
    }

    private var conversationArea: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(gemini.liveChatMessages) { msg in
                        if let toolAction = msg.toolAction {
                            VStack(alignment: .leading, spacing: 8) {
                                ToolCallTurnView(action: toolAction, count: msg.toolActionCount)
                                if let batchId = msg.agentResultBatchID {
                                    HStack {
                                        InlineAgentResultsBubble(batchId: batchId)
                                        Spacer(minLength: 48)
                                    }
                                    .padding(.leading, 12)
                                }
                            }
                        } else if msg.isUser {
                            UserTurnView(msg: msg)
                        } else {
                            ModelTurnView(msg: msg, replayPCM: chatReplayPCM)
                        }
                    }

                    if gemini.currentPendingExecApproval != nil {
                        InlineExecApprovalView(gemini: gemini)
                    }

                    if !gemini.userTranscript.isEmpty {
                        HStack {
                            Spacer(minLength: 48)
                            GeminiChatUserBubble(text: gemini.userTranscript)
                        }
                        .id("in-progress-user")
                    } else if gemini.isModelThinking && gemini.modelTranscript.isEmpty {
                        HStack {
                            TypingIndicatorDots()
                            Spacer(minLength: 48)
                        }
                        .id("in-progress-thinking")
                    } else if !gemini.modelTranscript.isEmpty {
                        HStack {
                            GeminiChatModelBubble(
                                text: gemini.modelTranscript,
                                audioData: nil,
                                audioSampleRate: 24000,
                                replayPCM: chatReplayPCM
                            )
                            Spacer(minLength: 48)
                        }
                        .id("in-progress-model")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 36)
                .padding(.bottom, 14)
            }
            .onChange(of: gemini.liveChatMessages) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
            .onChange(of: gemini.userTranscript) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
            .onChange(of: gemini.modelTranscript) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
            .onChange(of: gemini.pendingExecApprovals) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
            .onAppear {
                scrollToBottom(proxy: scrollProxy)
            }
        }
        .onHover { hovering in
            isConversationHovered = hovering
            if hovering {
                autoHideTask?.cancel()
            } else {
                scheduleConversationAutoHide()
            }
        }
    }

    private var inputBar: some View {
        Group {
            if isInputCollapsed {
                Image(systemName: "message.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.72))
                    .frame(width: 42, height: 42)
                    .geminiChatGlassBubble()
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if !suggestion.isEmpty && draft.count < suggestion.count {
                            Text(suggestion)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(suggestionColor)
                                .padding(.leading, 0)
                        }

                        TextField("Message…", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(inputTextColor)
                            .onSubmit(commitSend)
                            .disabled(!gemini.canSendLiveInput)
                            .onChange(of: draft) { _, newValue in
                                if historyIndex == nil {
                                    updateSuggestion(for: newValue)
                                }
                                if newValue.isEmpty {
                                    scheduleInputCollapse()
                                } else {
                                    expandInput()
                                    inputCollapseTask?.cancel()
                                }
                            }
                            .onKeyPress(.rightArrow) {
                                if !suggestion.isEmpty && draft.count < suggestion.count {
                                    draft = suggestion
                                    suggestion = ""
                                    return .handled
                                }
                                return .ignored
                            }
                            .onKeyPress(.tab) {
                                if !suggestion.isEmpty && draft.count < suggestion.count {
                                    draft = suggestion
                                    suggestion = ""
                                    return .handled
                                }
                                return .ignored
                            }
                            .onKeyPress(.upArrow) {
                                return navigateHistory(direction: -1)
                            }
                            .onKeyPress(.downArrow) {
                                return navigateHistory(direction: 1)
                            }
                    }

                    Button(action: commitSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(sendIconColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !gemini.canSendLiveInput
                            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .focusEffectDisabled()
                .geminiChatGlassBubble()
                .clipShape(Capsule())
                .contentShape(Capsule())
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .light)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isInputCollapsed)
        .onHover { hovering in
            isInputHovered = hovering
            if hovering {
                expandInput()
                inputCollapseTask?.cancel()
            } else {
                scheduleInputCollapse()
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func expandInput() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isInputCollapsed = false
        }
    }

    private func applyInputDisplayMode() {
        inputCollapseTask?.cancel()
        switch gemini.liveChatInputDisplayMode {
        case .autoCollapse:
            scheduleInputCollapse()
        case .alwaysVisible, .hidden:
            expandInput()
        }
    }

    private func scheduleInputCollapse() {
        inputCollapseTask?.cancel()
        guard gemini.liveChatInputDisplayMode == .autoCollapse else { return }
        guard !isInputHovered else { return }
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        inputCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard gemini.liveChatInputDisplayMode == .autoCollapse else { return }
            guard !isInputHovered else { return }
            guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isInputCollapsed = true
            }
        }
    }

    private func revealConversationAndScheduleAutoHide() {
        guard gemini.showTranscriptOverlay else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            isConversationAutoHidden = false
        }
        scheduleConversationAutoHide()
    }

    private func scheduleConversationAutoHide() {
        autoHideTask?.cancel()
        guard gemini.showTranscriptOverlay, gemini.transcriptOverlayAutoHide else { return }
        guard !isConversationHovered else { return }
        guard !gemini.isModelThinking, gemini.modelTranscript.isEmpty, gemini.userTranscript.isEmpty else { return }

        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1620))
            guard !Task.isCancelled else { return }
            guard gemini.showTranscriptOverlay, gemini.transcriptOverlayAutoHide else { return }
            guard !isConversationHovered else { return }
            guard !gemini.isModelThinking, gemini.modelTranscript.isEmpty, gemini.userTranscript.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                isConversationAutoHidden = true
            }
        }
    }

    private func updateSuggestion(for newValue: String) {
        if let found = GeminiLiveChatHistoryStore.shared.getSuggestion(for: newValue) {
            suggestion = found
        } else {
            suggestion = ""
        }
    }

    private func navigateHistory(direction: Int) -> KeyPress.Result {
        let history = GeminiLiveChatHistoryStore.shared.history
        guard !history.isEmpty else { return .ignored }

        if historyIndex == nil {
            originalDraft = draft
        }

        let currentIndex = historyIndex ?? -1
        let nextIndex = currentIndex + (direction * -1) // Up is -1 (previous), Down is +1 (next)

        if nextIndex < 0 {
            historyIndex = nil
            draft = originalDraft
            updateSuggestion(for: draft)
            return .handled
        } else if nextIndex < history.count {
            historyIndex = nextIndex
            draft = history[nextIndex]
            suggestion = "" // No suggestion while navigating history
            return .handled
        }

        return .ignored
    }

    private func commitSend() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard gemini.sendLiveChatMessage(trimmed) else { return }
        draft = ""
        suggestion = ""
        historyIndex = nil
    }
}

// MARK: - Window controller

@MainActor
final class GeminiLiveChatInputWindowController {
    private var panel: NSPanel?
    private var hostingView: GeminiLiveChatHostingView<GeminiLiveChatInputContentView>?
    private var cancellables = Set<AnyCancellable>()
    private var moveObserver: NSObjectProtocol?
    private weak var preferredScreen: NSScreen?
    private weak var gemini: GeminiLiveViewModel?

    private let panelWidth: CGFloat = 420
    private let panelHeight: CGFloat = 480
    private let defaultsKey = "dev.notch.gemini-live-chat-panel.frame"

    func setPreferredScreen(_ newScreen: NSScreen?) {
        preferredScreen = newScreen
        guard let panel, hostingView != nil else { return }
        if !frameIntersectsAnyVisibleWorkspace(panel.frame) {
            let sc = screenForPlacement()
            let target = clampFrame(panel.frame, to: sc)
            panel.setFrame(target, display: true)
            hostingView?.frame = CGRect(origin: .zero, size: target.size)
        }
    }

    func observe(gemini: GeminiLiveViewModel) {
        self.gemini = gemini
        cancellables.removeAll()

        Publishers.CombineLatest4(gemini.$lifecycleState, gemini.$showTranscriptOverlay, gemini.$showLiveChatInput, gemini.$pendingExecApprovals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lifecycleState, showConversation, showInput, pendingApprovals in
                guard let self else { return }
                if lifecycleState.preservesSessionUI, showConversation || showInput || !pendingApprovals.isEmpty {
                    self.ensurePanel(gemini: gemini)
                    self.panel?.orderFrontRegardless()
                } else {
                    self.panel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    func showIfNeeded() {
        guard let gemini else { return }
        ensurePanel(gemini: gemini)
        panel?.orderFrontRegardless()
    }

    func stopObserving() {
        gemini = nil
        cancellables.removeAll()
        removeMoveObserver()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Private

    private func screenForPlacement() -> NSScreen {
        preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func defaultFrame(on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let x = vf.midX - panelWidth / 2
        let y = vf.minY + 72
        return CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func loadSavedFrame() -> CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveFrame(_ frame: CGRect) {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height],
            forKey: defaultsKey
        )
    }

    private func dominantScreen(forWindowFrame windowFrame: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.frame)
            let area = max(0, inter.width) * max(0, inter.height)
            if area > bestArea {
                bestArea = area
                best = s
            }
        }
        return best
    }

    private func clampFrame(_ frame: CGRect, to screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var f = frame
        let minVisible: CGFloat = 48
        f.origin.x = min(max(f.origin.x, vf.minX - f.width + minVisible), vf.maxX - minVisible)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - minVisible)
        return f
    }

    private func frameIntersectsAnyVisibleWorkspace(_ windowFrame: CGRect) -> Bool {
        let minOverlap: CGFloat = 32
        for s in NSScreen.screens {
            let inter = windowFrame.intersection(s.visibleFrame)
            if inter.width >= minOverlap, inter.height >= minOverlap {
                return true
            }
        }
        return false
    }

    private func removeMoveObserver() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
    }

    private func ensurePanel(gemini: GeminiLiveViewModel) {
        let sc = screenForPlacement()

        if let hv = hostingView {
            hv.rootView = GeminiLiveChatInputContentView(gemini: gemini)
            return
        }

        let saved = loadSavedFrame()
        let initial: CGRect
        if let saved {
            let onScreen = dominantScreen(forWindowFrame: saved) ?? sc
            var correctedFrame = saved
            if abs(saved.width - panelWidth) > 5.0 || abs(saved.height - panelHeight) > 5.0 {
                correctedFrame = CGRect(x: saved.origin.x, y: saved.origin.y, width: panelWidth, height: panelHeight)
            }
            initial = clampFrame(correctedFrame, to: onScreen)
        } else {
            initial = defaultFrame(on: sc)
        }

        let panel = GeminiLiveChatKeyPanel(
            contentRect: initial,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        let root = GeminiLiveChatInputContentView(gemini: gemini)
        let hv = GeminiLiveChatHostingView(rootView: root)
        hv.frame = CGRect(origin: .zero, size: initial.size)
        hv.autoresizingMask = [.width, .height]
        panel.contentView = hv

        self.panel = panel
        self.hostingView = hv

        let trackedWindowNumber = panel.windowNumber
        removeMoveObserver()
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let w = NSApp.windows.first(where: { $0.windowNumber == trackedWindowNumber }) else { return }
                self.saveFrame(w.frame)
            }
        }
    }
}
