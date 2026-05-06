import Combine
import Foundation
import SwiftUI

@MainActor
final class NotchShortcutViewModel: ObservableObject {
    let store: ShortcutStore

    @Published var isEditing = false
    @Published var editingItem: ShortcutItem?
    @Published var isShowingAddSheet = false
    @Published var executionError: ExecutionErrorInfo?
    @Published var pendingApprovalItem: ShortcutItem?

    struct ExecutionErrorInfo: Identifiable {
        let id = UUID()
        let itemName: String
        let message: String
    }

    init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
    }

    var items: [ShortcutItem] {
        store.items
    }

    var hasItems: Bool {
        !store.items.isEmpty
    }

    // MARK: - Actions

    func add(_ item: ShortcutItem) {
        store.add(item)
    }

    func update(_ item: ShortcutItem) {
        store.update(item)
    }

    func delete(_ item: ShortcutItem) {
        store.delete(item)
    }

    func delete(at offsets: IndexSet) {
        store.delete(at: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        store.move(from: source, to: destination)
    }

    func execute(_ item: ShortcutItem) {
        Task {
            do {
                try await ShortcutExecutor.execute(item)
            } catch {
                executionError = ExecutionErrorInfo(
                    itemName: item.name,
                    message: error.localizedDescription
                )
            }
        }
    }

    func requestApproval(for item: ShortcutItem, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        pendingApprovalItem = item
        // The approval callback is stored; the view will present a confirmation sheet
        // and call resolveApproval() with the user's decision.
        approvalContinuation = completion
    }

    func resolveApproval(_ approved: Bool) {
        pendingApprovalItem = nil
        approvalContinuation?(approved)
        approvalContinuation = nil
    }

    private var approvalContinuation: (@MainActor @Sendable (Bool) -> Void)?

    // MARK: - Edit mode

    func startEditing(_ item: ShortcutItem) {
        editingItem = item
        isShowingAddSheet = true
    }

    func startAdding() {
        editingItem = nil
        isShowingAddSheet = true
    }

    func finishEditing() {
        editingItem = nil
        isShowingAddSheet = false
    }
}
