import AppKit
import Foundation

/// Website URLs for account signup, login, and Pro checkout (opened in the default browser).
///
/// Override the site root with env `NOTCH_WEB_ORIGIN` (e.g. `https://example.com`).
/// Paths default to `/signup`, `/login`, and `/pro` under that origin.
enum NotchWebPortal {
    /// Public base URL for HTML portal (same path prefix as the API, e.g. `https://host/notch`).
    private static func originURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo) -> URL {
        if let raw = processInfo.environment["NOTCH_WEB_ORIGIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        let resolvedAPI = apiBaseURL ?? URL(string: PortalHostedBackend.defaultURL)
        guard let api = resolvedAPI else {
            #if DEBUG
            let defaultEnv = "development"
            #else
            let defaultEnv = "production"
            #endif
            let envString = UserDefaults.standard.string(forKey: "dev.notch.environment") ?? defaultEnv
            let env = NotchEnvironment(rawValue: envString) ?? .production
            return URL(string: env.webOriginURL)!
        }

        if let trimmedAPI = trimmedPortalOrigin(from: api) {
            return trimmedAPI
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

    static func signupURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "signup")
    }

    static func loginURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "login")
    }

    /// Checkout / pricing page for **Notch Pro** (web purchase).
    static func proCheckoutURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "pro")
    }

    static func googleDriveAuthURL(
        apiBaseURL: URL? = nil,
        state: String? = nil,
        codeChallenge: String? = nil,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        let baseURL = pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "api/auth/google-drive")
        guard let state, !state.isEmpty else {
            return baseURL
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "state", value: state)]
        if let codeChallenge, !codeChallenge.isEmpty {
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
        }
        components?.queryItems = queryItems
        return components?.url ?? baseURL
    }

    static func googleDriveRefreshURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo = .processInfo) -> URL {
        pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "api/auth/google-drive/refresh")
    }

    static func oauthAuthorizeURL(
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String,
        identityProvider: String? = nil,
        apiBaseURL: URL? = nil,
        processInfo: ProcessInfo = .processInfo
    ) -> URL {
        var components = URLComponents(
            url: pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "oauth/authorize"),
            resolvingAgainstBaseURL: false
        )

        var queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let identityProvider {
            // Common parameter names for forcing a specific IdP (Keycloak, Auth0, Supabase, etc.)
            queryItems.append(URLQueryItem(name: "provider", value: identityProvider))
            queryItems.append(URLQueryItem(name: "kc_idp_hint", value: identityProvider))
            queryItems.append(URLQueryItem(name: "connection", value: identityProvider))
        }

        components?.queryItems = queryItems
        return components?.url ?? pathURL(apiBaseURL: apiBaseURL, processInfo: processInfo, path: "oauth/authorize")
    }

    private static func pathURL(apiBaseURL: URL? = nil, processInfo: ProcessInfo, path: String) -> URL {
        originURL(apiBaseURL: apiBaseURL, processInfo: processInfo).appendingPathComponent(path)
    }

    private static func trimmedPortalOrigin(from apiBaseURL: URL) -> URL? {
        guard let components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host else {
            return nil
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/api" {
            path = ""
        } else if path.hasSuffix("/api") {
            path = String(path.dropLast("/api".count))
        }

        var root = "\(scheme)://\(host)"
        if let port = components.port {
            root += ":\(port)"
        }
        root += path
        return URL(string: root)
    }

    static func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
