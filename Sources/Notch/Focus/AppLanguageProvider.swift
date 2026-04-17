import Combine
import Foundation

@MainActor
final class AppLanguageProvider: ObservableObject {
    static let storageKey = "app_language"

    @Published private(set) var currentLanguage: String

    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        currentLanguage = userDefaults.string(forKey: Self.storageKey) ?? "English"

        notificationCenter.publisher(for: UserDefaults.didChangeNotification, object: userDefaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        let resolvedLanguage = userDefaults.string(forKey: Self.storageKey) ?? "English"
        guard currentLanguage != resolvedLanguage else { return }
        currentLanguage = resolvedLanguage
    }
}
