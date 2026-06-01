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
            return "https://notch-portal-api-657193756037.asia-southeast1.run.app/api"
        case .development:
            return "http://localhost:8080/api"
        }
    }

    var webOriginURL: String {
        switch self {
        case .production:
            return "https://notch-portal-web.vercel.app"
        case .development:
            return "http://localhost:5173"
        }
    }
}

enum PortalHostedBackend {
    static var defaultURL: String {
        #if DEBUG
        let envString = UserDefaults.standard.string(forKey: "dev.notch.environment") ?? "development"
        let env = NotchEnvironment(rawValue: envString) ?? .production
        return env.portalURL
        #else
        return NotchEnvironment.production.portalURL
        #endif
    }
}
