import Combine
import Foundation

@MainActor
final class QuickKeyStore: ObservableObject {
    static let shared = QuickKeyStore()

    @Published var mappings: [QuickKeyMapping] = []
    @Published var isEngineEnabled: Bool = true {
        didSet {
            guard !isLoading, oldValue != isEngineEnabled else { return }
            persistEngineFlag()
            syncEngine()
        }
    }

    private let mappingsKey = "notch.quickkey.mappings"
    private let engineKey = "notch.quickkey.engineEnabled"
    private let defaults = UserDefaults.standard
    private var isLoading = false

    private init() {
        load()
    }

    func load() {
        isLoading = true
        isEngineEnabled = defaults.object(forKey: engineKey) as? Bool ?? true
        if let data = defaults.data(forKey: mappingsKey),
           let decoded = try? JSONDecoder().decode([QuickKeyMapping].self, from: data) {
            mappings = decoded
        } else {
            mappings = []
        }
        isLoading = false
    }

    func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            defaults.set(data, forKey: mappingsKey)
        }
        persistEngineFlag()
        NotificationCenter.default.post(name: .quickKeyMappingsDidChange, object: nil)
        syncEngine()
    }

    private func persistEngineFlag() {
        defaults.set(isEngineEnabled, forKey: engineKey)
    }

    private func syncEngine() {
        NotificationCenter.default.post(name: .quickKeyMappingsDidChange, object: nil)
        if isEngineEnabled, QuickKeyAccessibility.isTrusted {
            QuickKeyEngine.shared.restartIfNeeded()
        } else {
            QuickKeyEngine.shared.stop()
        }
    }

    func add(_ mapping: QuickKeyMapping) {
        mappings.append(mapping)
        save()
    }

    func update(_ mapping: QuickKeyMapping) {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index] = mapping
        save()
    }

    func delete(_ mapping: QuickKeyMapping) {
        mappings.removeAll { $0.id == mapping.id }
        save()
    }

    func toggle(_ mapping: QuickKeyMapping) {
        guard let index = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[index].isEnabled.toggle()
        save()
    }

    var enabledCount: Int {
        mappings.reduce(0) { $0 + ($1.isEnabled ? 1 : 0) }
    }
}
