import Foundation
import AuthenticationServices

/// Protocol defining a connector to external services
protocol Connector: Identifiable, ObservableObject {
    /// Unique identifier for the connector
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this connector provides
    var description: String { get }

    /// Icon name (SF Symbols) for UI display
    var icon: String { get }

    /// Whether the connector is currently authenticated
    var isAuthenticated: Bool { get }

    /// Current connection status
    var status: ConnectorStatus { get }

    /// OAuth configuration if applicable
    var oauthConfig: OAuthConfig? { get }

    /// Tools provided by this connector
    var tools: [any Tool] { get }

    /// Authenticate with the service
    func authenticate() async throws

    /// Disconnect from the service
    func disconnect() async

    /// Refresh authentication if needed
    func refreshIfNeeded() async throws
}

/// Default implementations
extension Connector {
    var oauthConfig: OAuthConfig? { nil }

    func refreshIfNeeded() async throws {
        // Default: no-op
    }
}

/// Connection status for a connector
enum ConnectorStatus: String, Codable {
    case disconnected
    case connecting
    case connected
    case error
    case authRequired
}

/// OAuth2 configuration
struct OAuthConfig {
    let clientId: String
    let clientSecret: String?
    let authorizationURL: URL
    let tokenURL: URL
    let redirectURL: URL
    let scopes: [String]

    /// Standard OAuth2 providers
    static func google(clientId: String, scopes: [String]) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: nil,
            authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            redirectURL: URL(string: "com.openwork.OpenWork:/oauth2redirect")!,
            scopes: scopes
        )
    }

    static func notion(clientId: String, clientSecret: String) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationURL: URL(string: "https://api.notion.com/v1/oauth/authorize")!,
            tokenURL: URL(string: "https://api.notion.com/v1/oauth/token")!,
            redirectURL: URL(string: "com.openwork.OpenWork:/oauth2redirect")!,
            scopes: []
        )
    }
}

/// Stored connector credentials
struct ConnectorCredentials: Codable {
    var connectorId: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var additionalData: [String: String]?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

/// Manages connector registration and lifecycle
@MainActor
class ConnectorRegistry: ObservableObject {
    static let shared = ConnectorRegistry()

    @Published private(set) var availableConnectors: [any Connector] = []
    @Published private(set) var connectedConnectors: [String] = []

    private weak var toolRegistry: ToolRegistry?

    private init() {
        registerBuiltinConnectors()
    }

    func setToolRegistry(_ registry: ToolRegistry) {
        self.toolRegistry = registry
    }

    /// Register a connector
    func register(_ connector: any Connector) {
        if !availableConnectors.contains(where: { $0.id == connector.id }) {
            availableConnectors.append(connector)
        }
    }

    /// Get connector by ID
    func connector(forID id: String) -> (any Connector)? {
        availableConnectors.first { $0.id == id }
    }

    /// Connect a connector (authenticate and register tools)
    func connect(id: String) async throws {
        guard let connector = connector(forID: id) else {
            throw ConnectorError.notFound(id)
        }

        try await connector.authenticate()

        // Register connector tools
        if let toolRegistry = toolRegistry {
            for tool in connector.tools {
                toolRegistry.register(tool)
            }
        }

        if !connectedConnectors.contains(id) {
            connectedConnectors.append(id)
        }
    }

    /// Disconnect a connector
    func disconnect(id: String) async {
        guard let connector = connector(forID: id) else { return }

        await connector.disconnect()

        // Unregister connector tools
        if let toolRegistry = toolRegistry {
            for tool in connector.tools {
                toolRegistry.unregister(id: tool.id)
            }
        }

        connectedConnectors.removeAll { $0 == id }
    }

    /// Check if connector is connected
    func isConnected(_ id: String) -> Bool {
        connectedConnectors.contains(id)
    }

    private func registerBuiltinConnectors() {
        register(GoogleDriveConnector())
        register(NotionConnector())
    }
}

/// Connector-related errors
enum ConnectorError: LocalizedError {
    case notFound(String)
    case authenticationFailed(String)
    case tokenExpired
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Connector not found: \(id)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExpired:
            return "Authentication token expired"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from service"
        }
    }
}

/// OAuth2 authentication helper
class OAuth2Helper: NSObject {
    private var authSession: ASWebAuthenticationSession?
    private weak var presentationAnchor: ASPresentationAnchor?

    @MainActor
    func authenticate(
        config: OAuthConfig,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> ConnectorCredentials {
        self.presentationAnchor = presentationAnchor

        // Build authorization URL
        var urlComponents = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        let authURL = urlComponents.url!
        let scheme = config.redirectURL.scheme

        // Perform web authentication
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: ConnectorError.authenticationFailed("No callback URL"))
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.authSession = session

            Task { @MainActor in
                session.start()
            }
        }

        // Extract authorization code
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ConnectorError.authenticationFailed("No authorization code in callback")
        }

        // Exchange code for tokens
        return try await exchangeCodeForTokens(code: code, config: config)
    }

    private func exchangeCodeForTokens(code: String, config: OAuthConfig) async throws -> ConnectorCredentials {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = [
            "code": code,
            "client_id": config.clientId,
            "redirect_uri": config.redirectURL.absoluteString,
            "grant_type": "authorization_code"
        ]

        if let clientSecret = config.clientSecret {
            body["client_secret"] = clientSecret
        }

        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.authenticationFailed("Token exchange failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ConnectorError.invalidResponse
        }

        let refreshToken = json["refresh_token"] as? String
        let expiresIn = json["expires_in"] as? Int
        let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }

        return ConnectorCredentials(
            connectorId: "",
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}

extension OAuth2Helper: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationAnchor ?? NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
