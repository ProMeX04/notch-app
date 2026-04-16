import AppKit
import Foundation

/// Website URLs for account signup, login, and Pro checkout (opened in the default browser).
///
/// Override the site root with env `NOTCH_WEB_ORIGIN` (e.g. `https://example.com`).
/// Paths default to `/signup`, `/login`, and `/pro` under that origin.
enum NotchWebPortal {
    /// Public base URL for HTML portal (same path prefix as the API, e.g. `https://host/notch`).
    private static func originURL(processInfo: ProcessInfo) -> URL {
        if let raw = processInfo.environment["NOTCH_WEB_ORIGIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        guard let api = URL(string: GeminiLiveHostedBackend.defaultURL) else {
            return URL(string: "https://portal-promex04s-projects.vercel.app")!
        }
        if let components = URLComponents(url: api, resolvingAgainstBaseURL: false),
           let scheme = components.scheme,
           let host = components.host {
            var root = "\(scheme)://\(host)"
            if let port = components.port {
                root += ":\(port)"
            }
            return URL(string: root) ?? api
        }

        return api
    }

    static func signupURL(processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(processInfo: processInfo, path: "signup")
    }

    static func loginURL(processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(processInfo: processInfo, path: "login")
    }

    /// Checkout / pricing page for **Notch Pro** (web purchase).
    static func proCheckoutURL(processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(processInfo: processInfo, path: "pro")
    }

    static func authBridgeURL(token: String, processInfo: ProcessInfo = .processInfo) -> URL {
        var components = URLComponents(url: pathURL(processInfo: processInfo, path: "auth/bridge"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url ?? pathURL(processInfo: processInfo, path: "auth/bridge")
    }

    private static func pathURL(processInfo: ProcessInfo, path: String) -> URL {
        originURL(processInfo: processInfo).appendingPathComponent(path)
    }

    static func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
