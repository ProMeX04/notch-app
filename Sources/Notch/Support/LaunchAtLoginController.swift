import AppKit
import ServiceManagement

@MainActor
final class LaunchAtLoginController {
    enum LaunchAtLoginError: LocalizedError {
        case unsupportedStatus

        var errorDescription: String? {
            switch self {
            case .unsupportedStatus:
                return "Couldn't determine the current launch-at-login status."
            }
        }
    }

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    func refreshStatus() {
        _ = service.status
    }

    func setEnabled(_ enabled: Bool) throws {
        let currentStatus = service.status
        guard currentStatus != .notFound else {
            throw LaunchAtLoginError.unsupportedStatus
        }

        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
