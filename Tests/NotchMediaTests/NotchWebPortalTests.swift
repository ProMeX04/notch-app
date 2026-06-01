import XCTest
@testable import Notch

final class NotchWebPortalTests: XCTestCase {
    func testProductionURLMapping() {
        let prodAPI = URL(string: "https://notch-portal-api-657193756037.asia-southeast1.run.app/api")!
        let signup = NotchWebPortal.signupURL(apiBaseURL: prodAPI)
        XCTAssertEqual(signup.absoluteString, "https://notch-portal-web.vercel.app/signup")
        
        let login = NotchWebPortal.loginURL(apiBaseURL: prodAPI)
        XCTAssertEqual(login.absoluteString, "https://notch-portal-web.vercel.app/login")

        let oauth = NotchWebPortal.oauthAuthorizeURL(
            clientID: "client123",
            redirectURI: "redirect123",
            state: "state123",
            codeChallenge: "challenge123",
            apiBaseURL: prodAPI
        )
        XCTAssertTrue(oauth.absoluteString.hasPrefix("https://notch-portal-web.vercel.app/oauth/authorize"))
    }

    func testDevelopmentURLMapping() {
        let devAPI = URL(string: "http://localhost:8080/api")!
        let signup = NotchWebPortal.signupURL(apiBaseURL: devAPI)
        XCTAssertEqual(signup.absoluteString, "http://localhost:5173/signup")
    }

    func testCustomURLMappingFallback() {
        let customAPI = URL(string: "https://custom-api.example.com/api")!
        let signup = NotchWebPortal.signupURL(apiBaseURL: customAPI)
        XCTAssertEqual(signup.absoluteString, "https://custom-api.example.com/signup")
    }

    func testEnvironmentOverride() {
        let processInfo = ProcessInfo()
        // We will mock the environment by passing processInfo after setting the env variable
        setenv("NOTCH_WEB_ORIGIN", "https://override.example.com", 1)
        defer {
            unsetenv("NOTCH_WEB_ORIGIN")
        }
        
        let signup = NotchWebPortal.signupURL(apiBaseURL: URL(string: "https://anything.com/api")!, processInfo: processInfo)
        XCTAssertEqual(signup.absoluteString, "https://override.example.com/signup")
    }
}
