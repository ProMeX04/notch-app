import AppKit
import NotchShelfCore
@preconcurrency import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

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
    static let itemsPerRow: CGFloat = 5
    static let itemSpacing: CGFloat = 4
    static let sectionInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

    @ObservedObject var shelf: NotchShelfViewModel
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
        }
        var shelf: NotchShelfViewModel
        let presentationModel: NotchPresentationModel
        weak var collectionView: ShelfCollectionView?
        private var isSyncingSelection = false
        private var lastSnapshot: [ItemState] = []
        private var draggedItemIDs: [UUID] = []
        private var _quickLookController: ShelfQuickLookPanelController?
        private func requireQuickLookController() -> ShelfQuickLookPanelController {
            if let existing = _quickLookController { return existing }
            let newController = ShelfQuickLookPanelController()
            newController.onVisibilityChange = { [weak self] isVisible in
                self?.presentationModel.setAutoCollapseSuppressed(
                    isVisible,
                    reason: .shelfQuickLook
                )
            }
            newController.onClose = { [weak self] in
                self?.restoreShelfFocus()
            }
            _quickLookController = newController
            return newController
        }

        init(shelf: NotchShelfViewModel, presentationModel: NotchPresentationModel) {
            self.shelf = shelf
            self.presentationModel = presentationModel
            super.init()
        }

        func reloadData() {
            shelf.refreshDriveStates(force: false)
            let isConnected = shelf.isGoogleDriveConnected
            let snapshot = shelf.items.map { item in
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
                    hasError: shelf.itemErrors[item.id] != nil
                )
            }
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

            if shelf.canQuickLookSelection {
                menu.addItem(
                    withTitle: selection.count == 1 ? "Quick Look" : "Quick Look Selected",
                    action: #selector(toggleQuickLookFromMenu),
                    keyEquivalent: ""
                )
            }

            if !menu.items.isEmpty {
                menu.addItem(.separator())
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

        func handleDoubleClick(on indexPath: IndexPath?) {
            guard let indexPath,
                  shelf.items.indices.contains(indexPath.item) else {
                return
            }

            shelf.activate(shelf.items[indexPath.item])
        }

        func toggleQuickLook() {
            guard let previewURL = shelf.previewableSelectedFileURLs.first else { return }

            let ql = requireQuickLookController()
            if ql.isVisible {
                ql.close()
                return
            }

            showQuickLook(previewURL)
        }

        func showQuickLook(_ url: URL) {
            requireQuickLookController().show(url: url)
        }

        func refreshQuickLookIfNeeded() {
            guard let ql = _quickLookController, ql.isVisible else { return }
            guard let previewURL = shelf.previewableSelectedFileURLs.first else {
                ql.close(restoreFocus: false)
                return
            }

            ql.update(url: previewURL)
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
                error: error
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
            let totalSpacing = ShelfBrowserView.itemSpacing * (ShelfBrowserView.itemsPerRow - 1)
            let itemWidth = floor((contentWidth - totalSpacing) / ShelfBrowserView.itemsPerRow)

            return NSSize(
                width: max(72, itemWidth),
                height: ShelfCollectionItem.preferredSize.height
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
            let sortedIndexPaths = indexPaths.sorted { lhs, rhs in
                if lhs.section == rhs.section {
                    return lhs.item < rhs.item
                }
                return lhs.section < rhs.section
            }

            draggedItemIDs = sortedIndexPaths.compactMap { indexPath in
                shelf.items.indices.contains(indexPath.item) ? shelf.items[indexPath.item].id : nil
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            dragOperation operation: NSDragOperation
        ) {
            draggedItemIDs.removeAll()
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            // Internal reorder.
            if draggingInfo.draggingSource as AnyObject? === collectionView,
               !draggedItemIDs.isEmpty {
                proposedDropOperation.pointee = .before
                return .move
            }

            // External drop (e.g. from Finder). Routing this through the
            // collection view rather than SwiftUI's `onDrop` keeps the
            // event entirely in AppKit — no `@Published` round-trip — so
            // the system insertion indicator and animations match Finder's.
            if hasAcceptableExternalContent(in: draggingInfo.draggingPasteboard) {
                proposedDropOperation.pointee = .before
                return .copy
            }

            return []
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath destinationIndexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            if draggingInfo.draggingSource as AnyObject? === collectionView {
                guard !draggedItemIDs.isEmpty else { return false }
                let destinationIndex = min(destinationIndexPath.item, shelf.items.count)
                // Mutating `items` triggers SwiftUI's `updateNSView` which
                // calls `reloadData()` → diff-based animation runs there.
                // Avoid double reload (which previously cancelled the move
                // animation).
                shelf.moveItems(with: draggedItemIDs, to: destinationIndex)
                draggedItemIDs.removeAll()
                return true
            }

            let providers = externalItemProviders(from: draggingInfo)
            guard !providers.isEmpty else { return false }

            // Make sure the shelf panel is the active one so the user
            // sees the items they just dropped. This call is cheap when
            // we're already on shelf because of the panel-switch guards.
            presentationModel.selectPanel(.shelf, reveal: true)
            // SwiftUI's `onDrop(isTargeted:)` already fired with `false`
            // by the time AppKit reaches this acceptDrop, which armed an
            // auto-collapse 120 ms out. Drop succeeded — keep the shelf
            // open so the user sees what just landed.
            presentationModel.cancelScheduledCollapse()
            return shelf.handleDrop(providers: providers)
        }

        private func hasAcceptableExternalContent(in pasteboard: NSPasteboard) -> Bool {
            pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
                || pasteboard.canReadObject(forClasses: [NSString.self], options: nil)
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
            refreshQuickLookIfNeeded()
        }

        @objc private func openSelection() {
            shelf.activateSelectedItems()
        }

        @objc private func toggleQuickLookFromMenu() {
            toggleQuickLook()
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
            refreshQuickLookIfNeeded()
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

        private func restoreShelfFocus() {
            guard let collectionView else { return }
            NSApp.activate(ignoringOtherApps: true)
            collectionView.window?.orderFrontRegardless()
            collectionView.window?.makeKey()
            collectionView.window?.makeFirstResponder(collectionView)
        }

        func cleanupWhenShelfDisappears() {
            presentationModel.setAutoCollapseSuppressed(false, reason: .shelfQuickLook)
            _quickLookController?.close(restoreFocus: false)

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

        if clickedIndexPath == nil,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift) {
            deselectAll(nil)
            shelfCoordinator?.collectionView(self, didDeselectItemsAt: [])
            return
        }

        super.mouseDown(with: event)

        if event.clickCount == 2 {
            shelfCoordinator?.handleDoubleClick(on: clickedIndexPath)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 53 {
            shelfCoordinator?.toggleQuickLook()
            return
        }

        super.keyDown(with: event)
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

private final class ShelfCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfCollectionItem")
    static let preferredSize = NSSize(width: 72, height: 82)
    private static let previewSize = CGSize(width: 42, height: 42)

    private var thumbnailTask: Task<Void, Never>?
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
        currentItemID = nil
        shelfView.reset()
    }

    func configure(
        with item: NotchShelfItem,
        driveState: NotchShelfItem.ItemDriveState,
        isGoogleDriveConnected: Bool,
        uploadProgress: Double?,
        inProgress: Bool,
        error: String?
    ) {
        currentItemID = item.id
        thumbnailTask?.cancel()
        thumbnailTask = nil

        shelfView.titleField.stringValue = item.displayName
        shelfView.previewImageView.image = fallbackIcon(for: item)
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
            if isGoogleDriveConnected {
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

        guard case let .file(reference) = item.kind else { return }
        let itemID = item.id
        thumbnailTask = Task { [weak self] in
            guard let thumbnail = await NotchShelfThumbnailService.shared.thumbnail(
                for: reference.url,
                size: Self.previewSize
            ) else {
                return
            }

            await MainActor.run {
                guard let self, self.currentItemID == itemID else { return }
                self.shelfView.previewImageView.image = thumbnail
            }
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

private final class ShelfCollectionItemView: NSView {
    let previewImageView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let cloudStatusImageView = NSImageView()
    let circularProgressView = CircularProgressView()

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

    func reset() {
        previewImageView.image = nil
        titleField.stringValue = ""
        cloudStatusImageView.image = nil
        cloudStatusImageView.isHidden = true
        circularProgressView.progress = 0.0
        circularProgressView.isHidden = true
        applySelection(false)
    }

    func applySelection(_ selected: Bool) {
        previewImageView.alphaValue = selected ? 1.0 : 0.75
        titleField.textColor = selected ? .white : .white.withAlphaComponent(0.65)

        if selected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            layer?.borderWidth = 1.5
            layer?.cornerRadius = 8
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            layer?.cornerRadius = 8
        }

        layer?.shadowOpacity = selected ? 0.25 : 0.1
        layer?.shadowRadius = selected ? 8 : 3
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



    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.white.withAlphaComponent(0.28).cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -3)

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

        titleField.font = .systemFont(ofSize: 9, weight: .semibold)
        titleField.textColor = .white.withAlphaComponent(0.86)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.cell?.wraps = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            previewImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 42),
            previewImageView.heightAnchor.constraint(equalToConstant: 42),

            cloudStatusImageView.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: -4),
            cloudStatusImageView.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 4),
            cloudStatusImageView.widthAnchor.constraint(equalToConstant: 16),
            cloudStatusImageView.heightAnchor.constraint(equalToConstant: 16),

            circularProgressView.topAnchor.constraint(equalTo: previewImageView.topAnchor, constant: -4),
            circularProgressView.trailingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 4),
            circularProgressView.widthAnchor.constraint(equalToConstant: 16),
            circularProgressView.heightAnchor.constraint(equalToConstant: 16),

            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleField.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 6),
            titleField.heightAnchor.constraint(equalToConstant: 28),
        ])

        applySelection(false)
    }
}

private final class ShelfQuickLookPanel: NSPanel {
    var closeHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 53 {
            closeHandler?()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
private final class ShelfQuickLookPanelController: NSObject, NSWindowDelegate {
    private let panel: ShelfQuickLookPanel
    private let previewView: QLPreviewView
    var onClose: (() -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?
    private var shouldRestoreFocusOnClose = true

    var isVisible: Bool {
        panel.isVisible
    }

    override init() {
        panel = ShelfQuickLookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.center()

        previewView = QLPreviewView(frame: panel.contentView?.bounds ?? .zero, style: .normal)
        previewView.autoresizingMask = [.width, .height]
        previewView.shouldCloseWithWindow = true
        previewView.autostarts = true

        super.init()
        panel.delegate = self

        let containerView = NSView(frame: panel.contentView?.bounds ?? .zero)
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(previewView)
        panel.contentView = containerView

        panel.closeHandler = { [weak self] in
            self?.close()
        }
    }

    func show(url: URL) {
        update(url: url)
        panel.title = url.lastPathComponent
        let wasVisible = panel.isVisible
        shouldRestoreFocusOnClose = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if !wasVisible {
            onVisibilityChange?(true)
        }
    }

    func update(url: URL) {
        let previewItem = url as NSURL
        if (previewView.previewItem as? NSURL) != previewItem {
            previewView.previewItem = previewItem
        } else {
            previewView.refreshPreviewItem()
        }
        panel.title = url.lastPathComponent
    }

    func close(restoreFocus: Bool = true) {
        guard panel.isVisible else { return }
        shouldRestoreFocusOnClose = restoreFocus
        panel.orderOut(nil)
        handleDidHide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    private func handleDidHide() {
        onVisibilityChange?(false)

        let shouldRestoreFocus = shouldRestoreFocusOnClose
        shouldRestoreFocusOnClose = true
        if shouldRestoreFocus {
            onClose?()
        }
    }
}
