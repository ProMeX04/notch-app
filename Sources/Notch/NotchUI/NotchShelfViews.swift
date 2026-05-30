import AppKit
import NotchShelfFeature
import SwiftUI
import UniformTypeIdentifiers

private extension NotchShelfItemSize {
    var itemsPerRow: CGFloat {
        switch self {
        case .small: return 6
        case .medium: return 5
        case .large: return 4
        }
    }

    var previewSize: CGSize {
        switch self {
        case .small: return CGSize(width: 34, height: 34)
        case .medium: return CGSize(width: 42, height: 42)
        case .large: return CGSize(width: 54, height: 54)
        }
    }

    var minimumCellWidth: CGFloat {
        switch self {
        case .small: return 58
        case .medium: return 72
        case .large: return 86
        }
    }

    func cellHeight(showName: Bool) -> CGFloat {
        guard showName else { return previewSize.height + 12 }
        switch self {
        case .small: return 76
        case .medium: return 84
        case .large: return 96
        }
    }
}

/// Owns the long-lived `NSScrollView`/`NSCollectionView` and their
/// coordinator so that switching panels (or collapsing the notch) does
/// not tear down and rebuild the shelf — the previous behaviour where
/// `NSViewRepresentable.makeNSView` ran every reveal was the dominant
/// source of "khựng" the user reported. The host is created once at
/// `MediaNotchView` level via `@StateObject` and reused forever.
@MainActor
final class ShelfBrowserHost: ObservableObject {
    let scrollView: NSScrollView
    fileprivate let collectionView: ShelfCollectionView
    fileprivate var coordinator: ShelfBrowserView.Coordinator?

    /// The insertion index calculated during the current drag session.
    /// Read synchronously from `handleShelfDrop` before the indicator is cleared.
    var pendingDropIndex: Int? {
        collectionView.dropTargetIndex
    }

    var draggedItemIDs: [UUID] {
        get { collectionView.draggedItemIDs }
        set { collectionView.draggedItemIDs = newValue }
    }

    func updateDropIndicator(at location: CGPoint? = nil) {
        collectionView.updateDropIndicator(at: location)
    }

    func hideDropIndicator() {
        collectionView.hideDropIndicator()
    }

    init() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .automatic

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = ShelfCollectionItem.preferredSize
        layout.minimumInteritemSpacing = ShelfBrowserView.itemSpacing
        layout.minimumLineSpacing = ShelfBrowserView.itemSpacing
        layout.sectionInset = ShelfBrowserView.sectionInsets

        let collectionView = ShelfCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            ShelfCollectionItem.self,
            forItemWithIdentifier: ShelfCollectionItem.identifier
        )
        // Accept native external drags (Finder URLs, plain text). With this
        // registration in place, drops that happen while the shelf is
        // visible are routed through `validateDrop`/`acceptDrop` directly,
        // bypassing the SwiftUI `onDrop` → `@Published` chain that used
        // to add latency.
        collectionView.registerForDraggedTypes([.fileURL, .URL, .string])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = collectionView

        self.scrollView = scrollView
        self.collectionView = collectionView
    }
}

struct ShelfPanelView: View {
    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var presentationModel: NotchPresentationModel
    let host: ShelfBrowserHost

    var body: some View {
        VStack(spacing: 10) {
            if let error = shelf.driveUploadError {
                ShelfDriveStatusRow(
                    icon: "exclamationmark.triangle.fill",
                    text: error,
                    tint: .red
                )
            } else if let message = shelf.driveUploadMessage {
                ShelfDriveStatusRow(
                    icon: shelf.isUploadingToDrive ? "arrow.triangle.2.circlepath" : "checkmark.icloud.fill",
                    text: message,
                    tint: shelf.isUploadingToDrive ? .blue : .green
                )
            }

            if shelf.hasItems {
                ShelfBrowserView(
                    shelf: shelf,
                    preferences: shelf.preferences,
                    presentationModel: presentationModel,
                    host: host
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.white.opacity(shelf.isDropTargeted ? 0.28 : 0.1),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10])
                    )
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

private struct ShelfDriveStatusRow: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ShelfBrowserView: NSViewRepresentable {
    static let itemSpacing: CGFloat = 2
    static let sectionInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

    @ObservedObject var shelf: NotchShelfViewModel
    @ObservedObject var preferences: NotchShelfPreferences
    @ObservedObject var presentationModel: NotchPresentationModel
    let host: ShelfBrowserHost

    func makeCoordinator() -> Coordinator {
        if let existing = host.coordinator {
            existing.shelf = shelf
            return existing
        }
        let coord = Coordinator(
            shelf: shelf,
            presentationModel: presentationModel
        )
        coord.collectionView = host.collectionView
        host.collectionView.delegate = coord
        host.collectionView.dataSource = coord
        host.collectionView.shelfCoordinator = coord
        host.coordinator = coord
        return coord
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coord = context.coordinator
        if host.collectionView.delegate !== coord {
            host.collectionView.delegate = coord
        }
        if host.collectionView.dataSource !== coord {
            host.collectionView.dataSource = coord
        }
        if host.collectionView.shelfCoordinator !== coord {
            host.collectionView.shelfCoordinator = coord
        }
        coord.collectionView = host.collectionView
        coord.reloadData()
        coord.syncSelectionToCollectionView()
        return host.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.shelf = shelf
        context.coordinator.updateLayout()
        context.coordinator.reloadData()
        context.coordinator.syncSelectionToCollectionView()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        // Don't tear down NSScrollView — the host owns it and reuses it
        // across every panel switch / collapse-expand cycle. Just release
        // any transient state that should not survive a hide.
        coordinator.cleanupWhenShelfDisappears()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        struct ItemState: Equatable {
            let id: UUID
            let displayName: String
            let driveFileID: String?
            let driveIsPublic: Bool
            let driveUploadedAt: Date?
            let driveState: NotchShelfItem.ItemDriveState
            let isGoogleDriveConnected: Bool
            let uploadProgress: Double?
            let inProgress: Bool
            let hasError: Bool
            let itemSize: NotchShelfItemSize
            let showItemNames: Bool
            let showDriveBadges: Bool
            let accentColorID: String
        }
        var shelf: NotchShelfViewModel
        let presentationModel: NotchPresentationModel
        weak var collectionView: ShelfCollectionView?
        private var isSyncingSelection = false
        private var lastSnapshot: [ItemState] = []

        init(shelf: NotchShelfViewModel, presentationModel: NotchPresentationModel) {
            self.shelf = shelf
            self.presentationModel = presentationModel
            super.init()
        }

        func updateLayout() {
            guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            let expected = NSSize(width: 72, height: shelf.preferences.itemSize.cellHeight(showName: shelf.preferences.showItemNames))
            if layout.itemSize.height != expected.height {
                layout.itemSize = expected
                layout.invalidateLayout()
            }
        }

        private func makeItemState(for item: NotchShelfItem, isConnected: Bool) -> ItemState {
            ItemState(
                id: item.id,
                displayName: item.displayName,
                driveFileID: item.driveFileID,
                driveIsPublic: item.driveIsPublic,
                driveUploadedAt: item.driveUploadedAt,
                driveState: shelf.cachedDriveStates[item.id] ?? .local,
                isGoogleDriveConnected: isConnected,
                uploadProgress: shelf.uploadProgresses[item.id],
                inProgress: shelf.itemsInProgress.contains(item.id) || shelf.uploadingItemIDs.contains(item.id),
                hasError: shelf.itemErrors[item.id] != nil,
                itemSize: shelf.preferences.itemSize,
                showItemNames: shelf.preferences.showItemNames,
                showDriveBadges: shelf.preferences.showDriveBadges,
                accentColorID: presentationModel.accentColorID
            )
        }

        func reloadData() {
            shelf.refreshDriveStates(force: false)
            let isConnected = shelf.isGoogleDriveConnected
            let snapshot = shelf.items.map { makeItemState(for: $0, isConnected: isConnected) }
            guard snapshot != lastSnapshot else { return }

            let oldSnapshot = lastSnapshot
            lastSnapshot = snapshot

            guard let collectionView else { return }

            // Initial load (or after a full reset) — skip diffing to avoid
            // animating items in from nowhere on first appearance.
            guard !oldSnapshot.isEmpty else {
                collectionView.reloadData()
                return
            }

            let oldIDs = oldSnapshot.map(\.id)
            let newIDs = snapshot.map(\.id)

            if oldIDs == newIDs {
                var reloads: [IndexPath] = []
                for i in 0..<snapshot.count {
                    if oldSnapshot[i] != snapshot[i] {
                        reloads.append(IndexPath(item: i, section: 0))
                    }
                }
                if !reloads.isEmpty {
                    collectionView.reloadItems(at: Set(reloads))
                }
                return
            }

            let difference = newIDs.difference(from: oldIDs).inferringMoves()

            var deletions: Set<IndexPath> = []
            var insertions: Set<IndexPath> = []
            var moves: [(from: IndexPath, to: IndexPath)] = []

            for change in difference {
                switch change {
                case let .remove(offset, _, associatedWith):
                    if associatedWith == nil {
                        deletions.insert(IndexPath(item: offset, section: 0))
                    }
                case let .insert(offset, _, associatedWith):
                    if let assoc = associatedWith {
                        moves.append((
                            from: IndexPath(item: assoc, section: 0),
                            to: IndexPath(item: offset, section: 0)
                        ))
                    } else {
                        insertions.insert(IndexPath(item: offset, section: 0))
                    }
                }
            }

            var reloads: Set<IndexPath> = []
            for (newIdx, newItem) in snapshot.enumerated() {
                if let oldIdx = oldSnapshot.firstIndex(where: { $0.id == newItem.id }) {
                    if oldSnapshot[oldIdx] != newItem {
                        reloads.insert(IndexPath(item: newIdx, section: 0))
                    }
                }
            }

            // Run inserts/deletes/moves inside an explicit animation context
            // with a tight duration. The previous `animator().performBatchUpdates`
            // path used the default 0.25s linear curve which competed with the
            // SwiftUI spring driving the surrounding notch chrome; the user
            // saw that as "giật giật" while items reflowed. A short, tweened
            // pass plays much more smoothly alongside the panel transition.
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                collectionView.animator().performBatchUpdates({
                    if !deletions.isEmpty {
                        collectionView.deleteItems(at: deletions)
                    }
                    if !insertions.isEmpty {
                        collectionView.insertItems(at: insertions)
                    }
                    for move in moves {
                        collectionView.moveItem(at: move.from, to: move.to)
                    }
                }, completionHandler: { [weak self] _ in
                    guard let self, let collectionView = self.collectionView else { return }
                    if !reloads.isEmpty {
                        collectionView.reloadItems(at: reloads)
                    }
                })
            }, completionHandler: nil)
        }

        func syncSelectionToCollectionView() {
            guard let collectionView, !isSyncingSelection else { return }

            isSyncingSelection = true
            defer { isSyncingSelection = false }

            let indexPaths = Set(
                shelf.items.enumerated().compactMap { index, item in
                    shelf.selectedItemIDs.contains(item.id) ? IndexPath(item: index, section: 0) : nil
                }
            )

            let currentSelection = collectionView.selectionIndexPaths
            if currentSelection.subtracting(indexPaths).isEmpty,
               indexPaths.subtracting(currentSelection).isEmpty {
                return
            }

            collectionView.deselectAll(nil)
            if !indexPaths.isEmpty {
                collectionView.selectItems(at: indexPaths, scrollPosition: [])
            }
        }

        func menu(for collectionView: ShelfCollectionView, event: NSEvent) -> NSMenu? {
            let point = collectionView.convert(event.locationInWindow, from: nil)
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  shelf.items.indices.contains(indexPath.item) else {
                return nil
            }

            let clickedItem = shelf.items[indexPath.item]
            if !shelf.isSelected(clickedItem) {
                collectionView.deselectAll(nil)
                collectionView.selectItems(at: [indexPath], scrollPosition: [])
                syncSelectionFromCollectionView()
            }

            let selection = shelf.selectedItems
            guard !selection.isEmpty else { return nil }

            let menu = NSMenu()
            let allOpenable = selection.allSatisfy {
                switch $0.kind {
                case .file, .link:
                    return true
                case .text:
                    return false
                }
            }

            if selection.count == 1 {
                let item = selection[0]
                let openTitle: String
                switch item.kind {
                case .file:
                    openTitle = "Open"
                case .link:
                    openTitle = "Open Link"
                case .text:
                    openTitle = "Copy Text"
                }
                menu.addItem(
                    withTitle: openTitle,
                    action: #selector(openSelection),
                    keyEquivalent: ""
                )

                if case .file = item.kind {
                    menu.addItem(
                        withTitle: "Show in Finder",
                        action: #selector(revealSelection),
                        keyEquivalent: ""
                    )
                }

                menu.addItem(
                    withTitle: "Copy",
                    action: #selector(copySelection),
                    keyEquivalent: ""
                )
            } else {
                if allOpenable {
                    menu.addItem(
                        withTitle: "Open Selected",
                        action: #selector(openSelection),
                        keyEquivalent: ""
                    )
                }

                menu.addItem(
                    withTitle: "Copy Selected",
                    action: #selector(copySelection),
                    keyEquivalent: ""
                )
            }

            if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
                menu.addItem(.separator())
            }

            if selection.count == 1 {
                let item = selection[0]
                if shelf.isGoogleDriveConnected {
                    switch shelf.cachedDriveStates[item.id] ?? .local {
                    case .local:
                        menu.addItem(
                            withTitle: "Upload to Google Drive",
                            action: #selector(uploadToGoogleDrive),
                            keyEquivalent: ""
                        )
                    case .synced:
                        menu.addItem(
                            withTitle: "Copy Link",
                            action: #selector(copyDriveLinkOnly),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Chia sẻ công khai",
                            action: #selector(copyPublicShareLink),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Open in Google Drive",
                            action: #selector(openInGoogleDrive),
                            keyEquivalent: ""
                        )
                    case .syncedPublic:
                        menu.addItem(
                            withTitle: "Copy Link",
                            action: #selector(copyDriveLinkOnly),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Thu hồi chia sẻ công khai",
                            action: #selector(copyDriveShareLink),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Open in Google Drive",
                            action: #selector(openInGoogleDrive),
                            keyEquivalent: ""
                        )
                    case .modified:
                        menu.addItem(
                            withTitle: "Đồng bộ thay đổi lên Drive",
                            action: #selector(uploadToGoogleDrive),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Copy Link",
                            action: #selector(copyDriveLinkOnly),
                            keyEquivalent: ""
                        )
                        if item.driveIsPublic {
                            menu.addItem(
                                withTitle: "Thu hồi chia sẻ công khai",
                                action: #selector(copyDriveShareLink),
                                keyEquivalent: ""
                            )
                        } else {
                            menu.addItem(
                                withTitle: "Chia sẻ công khai",
                                action: #selector(copyPublicShareLink),
                                keyEquivalent: ""
                            )
                        }
                        menu.addItem(
                            withTitle: "Open in Google Drive",
                            action: #selector(openInGoogleDrive),
                            keyEquivalent: ""
                        )
                    case .orphaned:
                        menu.addItem(
                            withTitle: "Copy Link",
                            action: #selector(copyDriveLinkOnly),
                            keyEquivalent: ""
                        )
                        menu.addItem(
                            withTitle: "Open in Google Drive",
                            action: #selector(openInGoogleDrive),
                            keyEquivalent: ""
                        )
                    }
                } else {
                    menu.addItem(
                        withTitle: "Link Google Drive",
                        action: #selector(linkGoogleDrive),
                        keyEquivalent: ""
                    )
                }
            } else {
                if shelf.isGoogleDriveConnected {
                    menu.addItem(
                        withTitle: "Upload to Google Drive",
                        action: #selector(uploadToGoogleDrive),
                        keyEquivalent: ""
                    )
                } else {
                    menu.addItem(
                        withTitle: "Link Google Drive",
                        action: #selector(linkGoogleDrive),
                        keyEquivalent: ""
                    )
                }
            }

            if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
                menu.addItem(.separator())
            }

            menu.addItem(
                withTitle: selection.count == 1 ? "Remove from Shelf" : "Remove Selected",
                action: #selector(removeSelection),
                keyEquivalent: ""
            )

            menu.items.forEach { $0.target = self }
            return menu
        }

        func handleDoubleClick(on item: NotchShelfItem) {
            guard shelf.items.contains(where: { $0.id == item.id }) else { return }
            switch item.kind {
            case .file, .text:
                shelf.activate(item)
            case let .link(url):
                if shelf.preferences.linkDoubleClickAction == .copyURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } else {
                    shelf.activate(item)
                }
            }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            shelf.items.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            guard let item = collectionView.makeItem(
                withIdentifier: ShelfCollectionItem.identifier,
                for: indexPath
            ) as? ShelfCollectionItem else {
                return NSCollectionViewItem()
            }

            let shelfItem = shelf.items[indexPath.item]
            let driveState = shelf.cachedDriveStates[shelfItem.id] ?? .local
            let progress = shelf.uploadProgresses[shelfItem.id]
            let inProgress = shelf.itemsInProgress.contains(shelfItem.id) || shelf.uploadingItemIDs.contains(shelfItem.id)
            let error = shelf.itemErrors[shelfItem.id]
            item.configure(
                with: shelfItem,
                driveState: driveState,
                isGoogleDriveConnected: shelf.isGoogleDriveConnected,
                uploadProgress: progress,
                inProgress: inProgress,
                error: error,
                itemSize: shelf.preferences.itemSize,
                showItemNames: shelf.preferences.showItemNames,
                showDriveBadges: shelf.preferences.showDriveBadges
            )
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            let contentWidth = max(
                0,
                collectionView.bounds.width
                    - ShelfBrowserView.sectionInsets.left
                    - ShelfBrowserView.sectionInsets.right
            )
            let itemsPerRow = shelf.preferences.itemSize.itemsPerRow
            let totalSpacing = ShelfBrowserView.itemSpacing * (itemsPerRow - 1)
            let itemWidth = floor((contentWidth - totalSpacing) / itemsPerRow)

            return NSSize(
                width: max(shelf.preferences.itemSize.minimumCellWidth, itemWidth),
                height: shelf.preferences.itemSize.cellHeight(showName: shelf.preferences.showItemNames)
            )
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            syncSelectionFromCollectionView()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            syncSelectionFromCollectionView()
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard shelf.items.indices.contains(indexPath.item) else { return nil }
            return shelf.items[indexPath.item].pasteboardWriter
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItemsAt indexPaths: Set<IndexPath>
        ) {
            let ids = indexPaths.compactMap { indexPath -> UUID? in
                guard shelf.items.indices.contains(indexPath.item) else { return nil }
                return shelf.items[indexPath.item].id
            }
            if let shelfCollectionView = collectionView as? ShelfCollectionView {
                shelfCollectionView.draggedItemIDs = ids
            }
            print("--- CollectionView draggingSession began for items: \(ids) ---")
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            dragOperation operation: NSDragOperation
        ) {
            if let shelfCollectionView = collectionView as? ShelfCollectionView {
                shelfCollectionView.draggedItemIDs = []
                shelfCollectionView.hideDropIndicator()
            }
            print("--- CollectionView draggingSession ended ---")
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let shelfCollectionView = collectionView as? ShelfCollectionView
            let isInternal = shelfCollectionView.map { !$0.draggedItemIDs.isEmpty } ?? false

            if isInternal {
                shelfCollectionView?.updateDropIndicator()
                proposedDropOperation.pointee = .before
                return .move
            }

            let acceptable = hasAcceptableExternalContent(in: draggingInfo.draggingPasteboard)
            if acceptable {
                shelfCollectionView?.updateDropIndicator()
                proposedDropOperation.pointee = .before
                return .copy
            }

            shelfCollectionView?.hideDropIndicator()
            return []
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath destinationIndexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            let shelfCollectionView = collectionView as? ShelfCollectionView
            let isInternal = shelfCollectionView.map { !$0.draggedItemIDs.isEmpty } ?? false

            // Make sure the shelf panel is the active one so the user
            // sees the items they just dropped.
            presentationModel.selectPanel(.shelf, reveal: true)
            presentationModel.cancelScheduledCollapse()

            if isInternal, let shelfCollectionView {
                let internalIDs = shelfCollectionView.draggedItemIDs
                shelf.moveItems(with: internalIDs, to: destinationIndexPath.item)
                shelfCollectionView.draggedItemIDs = []
                shelfCollectionView.hideDropIndicator()
                return true
            }

            let providers = externalItemProviders(from: draggingInfo)
            guard !providers.isEmpty else {
                shelfCollectionView?.hideDropIndicator()
                return false
            }

            let accepted = shelf.handleDrop(providers: providers, atIndex: destinationIndexPath.item)
            shelfCollectionView?.hideDropIndicator()
            return accepted
        }

        private func hasAcceptableExternalContent(in pasteboard: NSPasteboard) -> Bool {
            guard let types = pasteboard.types else { return false }
            let hasURL = types.contains(.fileURL) || types.contains(.URL)
            let hasString = types.contains(.string)
            let hasLegacy = types.contains(where: {
                $0.rawValue == "public.file-url"
                || $0.rawValue == "public.url"
                || $0.rawValue == "public.utf8-plain-text"
                || $0.rawValue == "NSFilenamesPboardType"
            })
            return hasURL || hasString || hasLegacy
        }

        private func externalItemProviders(from info: NSDraggingInfo) -> [NSItemProvider] {
            let pasteboard = info.draggingPasteboard

            if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: nil
            ) as? [URL], !urls.isEmpty {
                return urls.map { url -> NSItemProvider in
                    if url.isFileURL {
                        // File URLs need an explicit file-URL representation
                        // so the shelf drop service picks the file branch
                        // (rather than a generic URL link item).
                        let provider = NSItemProvider()
                        provider.registerObject(url as NSURL, visibility: .ownProcess)
                        return provider
                    }
                    return NSItemProvider(object: url as NSURL)
                }
            }

            if let strings = pasteboard.readObjects(
                forClasses: [NSString.self],
                options: nil
            ) as? [String], !strings.isEmpty {
                return strings.map { NSItemProvider(object: $0 as NSString) }
            }

            return []
        }

        private func syncSelectionFromCollectionView() {
            guard let collectionView, !isSyncingSelection else { return }

            isSyncingSelection = true
            defer { isSyncingSelection = false }

            let ids = Set(
                collectionView.selectionIndexPaths.compactMap { indexPath in
                    shelf.items.indices.contains(indexPath.item) ? shelf.items[indexPath.item].id : nil
                }
            )
            shelf.select(ids: ids)
        }

        @objc private func openSelection() {
            shelf.activateSelectedItems()
        }

        @objc private func revealSelection() {
            guard let item = shelf.primarySelectedItem else { return }
            shelf.revealInFinder(item)
        }

        @objc private func copySelection() {
            shelf.copySelectedItemsToPasteboard()
        }

        func copySelectionFromShortcut() {
            guard !shelf.selectedItems.isEmpty else { return }
            copySelection()
        }

        func removeSelectionFromShortcut() {
            guard !shelf.selectedItems.isEmpty else { return }
            removeSelection()
        }

        @objc private func removeSelection() {
            // `removeSelectedItems` mutates `items` which triggers
            // `updateNSView` → diff-based reload. Skip the redundant
            // synchronous reload that used to cancel removal animations.
            shelf.removeSelectedItems()
        }

        @objc private func linkGoogleDrive() {
            shelf.connectGoogleDrive()
        }

        @objc private func copyDriveLinkOnly() {
            guard let item = shelf.primarySelectedItem else { return }
            shelf.copyDriveLink(item)
        }

        @objc private func copyDriveShareLink() {
            guard let item = shelf.primarySelectedItem else { return }
            shelf.shareItemPrivately(item)
        }

        @objc private func copyPublicShareLink() {
            guard let item = shelf.primarySelectedItem else { return }
            shelf.shareItemPublicly(item)
        }

        @objc private func openInGoogleDrive() {
            guard let item = shelf.primarySelectedItem,
                  let fileID = item.driveFileID else { return }
            let urlString = "https://drive.google.com/file/d/\(fileID)/view?usp=drivesdk"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }


        @objc private func uploadToGoogleDrive() {
            shelf.uploadSelectedItemsToDrive()
        }

        func cleanupWhenShelfDisappears() {
            lastSnapshot = []
            // Intentionally keep WorkspaceIconCache + thumbnail cache warm.
            // Flushing them every time the shelf hides used to force a full
            // QLThumbnailGenerator pass on the next reveal, which produced a
            // visible "khựng" while items repopulated their previews. The
            // caches enforce their own LRU caps, so leaving them resident
            // keeps memory bounded without paying that cost.
        }
    }
}

final class ShelfCollectionView: NSCollectionView {
    weak var shelfCoordinator: ShelfBrowserView.Coordinator?

    // The items currently being dragged internally.
    var draggedItemIDs: [UUID] = []

    // MARK: - Drop indicator

    /// A thin blue line drawn between items to show where a drop will land.
    private lazy var dropIndicatorLine: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        v.layer?.cornerRadius = 1
        v.layer?.zPosition = 1000
        v.isHidden = true
        addSubview(v)
        return v
    }()

    /// The insertion index computed from the current drag position.
    /// `NotchHostingView.performDragOperation` reads this synchronously
    /// before SwiftUI's `.onDrop` handler fires.
    var dropTargetIndex: Int?

    /// Called by `ShelfContentDropDelegate` on every drag updated tick.
    func updateDropIndicator(at location: CGPoint? = nil) {
        guard let window = self.window else {
            hideDropIndicator()
            return
        }
        let windowPoint: CGPoint
        if let location {
            let windowHeight = window.contentView?.bounds.height ?? 210
            windowPoint = CGPoint(x: location.x, y: windowHeight - location.y)
        } else {
            windowPoint = window.mouseLocationOutsideOfEventStream
        }
        let localPoint = convert(windowPoint, from: nil)
        let itemCount = numberOfItems(inSection: 0)

        // Reject internal drags — no indicator for reorders.
        let pb = NSPasteboard(name: .drag)
        let isInternal = pb.types?.contains(where: {
            $0.rawValue == NotchShelfItem.internalDragIdentityTypeIdentifier
        }) ?? false
        if isInternal {
            hideDropIndicator()
            return
        }

        let accentColorID = UserDefaults.standard.string(forKey: NotchAccentColorOption.storageKey) ?? ""
        let nsAccentColor = NotchAccentColorOption.resolve(rawValue: accentColorID).nsColor
        dropIndicatorLine.layer?.backgroundColor = nsAccentColor.cgColor

        guard itemCount > 0 else {
            dropTargetIndex = 0
            dropIndicatorLine.isHidden = true
            return
        }

        // Gather item frames from the layout.
        struct ItemFrame { let index: Int; let frame: NSRect }
        var items: [ItemFrame] = []
        for i in 0..<itemCount {
            if let attrs = layoutAttributesForItem(at: IndexPath(item: i, section: 0)) {
                items.append(ItemFrame(index: i, frame: attrs.frame))
            }
        }
        guard !items.isEmpty else {
            dropTargetIndex = 0
            dropIndicatorLine.isHidden = true
            return
        }

        // Group into rows (items whose minY are within 4 pt).
        var rows: [[ItemFrame]] = []
        var currentRow: [ItemFrame] = []
        for item in items {
            if let last = currentRow.last, abs(item.frame.minY - last.frame.minY) > 4 {
                rows.append(currentRow)
                currentRow = [item]
            } else {
                currentRow.append(item)
            }
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        // Pick the row closest to the cursor's y.
        let targetRow = rows.min(by: {
            abs($0[0].frame.midY - localPoint.y) < abs($1[0].frame.midY - localPoint.y)
        }) ?? rows[0]

        // Within the row, find the insertion gap.
        var insertIndex = targetRow.last!.index + 1
        var indicatorX = targetRow.last!.frame.maxX + 1

        for item in targetRow {
            if localPoint.x < item.frame.midX {
                insertIndex = item.index
                indicatorX = item.frame.minX - 2
                break
            }
        }

        dropTargetIndex = insertIndex
        print("--- ShelfCollectionView.updateDropIndicator: windowPoint=\(windowPoint), localPoint=\(localPoint), targetIndex=\(insertIndex) ---")

        // Position and show.
        let refFrame = targetRow[0].frame
        dropIndicatorLine.frame = NSRect(
            x: indicatorX,
            y: refFrame.minY,
            width: 2,
            height: refFrame.height
        )
        dropIndicatorLine.isHidden = false
    }

    func hideDropIndicator() {
        dropIndicatorLine.isHidden = true
        dropTargetIndex = nil
    }

    // MARK: - First-responder / interaction overrides

    override var acceptsFirstResponder: Bool { true }

    // The notch lives in a `.nonactivatingPanel`, so the window is often
    // not key when the user reaches for an item. Without this override the
    // first mouseDown is swallowed as "click-to-focus", and the user has
    // to press a second time before a drag-out is recognised — exactly
    // the "ấn kéo không nhạy" symptom. Returning `true` lets the very
    // first click begin AppKit's drag tracking immediately.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        shelfCoordinator?.menu(for: self, event: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        let clickedItem = clickedIndexPath.flatMap {
            item(at: $0) as? ShelfCollectionItem
        }
        let activatedShelfItem = clickedIndexPath.flatMap { indexPath -> NotchShelfItem? in
            guard let shelf = shelfCoordinator?.shelf,
                  shelf.items.indices.contains(indexPath.item) else {
                return nil
            }
            return shelf.items[indexPath.item]
        }

        if clickedIndexPath == nil,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift) {
            deselectAll(nil)
            shelfCoordinator?.collectionView(self, didDeselectItemsAt: [])
            return
        }

        clickedItem?.setPressed(true)
        super.mouseDown(with: event)
        clickedItem?.setPressed(false)

        if event.clickCount == 2, let activatedShelfItem {
            clickedItem?.playActivationPulse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak coordinator = shelfCoordinator] in
                coordinator?.handleDoubleClick(on: activatedShelfItem)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            shelfCoordinator?.copySelectionFromShortcut()
            return true
        }

        if modifiers == .command,
           event.keyCode == 51 {
            shelfCoordinator?.removeSelectionFromShortcut()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private struct ShelfThumbnailCache {
    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()
}

@MainActor
private struct ShelfMetadataCache {
    static let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 200
        return c
    }()
}

private final class ShelfCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfCollectionItem")
    static let preferredSize = NSSize(width: 72, height: 84)

    private var thumbnailTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var currentItemID: UUID?

    private var shelfView: ShelfCollectionItemView {
        view as! ShelfCollectionItemView
    }

    override func loadView() {
        view = ShelfCollectionItemView()
    }

    override var isSelected: Bool {
        didSet {
            shelfView.applySelection(isSelected)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        thumbnailTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        currentItemID = nil
        shelfView.setPressed(false, animated: false)
        shelfView.reset()
    }

    func setPressed(_ pressed: Bool) {
        shelfView.setPressed(pressed)
    }

    func playActivationPulse() {
        shelfView.playActivationPulse()
    }

    func configure(
        with item: NotchShelfItem,
        driveState: NotchShelfItem.ItemDriveState,
        isGoogleDriveConnected: Bool,
        uploadProgress: Double?,
        inProgress: Bool,
        error: String?,
        itemSize: NotchShelfItemSize,
        showItemNames: Bool,
        showDriveBadges: Bool
    ) {
        currentItemID = item.id
        thumbnailTask?.cancel()
        thumbnailTask = nil
        metadataTask?.cancel()
        metadataTask = nil

        shelfView.configureAppearance(itemSize: itemSize, showItemName: showItemNames)
        shelfView.setTitle(showItemNames ? item.displayName : "")
        shelfView.applySelection(isSelected)

        shelfView.setUploadProgress(nil)
        shelfView.setDriveBadge(symbolName: nil, tint: nil, accessibilityDescription: nil)
        shelfView.toolTip = nil

        if let progress = uploadProgress {
            shelfView.setUploadProgress(progress)
        } else if inProgress {
            shelfView.setDriveBadge(
                symbolName: "arrow.triangle.2.circlepath",
                tint: .systemBlue,
                accessibilityDescription: "Processing...",
                isAnimating: true
            )
        } else if let errorMsg = error {
            shelfView.setDriveBadge(
                symbolName: "xmark.icloud.fill",
                tint: .systemRed,
                accessibilityDescription: errorMsg
            )
            shelfView.toolTip = errorMsg
        } else {
            if isGoogleDriveConnected && showDriveBadges {
                switch driveState {
                case .local:
                    shelfView.setDriveBadge(symbolName: nil, tint: nil, accessibilityDescription: nil)
                case .synced:
                    shelfView.setDriveBadge(
                        symbolName: "checkmark.icloud.fill",
                        tint: .systemGreen,
                        accessibilityDescription: "Synced"
                    )
                case .syncedPublic:
                    shelfView.setDriveBadge(
                        symbolName: "link.icloud.fill",
                        tint: .systemBlue,
                        accessibilityDescription: "Synced Public"
                    )
                case .modified:
                    shelfView.setDriveBadge(
                        symbolName: "arrow.clockwise.icloud.fill",
                        tint: .systemOrange,
                        accessibilityDescription: "Modified"
                    )
                case .orphaned:
                    shelfView.setDriveBadge(
                        symbolName: "exclamationmark.icloud.fill",
                        tint: .systemYellow,
                        accessibilityDescription: "Local file missing; Drive copy may still exist"
                    )
                }
            }
        }

        // 1. Handle Metadata Info Cache Lookup
        let metadataKey = item.id.uuidString as NSString
        if let cachedInfo = ShelfMetadataCache.cache.object(forKey: metadataKey) {
            shelfView.infoField.stringValue = cachedInfo as String
            shelfView.infoField.isHidden = !showItemNames || cachedInfo.length == 0
        } else {
            shelfView.infoField.stringValue = ""
            shelfView.infoField.isHidden = true
            
            if case let .file(reference) = item.kind {
                let itemID = item.id
                metadataTask = Task { [weak self] in
                    let info = await NotchShelfMetadataService.shared.metadata(for: reference.url)
                    if let info {
                        ShelfMetadataCache.cache.setObject(info as NSString, forKey: metadataKey)
                    }

                    await MainActor.run {
                        guard let self, self.currentItemID == itemID else { return }
                        self.shelfView.infoField.stringValue = info ?? ""
                        self.shelfView.infoField.isHidden = !showItemNames || (info?.isEmpty ?? true)
                    }
                }
            }
        }

        // 2. Handle Thumbnail Cache Lookup
        if case let .file(reference) = item.kind {
            let itemID = item.id
            let cacheKey = "\(item.id.uuidString)_\(Int(itemSize.previewSize.width))x\(Int(itemSize.previewSize.height))" as NSString
            
            if let cachedThumbnail = ShelfThumbnailCache.cache.object(forKey: cacheKey) {
                shelfView.previewImageView.image = cachedThumbnail
            } else {
                shelfView.previewImageView.image = fallbackIcon(for: item)
                
                thumbnailTask = Task { [weak self] in
                    guard let thumbnail = await NotchShelfThumbnailService.shared.thumbnail(
                        for: reference.url,
                        size: itemSize.previewSize
                    ) else {
                        return
                    }
                    
                    ShelfThumbnailCache.cache.setObject(thumbnail, forKey: cacheKey)

                    await MainActor.run {
                        guard let self, self.currentItemID == itemID else { return }
                        self.shelfView.previewImageView.image = thumbnail
                    }
                }
            }
        } else {
            shelfView.previewImageView.image = fallbackIcon(for: item)
        }
    }

    private func fallbackIcon(for item: NotchShelfItem) -> NSImage {
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
}

private final class CircularProgressView: NSView {
    var progress: Double = 0.0 {
        didSet {
            let clamped = max(0.0, min(1.0, progress))
            if clamped != oldValue {
                needsDisplay = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) - 3.0) / 2.0
        guard radius > 0 else { return }

        // 1. Draw subtle background circle outline
        let bgPath = NSBezierPath()
        bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        bgPath.lineWidth = 2.0
        NSColor.white.withAlphaComponent(0.2).setStroke()
        bgPath.stroke()

        // 2. Draw progress arc (starting from top, 90 degrees, moving clockwise)
        if progress > 0.0 {
            let progressPath = NSBezierPath()
            let startAngle: CGFloat = 90.0
            let endAngle = startAngle - CGFloat(max(0.0, min(1.0, progress)) * 360.0)

            progressPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            progressPath.lineWidth = 2.0
            progressPath.lineCapStyle = .round

            NSColor.systemBlue.setStroke()
            progressPath.stroke()
        }
    }
}

internal final class ShelfCollectionItemView: NSView {
    private static let finderTitleMaxCharacters = 12
    private let iconSelectionBackground = NSView()
    let previewImageView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let infoField = NSTextField(labelWithString: "")
    private let titleSelectionBackground = NSView()
    let cloudStatusImageView = NSImageView()
    private let circularProgressView = CircularProgressView()
    private var previewWidthConstraint: NSLayoutConstraint?
    private var previewHeightConstraint: NSLayoutConstraint?
    private var titleWidthConstraint: NSLayoutConstraint?
    private var fullTitle = ""
    private var isFinderSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // Same reasoning as `ShelfCollectionView.acceptsFirstMouse`: the
    // hosting window is non-activating, so without this override the
    // very first click on an item only focuses the panel and the
    // subsequent mouseDragged events never form a drag session. Letting
    // the item view accept first-mouse means a single press-and-drag
    // always initiates the drag-out gesture, like Finder.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        updateDisplayedTitle()
    }

    func configureAppearance(itemSize: NotchShelfItemSize, showItemName: Bool) {
        previewWidthConstraint?.constant = itemSize.previewSize.width
        previewHeightConstraint?.constant = itemSize.previewSize.height
        titleField.isHidden = !showItemName
        infoField.isHidden = !showItemName || infoField.stringValue.isEmpty
        updateSelectionBackgrounds()
    }

    func reset() {
        setPressed(false, animated: false)
        previewImageView.image = nil
        setTitle("")
        infoField.stringValue = ""
        infoField.isHidden = true
        cloudStatusImageView.image = nil
        cloudStatusImageView.isHidden = true
        circularProgressView.progress = 0.0
        circularProgressView.isHidden = true
        applySelection(false)
    }

    func setPressed(_ pressed: Bool, animated: Bool = true) {
        guard let layer else { return }
        let targetScale: CGFloat = pressed ? 0.96 : 1
        let currentScale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat)
            ?? (layer.value(forKeyPath: "transform.scale") as? CGFloat)
            ?? 1

        layer.setValue(targetScale, forKeyPath: "transform.scale")
        layer.opacity = pressed ? 0.98 : 1

        guard animated else {
            layer.removeAnimation(forKey: "shelfPressedScale")
            layer.removeAnimation(forKey: "shelfPressedOpacity")
            return
        }

        let scaleAnimation = CASpringAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = currentScale
        scaleAnimation.toValue = targetScale
        scaleAnimation.mass = 1
        scaleAnimation.stiffness = 320
        scaleAnimation.damping = 26
        scaleAnimation.initialVelocity = 0
        scaleAnimation.duration = min(0.24, scaleAnimation.settlingDuration)
        layer.add(scaleAnimation, forKey: "shelfPressedScale")

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = layer.presentation()?.opacity ?? (pressed ? 1 : 0.98)
        opacityAnimation.toValue = pressed ? 0.98 : 1
        opacityAnimation.duration = pressed ? 0.08 : 0.16
        layer.add(opacityAnimation, forKey: "shelfPressedOpacity")
    }

    func playActivationPulse() {
        setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.setPressed(false)
        }
    }

    func applySelection(_ selected: Bool) {
        isFinderSelected = selected
        previewImageView.alphaValue = selected ? 1.0 : 0.78
        titleField.textColor = selected ? .white : .white.withAlphaComponent(0.68)
        updateSelectionBackgrounds()

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.cornerRadius = 0
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
    }

    func setDriveBadge(symbolName: String?, tint: NSColor?, accessibilityDescription: String?, isAnimating: Bool = false) {
        guard let symbolName, let tint else {
            cloudStatusImageView.image = nil
            cloudStatusImageView.isHidden = true
            cloudStatusImageView.layer?.removeAllAnimations()
            return
        }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfiguration)
        image?.isTemplate = true

        cloudStatusImageView.image = image
        cloudStatusImageView.contentTintColor = tint
        cloudStatusImageView.isHidden = false
        cloudStatusImageView.layer?.zPosition = 20

        cloudStatusImageView.layer?.removeAllAnimations()
        if isAnimating {
            let rotation = CABasicAnimation(keyPath: "transform")
            let toCenter = CATransform3DMakeTranslation(-8, -8, 0)
            let fromCenter = CATransform3DMakeTranslation(8, 8, 0)
            let startTransform = CATransform3DConcat(
                CATransform3DConcat(toCenter, CATransform3DMakeRotation(0.0, 0, 0, 1)),
                fromCenter
            )
            let endTransform = CATransform3DConcat(
                CATransform3DConcat(toCenter, CATransform3DMakeRotation(-Double.pi * 2.0, 0, 0, 1)),
                fromCenter
            )
            rotation.fromValue = startTransform
            rotation.toValue = endTransform
            rotation.duration = 1.2
            rotation.repeatCount = .infinity
            cloudStatusImageView.layer?.add(rotation, forKey: "rotationAnimation")
        }
    }

    func setUploadProgress(_ progress: Double?) {
        if let progress = progress {
            circularProgressView.progress = progress
            circularProgressView.isHidden = false
            cloudStatusImageView.isHidden = true
            circularProgressView.layer?.removeAllAnimations()
        } else {
            circularProgressView.isHidden = true
            circularProgressView.layer?.removeAllAnimations()
        }
    }

    func setTitle(_ title: String) {
        fullTitle = title
        updateDisplayedTitle()
    }



    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.white.withAlphaComponent(0.28).cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -3)

        iconSelectionBackground.wantsLayer = true
        iconSelectionBackground.translatesAutoresizingMaskIntoConstraints = false
        iconSelectionBackground.layer?.cornerRadius = 7
        iconSelectionBackground.layer?.masksToBounds = true
        iconSelectionBackground.isHidden = true
        addSubview(iconSelectionBackground)

        previewImageView.wantsLayer = true
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewImageView)

        cloudStatusImageView.wantsLayer = true
        cloudStatusImageView.translatesAutoresizingMaskIntoConstraints = false
        cloudStatusImageView.imageScaling = .scaleProportionallyUpOrDown
        cloudStatusImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        cloudStatusImageView.isHidden = true
        addSubview(cloudStatusImageView)

        circularProgressView.wantsLayer = true
        circularProgressView.translatesAutoresizingMaskIntoConstraints = false
        circularProgressView.isHidden = true
        addSubview(circularProgressView)

        titleSelectionBackground.wantsLayer = true
        titleSelectionBackground.translatesAutoresizingMaskIntoConstraints = false
        titleSelectionBackground.layer?.cornerRadius = 4
        titleSelectionBackground.layer?.masksToBounds = true
        titleSelectionBackground.isHidden = true
        addSubview(titleSelectionBackground)

        titleField.font = .systemFont(ofSize: 9, weight: .semibold)
        titleField.textColor = .white.withAlphaComponent(0.86)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byClipping
        titleField.cell?.wraps = false
        titleField.cell?.isScrollable = false
        titleField.cell?.usesSingleLineMode = true
        titleField.cell?.lineBreakMode = .byClipping
        titleField.cell?.truncatesLastVisibleLine = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        infoField.font = .systemFont(ofSize: 8, weight: .regular)
        infoField.textColor = NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1.0)
        infoField.alignment = .center
        infoField.maximumNumberOfLines = 1
        infoField.lineBreakMode = .byTruncatingTail
        infoField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoField)

        let previewWidthConstraint = previewImageView.widthAnchor.constraint(equalToConstant: 42)
        let previewHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 42)
        let titleWidthConstraint = titleField.widthAnchor.constraint(equalToConstant: 0)
        let titleMaxWidthConstraint = titleField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4)
        titleMaxWidthConstraint.priority = .defaultLow
        self.previewWidthConstraint = previewWidthConstraint
        self.previewHeightConstraint = previewHeightConstraint
        self.titleWidthConstraint = titleWidthConstraint

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            previewImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewWidthConstraint,
            previewHeightConstraint,

            iconSelectionBackground.leadingAnchor.constraint(equalTo: previewImageView.leadingAnchor, constant: -6),
            iconSelectionBackground.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 6),
            iconSelectionBackground.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: -6),
            iconSelectionBackground.bottomAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 6),

            cloudStatusImageView.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: -4),
            cloudStatusImageView.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 4),
            cloudStatusImageView.widthAnchor.constraint(equalToConstant: 16),
            cloudStatusImageView.heightAnchor.constraint(equalToConstant: 16),

            circularProgressView.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: -4),
            circularProgressView.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 4),
            circularProgressView.widthAnchor.constraint(equalToConstant: 16),
            circularProgressView.heightAnchor.constraint(equalToConstant: 16),

            titleSelectionBackground.leadingAnchor.constraint(equalTo: titleField.leadingAnchor, constant: -3),
            titleSelectionBackground.trailingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 3),
            titleSelectionBackground.topAnchor.constraint(equalTo: titleField.topAnchor, constant: -2),
            titleSelectionBackground.bottomAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),

            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleMaxWidthConstraint,
            titleWidthConstraint,
            titleField.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 6),
            titleField.heightAnchor.constraint(equalToConstant: 14),

            infoField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            infoField.centerXAnchor.constraint(equalTo: centerXAnchor),
            infoField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4),
        ])

        applySelection(false)
    }

    private func updateSelectionBackgrounds() {
        updateDisplayedTitle()
        iconSelectionBackground.isHidden = !isFinderSelected
        iconSelectionBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        titleSelectionBackground.isHidden = !isFinderSelected || titleField.isHidden || titleField.stringValue.isEmpty

        let accentColorID = UserDefaults.standard.string(forKey: NotchAccentColorOption.storageKey) ?? ""
        let nsAccentColor = NotchAccentColorOption.resolve(rawValue: accentColorID).nsColor
        titleSelectionBackground.layer?.backgroundColor = nsAccentColor.cgColor
    }

    private func updateDisplayedTitle() {
        guard !titleField.isHidden, !fullTitle.isEmpty else {
            titleField.stringValue = ""
            titleWidthConstraint?.constant = 0
            return
        }

        let availableWidth = max(0, bounds.width - 10)
        guard availableWidth > 0 else {
            titleField.stringValue = fullTitle
            return
        }

        let font = titleField.font ?? NSFont.systemFont(ofSize: 9)
        let displayTitle = finderStyleMiddleTruncatedTitle(fullTitle, availableWidth: availableWidth, font: font)
        if titleField.stringValue != displayTitle {
            titleField.stringValue = displayTitle
        }

        let measuredWidth = titleWidth(displayTitle, font: font) + 6
        let targetWidth = min(max(12, measuredWidth), availableWidth)
        if abs((titleWidthConstraint?.constant ?? 0) - targetWidth) > 0.5 {
            titleWidthConstraint?.constant = targetWidth
        }
    }

    internal func finderStyleMiddleTruncatedTitle(
        _ title: String,
        availableWidth: CGFloat,
        font: NSFont
    ) -> String {
        let characters = Array(title)
        guard characters.count > Self.finderTitleMaxCharacters else {
            return title
        }

        let token = "..."
        guard titleWidth(token, font: font) <= availableWidth else { return token }

        guard characters.count > token.count else { return title }

        let maxVisibleWithoutToken = max(2, Self.finderTitleMaxCharacters - token.count)
        var suffixCount = min(
            preferredSuffixLength(for: title),
            maxVisibleWithoutToken - 1,
            characters.count - 2
        )
        while suffixCount >= 1 {
            var low = 1
            var high = min(
                maxVisibleWithoutToken - suffixCount,
                max(1, characters.count - suffixCount - 1)
            )
            var best: String?

            while low <= high {
                let prefixCount = (low + high) / 2
                let candidate = String(characters.prefix(prefixCount))
                    + token
                    + String(characters.suffix(suffixCount))

                if titleWidth(candidate, font: font) <= availableWidth {
                    best = candidate
                    low = prefixCount + 1
                } else {
                    high = prefixCount - 1
                }
            }

            if let best {
                return best
            }
            suffixCount -= 1
        }

        return token
    }

    private func preferredSuffixLength(for title: String) -> Int {
        let filename = title as NSString
        let pathExtension = filename.pathExtension
        guard !pathExtension.isEmpty else { return min(4, title.count - 1) }

        // Keep the extension plus at least one stem character, matching Finder's
        // "name...x.ext" style for files.
        return min(pathExtension.count + 2, 10, title.count - 1)
    }

    private func titleWidth(_ title: String, font: NSFont) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }
}
