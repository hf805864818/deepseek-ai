import Foundation
import UIKit
import SafariServices
import CryptoKit
import os.log

private let logger = AppLogger(category: "GoogleDriveOAuth")

// MARK: - Token Storage Model

struct GoogleDriveTokenStorage: Codable {
    let accessToken: String
    let refreshToken: String?
    let expireDate: Date?
    let lastRefresh: Date?

    var isExpired: Bool {
        guard let expire = expireDate else { return false }
        return expire < Date()
    }
}

// MARK: - OAuth Manager

/// Google Drive OAuth manager (Desktop app client type).
/// Uses PKCE + client_secret — required for Desktop app OAuth clients.
/// Follows the same pattern as GeminiOAuthManager but simplified
/// for a single-account (singleton) use case.
@MainActor
final class GoogleDriveOAuthManager: NSObject, ObservableObject {

    static let shared = GoogleDriveOAuthManager()

    // MARK: - OAuth Config (Desktop app client — requires client_secret)
    // Changed from iOS type to Desktop app type to support localhost redirect.
    // Desktop app clients allow http://localhost callback URIs natively,
    // but require client_secret for both token exchange and refresh.

    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v1/userinfo"
    private let clientID = "483538693797-hs0c9jrjg9b4s0pcj5hphrv20mrvf3d7.apps.googleusercontent.com"
    private let clientSecret = "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"
    private let callbackPort: UInt16 = 8086
    private var redirectURI: String { "http://localhost:\(callbackPort)/oauth2callback" }
    private let scopes = "https://www.googleapis.com/auth/drive.file"

    // MARK: - Keychain Config

    private let keychainService = "com.openminis.app.gdrive-oauth"
    private let keychainAccount = "token"
    private let emailKeychainAccount = "oauth-email"

    // MARK: - Published State

    @Published private(set) var isAuthenticating = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var userEmail: String?

    // MARK: - Private

    private var callbackServer: OAuthCallbackServer?
    private weak var safariVC: SFSafariViewController?

    /// Instance-level single-flight for token refresh. Prevents N concurrent
    /// callers from firing N refresh requests simultaneously.
    private var inFlightRefresh: Task<GoogleDriveTokenStorage, Error>?

    private override init() {
        super.init()
        isAuthenticated = loadToken()?.accessToken != nil
        userEmail = loadKeychainString(account: emailKeychainAccount)
    }

    // MARK: - Public API

    /// Initiates the OAuth login flow: starts a local callback server, opens
    /// SFSafariViewController for the user to authorize, then exchanges the
    /// authorization code for tokens via PKCE. Fetches the user email for
    /// display in the UI.
    func login() async throws {
        logger.info("=== Google Drive OAuth login started ===")
        // Defensive cleanup: stop any leftover server from a previous failed attempt
        callbackServer?.stop()
        callbackServer = nil
        isAuthenticating = true
        defer {
            isAuthenticating = false
            callbackServer?.stop()
            callbackServer = nil
            safariVC?.dismiss(animated: true)
            safariVC = nil
        }

        let state = generateState()
        let pkce = generatePKCE()

        // 1. Start local HTTP server
        let server = OAuthCallbackServer(port: callbackPort, callbackPath: "/oauth2callback")
        self.callbackServer = server
        try server.start()
        logger.info("Callback server started on port \(self.callbackPort)")

        // 2. Build authorization URL with PKCE (S256)
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let authorizationURL = components.url!
        logger.info("Authorization URL: \(authorizationURL.absoluteString)")

        // 3. Open in-app Safari
        presentSafariViewController(url: authorizationURL)

        // 4. Wait for callback (5 min timeout)
        let result = try await server.waitForCallback(timeout: 300)
        logger.info("Callback received — code length: \(result.code.count)")

        // 5. Validate state
        guard result.state == state else {
            logger.error("State mismatch!")
            throw LLMError.providerError(message: "OAuth state mismatch")
        }

        // 6. Exchange code for token (with PKCE verifier + client_secret
        //    for Desktop app type OAuth client)
        let token = try await exchangeCode(result.code, codeVerifier: pkce.verifier)
        saveToken(token)

        // 7. Fetch user email for display
        if let email = try? await fetchUserEmail(token: token.accessToken) {
            saveKeychainString(email, account: emailKeychainAccount)
            userEmail = email
            logger.info("User email fetched: \(email)")
        }

        isAuthenticated = true
        logger.info("=== Google Drive OAuth login complete ===")
    }

    /// Clears all stored tokens and email from Keychain.
    func logout() {
        logger.info("Google Drive logout — clearing token")
        deleteToken()
        deleteKeychainString(account: emailKeychainAccount)
        isAuthenticated = false
        userEmail = nil
    }

    /// Returns a valid access token, refreshing if necessary.
    /// Throws if no token is stored or refresh fails.
    func validAccessToken() async throws -> String {
        guard var storage = loadToken() else {
            throw LLMError.invalidAPIKey(detail: "Google Drive: no OAuth token found")
        }

        let needsRefresh = storage.refreshToken != nil
            && (storage.expireDate.map({ $0.timeIntervalSinceNow <= 0 }) ?? false)

        if needsRefresh {
            storage = try await refreshTokenGuarded(existingStorage: storage)
        }

        guard !storage.accessToken.isEmpty else {
            throw LLMError.invalidAPIKey(detail: "Google Drive: access token is empty")
        }
        return storage.accessToken
    }

    // MARK: - Refresh (single-flight)

    /// Refreshes the access token using the stored refresh token.
    /// Uses single-flight dedup so concurrent callers share one refresh.
    private func refreshTokenGuarded(existingStorage: GoogleDriveTokenStorage) async throws -> GoogleDriveTokenStorage {
        let staleRefreshToken = existingStorage.refreshToken!

        // Join an existing in-flight refresh if one is running
        if let existing = inFlightRefresh {
            logger.info("Joining in-flight refresh")
            return try await existing.value
        }

        logger.info("Refreshing Google Drive token on-demand...")
        let task = Task<GoogleDriveTokenStorage, Error> {
            let refreshed = try await performRefresh(refreshToken: staleRefreshToken)
            saveToken(refreshed)
            return refreshed
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }

        return try await task.value
    }

    // MARK: - State & PKCE Generation

    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedGDrive()
    }

    private func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = bytes.map { String(format: "%02x", $0) }.joined()
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64URLEncodedGDrive()
        return (verifier, challenge)
    }

    // MARK: - Token Exchange (Desktop app client — requires client_secret)

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> GoogleDriveTokenStorage {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
        ]

        return try await postTokenRequest(body: body, context: "Token exchange")
    }

    private func performRefresh(refreshToken: String) async throws -> GoogleDriveTokenStorage {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
        ]

        var storage = try await postTokenRequest(body: body, context: "Token refresh")
        // Google doesn't always return a new refresh token on refresh;
        // preserve the existing one so subsequent refreshes keep working.
        if storage.refreshToken == nil {
            storage = GoogleDriveTokenStorage(
                accessToken: storage.accessToken,
                refreshToken: refreshToken,
                expireDate: storage.expireDate,
                lastRefresh: storage.lastRefresh
            )
        }
        return storage
    }

    private func postTokenRequest(body: [String: String], context: String) async throws -> GoogleDriveTokenStorage {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let formData = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)

        logger.info("\(context) POST \(self.tokenURL)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? -1
        let responseBody = String(data: data, encoding: .utf8) ?? "<binary>"

        logger.info("\(context) Response status: \(statusCode)")

        guard (200..<300).contains(statusCode) else {
            #if DEBUG
            logger.error("\(context) FAILED — status \(statusCode): \(responseBody.prefix(500))")
            #else
            logger.error("\(context) FAILED — status \(statusCode)")
            #endif
            throw LLMError.providerError(message: "\(context) failed (status \(statusCode))")
        }

        return try parseTokenResponse(data)
    }

    private func parseTokenResponse(_ data: Data) throws -> GoogleDriveTokenStorage {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let accessToken = json["access_token"] as? String else {
            throw LLMError.decodingError(underlying: NSError(domain: "GoogleDriveOAuth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing access_token"]))
        }

        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? TimeInterval
        // Subtract 5 minutes as a safety buffer (same as GeminiOAuthManager)
        let expireDate = expiresIn.map { Date().addingTimeInterval($0 - 300) }

        return GoogleDriveTokenStorage(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expireDate: expireDate,
            lastRefresh: Date()
        )
    }

    // MARK: - User Info

    /// Fetches the user's email address using the access token.
    private func fetchUserEmail(token: String) async throws -> String? {
        var request = URLRequest(url: URL(string: userInfoURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["email"] as? String
    }

    // MARK: - In-App Safari

    private func presentSafariViewController(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var topVC = root
        while let presented = topVC.presentedViewController { topVC = presented }
        let vc = SFSafariViewController(url: url)
        topVC.present(vc, animated: true)
        self.safariVC = vc
    }

    // MARK: - Keychain

    private func saveToken(_ token: GoogleDriveTokenStorage) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadToken() -> GoogleDriveTokenStorage? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleDriveTokenStorage.self, from: data)
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func saveKeychainString(_ value: String, account: String) {
        let data = value.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadKeychainString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainString(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Helpers

private extension Data {
    func base64URLEncodedGDrive() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
