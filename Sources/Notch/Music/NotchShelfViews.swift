import SwiftUI
struct ShelfPanelView: View {
    @ObservedObject var shelf: NotchShelfViewModel

    var body: some View {
        VStack(spacing: 10) {
            if shelf.hasItems {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(shelf.items) { item in
                            ShelfItemCardView(item: item, shelf: shelf)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(shelf.isDropTargeted ? 0.28 : 0.1), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10]))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(shelf.isDropTargeted ? 0.08 : 0.03))
                    )
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: shelf.isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .systemBlue).ensureMinimumBrightness(factor: 0.72))

                            Text(shelf.isDropTargeted ? "Release to add to shelf" : "Drop here")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
    }
}

struct ShelfItemCardView: View {
    let item: NotchShelfItem
    @ObservedObject var shelf: NotchShelfViewModel
    @State private var thumbnail: NSImage?

    private let tileSize = CGSize(width: 58, height: 58)

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                previewTile

                Button {
                    shelf.remove(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                }
                .buttonStyle(.plain)
                .padding(5)
            }

            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)
        }
        .frame(width: 105)
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            shelf.activate(item)
        }
        .onDrag {
            item.dragItemProvider
        } preview: {
            dragPreview
        }
        .task(id: item.id) {
            await loadThumbnailIfNeeded()
        }
    }

    /// Lightweight drag preview – uses the cached icon (no disk I/O).
    private var dragPreview: some View {
        HStack(spacing: 8) {
            Image(nsImage: cachedFallbackIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text(item.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    /// Returns a cached system icon - avoids `NSWorkspace.shared.icon(forFile:)` on every render.
    private var cachedFallbackIcon: NSImage {
        switch item.kind {
        case let .file(reference):
            return WorkspaceIconCache.shared.icon(for: reference.url.path)
        case .link:
            return NSImage(
                systemSymbolName: "link.circle.fill",
                accessibilityDescription: "Link"
            ) ?? NSImage()
        case .text:
            return NSImage(
                systemSymbolName: "text.alignleft",
                accessibilityDescription: "Text"
            ) ?? NSImage()
        }
    }

    private var previewImage: NSImage {
        thumbnail ?? cachedFallbackIcon
    }

    private var previewTile: some View {
        Image(nsImage: previewImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: tileSize.width, height: tileSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        guard case let .file(reference) = item.kind else {
            thumbnail = cachedFallbackIcon
            return
        }

        // Start with the fast cached system icon
        thumbnail = cachedFallbackIcon

        // Then try for a high-quality thumbnail (will be skipped for folders in service)
        if let highQual = await NotchShelfThumbnailService.shared.thumbnail(for: reference.url, size: tileSize) {
            thumbnail = highQual
        }
    }
}
