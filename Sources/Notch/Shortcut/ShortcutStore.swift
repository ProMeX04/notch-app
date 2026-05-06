import Combine
import Foundation

@MainActor
final class ShortcutStore: ObservableObject {
    @Published var items: [ShortcutItem] = []

    private static let storageKey = "dev.notch.shortcuts"

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ item: ShortcutItem) {
        var newItem = item
        newItem.sortOrder = items.count
        items.append(newItem)
        save()
    }

    func update(_ item: ShortcutItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func delete(_ item: ShortcutItem) {
        items.removeAll { $0.id == item.id }
        reindex()
        save()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        reindex()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        reindex()
        save()
    }

    // MARK: - Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ShortcutItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func reindex() {
        for i in items.indices {
            items[i].sortOrder = i
        }
    }
}
