import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct AgentResultsView: View {
    @ObservedObject var store: AgentResultStore
    var onContentSizeChange: ((CGSize) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if store.items.isEmpty {
                    emptyState
                } else {
                    content
                }
            }

            if !store.items.isEmpty {
                AgentResultsOverlayActions(store: store)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
        }
        .frame(minWidth: 160, minHeight: 100)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, cornerRadius: 0)
                .ignoresSafeArea()
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No agent results yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Items pushed by agents will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var content: some View {
        ScrollView {
            resultStack
        }
        .overlay(alignment: .top) {
            resultStack
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AgentResultsContentSizeKey.self,
                            value: proxy.size
                        )
                    }
                )
        }
        .onPreferenceChange(AgentResultsContentSizeKey.self) { size in
            onContentSizeChange?(size)
        }
    }

    private var resultStack: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                AgentResultListItem(
                    item: item,
                    store: store,
                    flushImageTopCorners: index == 0
                )
            }
        }
        .padding(.bottom, 0)
    }

    private var visibleItems: [AgentResultItem] {
        store.visibleBatches.flatMap(\.items)
    }
}

private struct AgentResultsOverlayActions: View {
    @ObservedObject var store: AgentResultStore

    var body: some View {
        HStack(spacing: 6) {
            if visibleItemCount > 1 {
                CopyFeedbackButton(systemName: "square.on.square", badge: visibleItemCount, help: "Copy all visible items") {
                    copyVisibleItems()
                }
            }
            IconActionButton(systemName: "xmark", help: "Close results") {
                AgentResultStore.shared.clear()
                AgentResultsWindowController.shared.hide()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var visibleItemCount: Int {
        store.visibleBatches.reduce(0) { $0 + $1.items.count }
    }

    private func copyVisibleItems() {
        let items = store.visibleBatches.flatMap(\.items)
        guard !items.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let fileURLs = items.compactMap(\.localFileURL)
        if !fileURLs.isEmpty {
            pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
            return
        }

        let text = items.compactMap(\.plainTextForCopy).joined(separator: "\n\n")
        if !text.isEmpty {
            pasteboard.setString(text, forType: .string)
        }
    }
}

private struct AgentResultsContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct AgentResultListItem: View {
    let item: AgentResultItem
    @ObservedObject var store: AgentResultStore
    var flushImageTopCorners: Bool

    var body: some View {
        AgentResultInteractiveContent(
            item: item,
            store: store,
            flushImageTopCorners: flushImageTopCorners
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentResultsSlideShow: View {
    let items: [AgentResultItem]
    @ObservedObject var store: AgentResultStore
    @State private var slideIndex = 0

    private var safeIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(0, slideIndex), items.count - 1)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                let current = items[safeIndex]
                ZStack {
                    AgentResultInteractiveContent(
                        item: current,
                        store: store,
                        flushImageTopCorners: true
                    )

                }
            }
        }
        .onChange(of: items.map(\.id)) { oldIDs, newIDs in
            if oldIDs.first != newIDs.first {
                slideIndex = 0
            } else {
                slideIndex = min(slideIndex, max(0, newIDs.count - 1))
            }
        }
        .onChange(of: items.count) { _, newCount in
            slideIndex = min(slideIndex, max(0, newCount - 1))
        }
    }

    private var shouldShowPagination: Bool {
        items.count > 1 || showsHistoryMore
    }

    private var showsHistoryMore: Bool {
        store.hasHistoryBatches && !store.showingHistory
    }
}

private struct AgentResultsSlideNavButton: View {
    let systemName: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.28)
        .help(help)
    }
}

private struct AgentResultsSlidePageIndicator: View {
    let count: Int
    let index: Int
    let showsHistoryMore: Bool
    let onSelect: (Int) -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Button {
                    onSelect(i)
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(i == index ? 0.55 : 0.2))
                        .frame(width: i == index ? 6 : 5, height: i == index ? 6 : 5)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show item \(i + 1)")
            }

            if showsHistoryMore {
                Button(action: onMore) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show previous results")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

/// Caption label: files always use the filename; text/link may use optional tool `title`.
private func agentResultCaptionLabel(_ item: AgentResultItem) -> String? {
    switch item.kind {
    case let .file(url):
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    case let .link(url):
        if let raw = item.title {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let host = url.host, !host.isEmpty { return host }
        return url.absoluteString
    case .text:
        if let raw = item.title {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

private func agentResultKindIcon(_ kind: AgentResultKind) -> String {
    switch kind {
    case .text: return "text.alignleft"
    case .link: return "link"
    case .file: return "doc.fill"
    }
}

private func isImageFile(_ url: URL) -> Bool {
    guard let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
          let contentType = resourceValues.contentType
    else { return false }
    return contentType.conforms(to: .image)
}

private enum AgentResultChromeMetrics {
    static let captionMaxWidth: CGFloat = 220
    /// Inner row height matches toolbar icon buttons (22pt).
    static let chromeCapsuleContentMinHeight: CGFloat = 22
    static let chromeCapsulePaddingH: CGFloat = 8
    static let chromeCapsulePaddingV: CGFloat = 6
}

private struct AgentResultInteractiveContent: View {
    let item: AgentResultItem
    @ObservedObject var store: AgentResultStore
    /// When true and the file is an image, top corners stay square so media meets the panel edge.
    var flushImageTopCorners: Bool = false

    private var caption: String? {
        agentResultCaptionLabel(item)
    }

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowBody(for: item) {
                ZStack {
                    slideBody(for: item, flushImageTopCorners: flushImageTopCorners)
                    if shouldUseContainerHoverOverlay(for: item) && isHovering {
                        resultHoverOverlay
                    }
                }
                .onHover { hovering in
                    guard shouldUseContainerHoverOverlay(for: item) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = hovering
                    }
                }
            }
        }
    }

    private func shouldShowBody(for item: AgentResultItem) -> Bool {
        true
    }

    private func shouldShowChromeRow(for item: AgentResultItem) -> Bool {
        false
    }

    private func shouldUseContainerHoverOverlay(for item: AgentResultItem) -> Bool {
        switch item.kind {
        case .text:
            return true
        case let .file(url):
            return !isImageFile(url)
        case .link:
            return false
        }
    }

    @ViewBuilder
    private func slideBody(for item: AgentResultItem, flushImageTopCorners: Bool) -> some View {
        switch item.kind {
        case let .text(markdown):
            AgentResultsMarkdownText(markdown: markdown, fontSize: 14, codeFontSize: 12)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 2)
        case let .link(url):
            LinkBody(url: url, title: item.title)
        case let .file(url):
            FileBody(
                url: url,
                maxImageHeight: 300,
                compact: false,
                flushTopCornersWhenImage: flushImageTopCorners,
                usesHoverControlsWhenImage: true
            )
        }
    }

    private func openItemIfPossible(_ item: AgentResultItem) {
        switch item.kind {
        case .text:
            return
        case let .link(url), let .file(url):
            NSWorkspace.shared.open(url)
        }
    }

    private var resultHoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
            VStack(spacing: 10) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    if case let .file(url) = item.kind {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: Capsule())
                        .help("Open file")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Reveal", systemImage: "magnifyingglass")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: Capsule())
                        .help("Reveal in Finder")
                    }
                    CopyFeedbackButton(help: "Copy") {
                        copyToPasteboard()
                    }
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(14)
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
}

// MARK: - Body subviews

/// Native Swift markdown renderer with Highlightr syntax highlighting and iosMath LaTeX support.
private struct AgentResultsMarkdownText: View {
    let markdown: String
    var fontSize: CGFloat = 14
    var codeFontSize: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NativeMarkdownRenderer(
            text: markdown,
            isUser: false,
            widthMode: .fillParent,
            style: .agentResults(
                colorScheme: colorScheme,
                fontSize: fontSize,
                codeFontSize: codeFontSize
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct LinkBody: View {
    let url: URL
    let title: String?
    @State private var isHovering = false

    private var displayTitle: String {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return url.host ?? url.absoluteString
    }

    var body: some View {
        ZStack {
            placeholder

            if isHovering {
                hoverOverlay
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "link")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
    }

    private var hoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
            VStack(spacing: 10) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help("Open link")

                    CopyFeedbackButton(help: "Copy link") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(url.absoluteString, forType: .string)
                        pasteboard.writeObjects([url as NSURL])
                    }
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(14)
        }
    }
}

private struct FileBody: View {
    let url: URL
    var maxImageHeight: CGFloat = 260
    var compact: Bool = false
    /// When showing a full-width image preview (not compact), square off top corners so the bitmap meets the panel edge.
    var flushTopCornersWhenImage: Bool = false
    var usesHoverControlsWhenImage = false
    @State private var isHovering = false
    @State private var icon: NSImage?
    @State private var previewImage: NSImage?
    @State private var thumbnailLoadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let previewImage {
                ZStack {
                    Group {
                        if compact {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: maxImageHeight)
                                .clipped()
                        } else if flushTopCornersWhenImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: maxImageHeight)
                        } else {
                            Image(nsImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: maxImageHeight)
                        }
                    }
                    if usesHoverControlsWhenImage && isHovering && isImageFile(url) {
                        imageHoverOverlay
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover { hovering in
                    guard usesHoverControlsWhenImage && isImageFile(url) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        isHovering = hovering
                    }
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Group {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: compact ? 48 : 96, height: compact ? 48 : 96)
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.system(size: compact ? 40 : 82))
                                .foregroundStyle(.secondary)
                                .frame(width: compact ? 48 : 96, height: compact ? 48 : 96)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 72 : max(150, maxImageHeight * 0.55))
                .background(
                    Rectangle()
                        .fill(Color.primary.opacity(0.035))
                )
            }
        }
        .onAppear {
            loadAsset()
        }
        .onChange(of: url) { _, _ in
            loadAsset()
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }

    private var imageHoverOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
            VStack(spacing: 10) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help("Open image")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help("Reveal in Finder")

                    CopyFeedbackButton(help: "Copy image") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([url as NSURL])
                    }
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(14)
        }
    }

    private func loadAsset() {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = nil

        let targetURL = url
        icon = NSWorkspace.shared.icon(forFile: targetURL.path)
        previewImage = nil

        if Self.isVideoFile(targetURL) {
            thumbnailLoadTask = Task {
                let img = await Self.videoThumbnail(for: targetURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard url == targetURL else { return }
                    previewImage = img
                }
            }
        } else {
            previewImage = NSImage(contentsOf: targetURL)
        }
    }

    private static func isVideoFile(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .movie) || type.conforms(to: .video) {
            return true
        }
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v", "mov", "mkv", "webm", "avi", "mpg", "mpeg":
            return true
        default:
            return false
        }
    }

    /// Frame at ~0.5s, then first frame; `NSImage(contentsOf:)` does not decode video.
    private static func videoThumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let maxSide: CGFloat = 1600
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        let samples = [
            CMTime(seconds: 0.5, preferredTimescale: 600),
            .zero,
        ]
        for time in samples {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                return NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
            } catch {
                continue
            }
        }
        return nil
    }
}

private struct MissingAssetPlaceholder: View {
    let systemName: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
private struct IconActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

private struct CopyFeedbackButton: View {
    var systemName = "doc.on.doc"
    var badge: Int? = nil
    let help: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.12)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.12)) {
                    copied = false
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: copied ? "checkmark" : systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                if let badge, badge > 1, !copied {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 5, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? .green : .secondary)
        .help(copied ? "Copied" : help)
    }
}
