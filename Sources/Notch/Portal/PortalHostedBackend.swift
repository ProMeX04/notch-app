import Foundation

enum NotchEnvironment: String, CaseIterable, Identifiable {
    case production = "production"
    case development = "development"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .production:
            return "Production"
        case .development:
            return "Development"
        }
    }

    var portalURL: String {
        switch self {
        case .production:
            return "https://portal-six-blue.vercel.app/api"
        case .development:
            return "http://localhost:3000/api"
        }
    }

    var webOriginURL: String {
        switch self {
        case .production:
            return "https://portal-six-blue.vercel.app"
        case .development:
            return "http://localhost:3000"
        }
    }
}

enum PortalHostedBackend {
    static var defaultURL: String {
        #if DEBUG
        let defaultEnv = "development"
        #else
        let defaultEnv = "production"
        #endif
        let envString = UserDefaults.standard.string(forKey: "dev.notch.environment") ?? defaultEnv
        let env = NotchEnvironment(rawValue: envString) ?? .production
        return env.portalURL
    }
}
