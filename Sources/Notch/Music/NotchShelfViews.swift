import AppKit
@preconcurrency import QuickLookUI
import SwiftUI

struct ShelfPanelView: View {
    @ObservedObject var shelf: NotchShelfViewModel

    var body: some View {
        VStack(spacing: 10) {
            if shelf.hasItems {
                ShelfBrowserView(shelf: shelf)
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

private struct ShelfBrowserView: NSViewRepresentable {
    @ObservedObject var shelf: NotchShelfViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(shelf: shelf)
    }

    func makeNSView(context: Context) -> NSScrollView {
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
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let collectionView = ShelfCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        collectionView.shelfCoordinator = context.coordinator
        collectionView.register(
            ShelfCollectionItem.self,
            forItemWithIdentifier: ShelfCollectionItem.identifier
        )
        collectionView.registerForDraggedTypes([.fileURL, .URL, .string])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = collectionView
        context.coordinator.collectionView = collectionView
        context.coordinator.reloadData()
        context.coordinator.syncSelectionToCollectionView()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.shelf = shelf
        context.coordinator.reloadData()
        context.coordinator.syncSelectionToCollectionView()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.cleanupWhenShelfDisappears()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var shelf: NotchShelfViewModel
        weak var collectionView: ShelfCollectionView?
        private var isSyncingSelection = false
        private var lastSnapshot: [UUID] = []
        private var draggedItemIDs: [UUID] = []
        private var _quickLookController: ShelfQuickLookPanelController?
        private func requireQuickLookController() -> ShelfQuickLookPanelController {
            if let existing = _quickLookController { return existing }
            let newController = ShelfQuickLookPanelController()
            newController.onClose = { [weak self] in
                self?.restoreShelfFocus()
            }
            _quickLookController = newController
            return newController
        }

        init(shelf: NotchShelfViewModel) {
            self.shelf = shelf
            super.init()
        }

        func reloadData() {
            let snapshot = shelf.items.map(\.id)
            guard snapshot != lastSnapshot else { return }
            lastSnapshot = snapshot
            collectionView?.reloadData()
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

            item.configure(with: shelf.items[indexPath.item])
            return item
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
            guard draggingInfo.draggingSource as AnyObject? === collectionView,
                  !draggedItemIDs.isEmpty else {
                return []
            }

            proposedDropOperation.pointee = .before
            return .move
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath destinationIndexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            guard draggingInfo.draggingSource as AnyObject? === collectionView,
                  !draggedItemIDs.isEmpty else {
                return false
            }

            let destinationIndex = min(destinationIndexPath.item, shelf.items.count)
            shelf.moveItems(with: draggedItemIDs, to: destinationIndex)
            reloadData()
            syncSelectionToCollectionView()
            draggedItemIDs.removeAll()
            return true
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
            shelf.removeSelectedItems()
            reloadData()
            syncSelectionToCollectionView()
            refreshQuickLookIfNeeded()
        }

        private func restoreShelfFocus() {
            guard let collectionView else { return }
            NSApp.activate(ignoringOtherApps: true)
            collectionView.window?.orderFrontRegardless()
            collectionView.window?.makeKey()
            collectionView.window?.makeFirstResponder(collectionView)
        }

        func cleanupWhenShelfDisappears() {
            _quickLookController?.close(restoreFocus: false)
            
            // Aggressively flush memory caches when shelf is hidden
            WorkspaceIconCache.shared.clearAll()
            Task {
                await NotchShelfThumbnailService.shared.clearAllCache()
            }
        }
    }
}

private final class ShelfCollectionView: NSCollectionView {
    weak var shelfCoordinator: ShelfBrowserView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

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
    static let preferredSize = NSSize(width: 108, height: 104)
    private static let previewSize = CGSize(width: 58, height: 58)

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

    func configure(with item: NotchShelfItem) {
        currentItemID = item.id
        thumbnailTask?.cancel()
        thumbnailTask = nil

        shelfView.titleField.stringValue = item.displayName
        shelfView.previewImageView.image = fallbackIcon(for: item)
        shelfView.applySelection(isSelected)

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

private final class ShelfCollectionItemView: NSView {
    let previewImageView = NSImageView()
    let titleField = NSTextField(labelWithString: "")

    private let backgroundView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func reset() {
        previewImageView.image = nil
        titleField.stringValue = ""
        applySelection(false)
    }

    func applySelection(_ selected: Bool) {
        backgroundView.layer?.backgroundColor = selected
            ? NSColor.systemBlue.withAlphaComponent(0.16).cgColor
            : NSColor.white.withAlphaComponent(0.035).cgColor
        backgroundView.layer?.borderColor = selected
            ? NSColor.systemBlue.withAlphaComponent(0.72).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        backgroundView.layer?.borderWidth = selected ? 1.5 : 1
    }

    private func setup() {
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewImageView)

        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .white.withAlphaComponent(0.92)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.cell?.wraps = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            previewImageView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            previewImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 58),
            previewImageView.heightAnchor.constraint(equalToConstant: 58),

            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleField.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 8),
            titleField.heightAnchor.constraint(equalToConstant: 30),
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
private final class ShelfQuickLookPanelController {
    private let panel: ShelfQuickLookPanel
    private let previewView: QLPreviewView
    var onClose: (() -> Void)?

    var isVisible: Bool {
        panel.isVisible
    }

    init() {
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
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
        panel.orderOut(nil)
        if restoreFocus {
            onClose?()
        }
    }
}
