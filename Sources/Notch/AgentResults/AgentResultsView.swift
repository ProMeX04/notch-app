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
        .frame(minWidth: 320, minHeight: 100)
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
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                AgentResultListItem(
                    item: item,
                    store: store,
                    flushImageTopCorners: index == 0
                )
            }
        }
        .padding(.bottom, 10)
    }

    private var visibleItems: [AgentResultItem] {
        store.visibleBatches.flatMap(\.items)
    }
}

private struct AgentResultsOverlayActions: View {
    @ObservedObject var store: AgentResultStore

    var body: some View {
        HStack(spacing: 6) {
            CopyFeedbackButton(help: "Copy all visible items") {
                copyVisibleItems()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
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

                    if items.count > 1 {
                        HStack(alignment: .center, spacing: 0) {
                            AgentResultsSlideNavButton(
                                systemName: "chevron.left",
                                enabled: safeIndex > 0,
                                help: "Previous"
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    slideIndex = safeIndex - 1
                                }
                            }

                            Spacer(minLength: 0).allowsHitTesting(false)

                            AgentResultsSlideNavButton(
                                systemName: "chevron.right",
                                enabled: safeIndex < items.count - 1,
                                help: "Next"
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    slideIndex = safeIndex + 1
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    if shouldShowPagination {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0).allowsHitTesting(false)
                            AgentResultsSlidePageIndicator(
                                count: items.count,
                                index: safeIndex,
                                showsHistoryMore: showsHistoryMore,
                                onSelect: { index in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        slideIndex = index
                                    }
                                },
                                onMore: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        store.showingHistory = true
                                    }
                                }
                            )
                                .padding(.bottom, 6)
                        }
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            slideBody(for: item, flushImageTopCorners: flushImageTopCorners)
                .contentShape(Rectangle())
                .onTapGesture {
                    openItemIfPossible(item)
                }

            HStack(alignment: .center, spacing: 8) {
                if let caption {
                    HStack(spacing: 6) {
                        Image(systemName: agentResultKindIcon(item.kind))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(caption)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(minHeight: AgentResultChromeMetrics.chromeCapsuleContentMinHeight, alignment: .center)
                    .frame(maxWidth: AgentResultChromeMetrics.captionMaxWidth, alignment: .leading)
                    .padding(.horizontal, AgentResultChromeMetrics.chromeCapsulePaddingH)
                    .padding(.vertical, AgentResultChromeMetrics.chromeCapsulePaddingV)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer(minLength: 0)

                actionsRow
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
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
                flushTopCornersWhenImage: flushImageTopCorners
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

    private var actionsRow: some View {
        HStack(spacing: 6) {
            if case .file = item.kind {
                IconActionButton(systemName: "magnifyingglass", help: "Reveal in Finder") {
                    if let url = item.localFileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            CopyFeedbackButton(help: "Copy") {
                copyToPasteboard()
            }
        }
        .frame(minHeight: AgentResultChromeMetrics.chromeCapsuleContentMinHeight, alignment: .center)
        .padding(.horizontal, AgentResultChromeMetrics.chromeCapsulePaddingH)
        .padding(.vertical, AgentResultChromeMetrics.chromeCapsulePaddingV)
        .background(.ultraThinMaterial, in: Capsule())
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

/// Native `AttributedString` markdown — lighter than MarkdownUI for Agent Results list scrolling.
private struct AgentResultsMarkdownText: View {
    let markdown: String
    var fontSize: CGFloat = 14
    var codeFontSize: CGFloat = 12

    var body: some View {
        Text(Self.buildAttributed(markdown: markdown, fontSize: fontSize, codeFontSize: codeFontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private static func buildAttributed(
        markdown: String,
        fontSize: CGFloat,
        codeFontSize: CGFloat
    ) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible

        guard var base = try? AttributedString(markdown: markdown, options: options) else {
            var plain = AttributedString(markdown)
            var fallback = AttributeContainer()
            fallback.font = .system(size: fontSize)
            plain.mergeAttributes(fallback, mergePolicy: .keepNew)
            return plain
        }

        let runsSnapshot = Array(base.runs)
        for run in runsSnapshot {
            var attrs = AttributeContainer()
            let inlineCode = run.inlinePresentationIntent?.contains(.code) == true
            let blockCode = codeBlockDepth(run.presentationIntent) != nil
            if blockCode || inlineCode {
                attrs.font = .system(size: codeFontSize, design: .monospaced)
            } else if let level = headerLevel(run.presentationIntent) {
                let scale: CGFloat =
                    switch level {
                    case 1: 1.28
                    case 2: 1.18
                    default: 1.1
                    }
                attrs.font = .system(size: fontSize * scale, weight: .semibold)
            } else {
                attrs.font = .system(size: fontSize)
            }
            base[run.range].mergeAttributes(attrs, mergePolicy: .keepNew)
        }

        return base
    }

    private static func headerLevel(_ intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .header(let level) = component.kind {
                return level
            }
        }
        return nil
    }

    private static func codeBlockDepth(_ intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .codeBlock = component.kind {
                return 1
            }
        }
        return nil
    }
}

private struct LinkBody: View {
    let url: URL
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if title == nil {
                Text(url.absoluteString)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FileBody: View {
    let url: URL
    var maxImageHeight: CGFloat = 260
    var compact: Bool = false
    /// When showing a full-width image preview (not compact), square off top corners so the bitmap meets the panel top edge.
    var flushTopCornersWhenImage: Bool = false
    @State private var icon: NSImage?
    @State private var previewImage: NSImage?
    @State private var thumbnailLoadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let previewImage {
                Group {
                    if compact {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: maxImageHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else if flushTopCornersWhenImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: maxImageHeight)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 8,
                                    bottomTrailingRadius: 8,
                                    topTrailingRadius: 0,
                                    style: .continuous
                                )
                            )
                    } else {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: maxImageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    RoundedRectangle(cornerRadius: flushTopCornersWhenImage ? 0 : 8, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .clipShape(
                    flushTopCornersWhenImage
                        ? AnyShape(UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 0,
                            style: .continuous
                        ))
                        : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(copied ? .green : .secondary)
        .help(copied ? "Copied" : help)
    }
}
