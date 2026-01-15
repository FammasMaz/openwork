import XCTest
@testable import OpenWork

@MainActor
final class ConnectorRegistryTests: XCTestCase {

    var connectorRegistry: ConnectorRegistry!

    override func setUp() async throws {
        connectorRegistry = ConnectorRegistry.shared
    }

    override func tearDown() async throws {
        // Disconnect all connectors
        for connector in connectorRegistry.availableConnectors {
            await connectorRegistry.disconnect(id: connector.id)
        }
    }

    // MARK: - Available Connectors

    func testConnectorsAvailable() {
        XCTAssertFalse(connectorRegistry.availableConnectors.isEmpty)
    }

    func testGoogleDriveConnectorExists() {
        let gdrive = connectorRegistry.availableConnectors.first { $0.id == "google-drive" }
        XCTAssertNotNil(gdrive)
    }

    func testNotionConnectorExists() {
        let notion = connectorRegistry.availableConnectors.first { $0.id == "notion" }
        XCTAssertNotNil(notion)
    }

    // MARK: - Connector Properties

    func testGoogleDriveProperties() {
        guard let gdrive = connectorRegistry.availableConnectors.first(where: { $0.id == "google-drive" }) else {
            XCTFail("Google Drive connector not found")
            return
        }

        XCTAssertEqual(gdrive.name, "Google Drive")
        XCTAssertFalse(gdrive.description.isEmpty)
        XCTAssertFalse(gdrive.icon.isEmpty)
    }

    func testNotionProperties() {
        guard let notion = connectorRegistry.availableConnectors.first(where: { $0.id == "notion" }) else {
            XCTFail("Notion connector not found")
            return
        }

        XCTAssertEqual(notion.name, "Notion")
        XCTAssertFalse(notion.description.isEmpty)
        XCTAssertFalse(notion.icon.isEmpty)
    }

    // MARK: - Authentication State

    func testInitialAuthenticationState() {
        for connector in connectorRegistry.availableConnectors {
            // All connectors should start disconnected
            XCTAssertEqual(connector.status, .disconnected)
            XCTAssertFalse(connector.isAuthenticated)
        }
    }

    // MARK: - Disconnect

    func testDisconnect() async {
        let connectorId = "google-drive"

        await connectorRegistry.disconnect(id: connectorId)

        let connector = connectorRegistry.availableConnectors.first { $0.id == connectorId }
        XCTAssertEqual(connector?.status, .disconnected)
    }

    // MARK: - OAuth Config

    func testGoogleDriveOAuthConfigNil() {
        // Without client ID configured, should be nil
        guard let gdrive = connectorRegistry.availableConnectors.first(where: { $0.id == "google-drive" }) else {
            XCTFail("Google Drive connector not found")
            return
        }

        // OAuth config depends on UserDefaults configuration
        // If not configured, it should be nil
        if UserDefaults.standard.string(forKey: "GoogleDrive.ClientID") == nil {
            XCTAssertNil(gdrive.oauthConfig)
        }
    }

    func testNotionOAuthConfigNil() {
        guard let notion = connectorRegistry.availableConnectors.first(where: { $0.id == "notion" }) else {
            XCTFail("Notion connector not found")
            return
        }

        if UserDefaults.standard.string(forKey: "Notion.ClientID") == nil {
            XCTAssertNil(notion.oauthConfig)
        }
    }

    // MARK: - Tools

    func testConnectorTools() {
        for connector in connectorRegistry.availableConnectors {
            let tools = connector.tools
            XCTAssertFalse(tools.isEmpty, "Connector \(connector.id) should have tools")
        }
    }

    // MARK: - Connector Lookup

    func testConnectorForID() {
        let connector = connectorRegistry.connector(forID: "google-drive")
        XCTAssertNotNil(connector)
        XCTAssertEqual(connector?.id, "google-drive")
    }

    func testConnectorForIDNotFound() {
        let connector = connectorRegistry.connector(forID: "nonexistent")
        XCTAssertNil(connector)
    }

    // MARK: - Connection State

    func testIsConnectedFalseInitially() {
        XCTAssertFalse(connectorRegistry.isConnected("google-drive"))
        XCTAssertFalse(connectorRegistry.isConnected("notion"))
    }
}

// MARK: - ConnectorStatus Tests

final class ConnectorStatusTests: XCTestCase {

    func testAllStatusValues() {
        let allStatuses: [ConnectorStatus] = [.disconnected, .connecting, .connected, .error, .authRequired]

        XCTAssertEqual(allStatuses.count, 5)
    }

    func testStatusRawValues() {
        XCTAssertEqual(ConnectorStatus.disconnected.rawValue, "disconnected")
        XCTAssertEqual(ConnectorStatus.connecting.rawValue, "connecting")
        XCTAssertEqual(ConnectorStatus.connected.rawValue, "connected")
        XCTAssertEqual(ConnectorStatus.error.rawValue, "error")
        XCTAssertEqual(ConnectorStatus.authRequired.rawValue, "authRequired")
    }

    func testStatusCodable() throws {
        let status = ConnectorStatus.connected
        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(ConnectorStatus.self, from: encoded)

        XCTAssertEqual(decoded, status)
    }
}

// MARK: - ConnectorCredentials Tests

final class ConnectorCredentialsTests: XCTestCase {

    func testCredentialsCreation() {
        let creds = ConnectorCredentials(
            connectorId: "google-drive",
            accessToken: "access-token-123",
            refreshToken: "refresh-token-456",
            expiresAt: Date().addingTimeInterval(3600)
        )

        XCTAssertEqual(creds.connectorId, "google-drive")
        XCTAssertEqual(creds.accessToken, "access-token-123")
        XCTAssertEqual(creds.refreshToken, "refresh-token-456")
    }

    func testCredentialsNotExpired() {
        let creds = ConnectorCredentials(
            connectorId: "test",
            accessToken: "token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600) // 1 hour from now
        )

        XCTAssertFalse(creds.isExpired)
    }

    func testCredentialsExpired() {
        let creds = ConnectorCredentials(
            connectorId: "test",
            accessToken: "token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )

        XCTAssertTrue(creds.isExpired)
    }

    func testCredentialsNoExpiry() {
        let creds = ConnectorCredentials(
            connectorId: "test",
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil
        )

        XCTAssertFalse(creds.isExpired)
    }

    func testCodable() throws {
        let creds = ConnectorCredentials(
            connectorId: "test",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date()
        )

        let encoded = try JSONEncoder().encode(creds)
        let decoded = try JSONDecoder().decode(ConnectorCredentials.self, from: encoded)

        XCTAssertEqual(decoded.connectorId, creds.connectorId)
        XCTAssertEqual(decoded.accessToken, creds.accessToken)
        XCTAssertEqual(decoded.refreshToken, creds.refreshToken)
    }
}

// MARK: - OAuthConfig Tests

final class OAuthConfigTests: XCTestCase {

    func testGoogleConfig() {
        let config = OAuthConfig.google(
            clientId: "test-client-id",
            scopes: ["scope1", "scope2"]
        )

        XCTAssertEqual(config.clientId, "test-client-id")
        XCTAssertEqual(config.scopes, ["scope1", "scope2"])
        XCTAssertTrue(config.authorizationURL.absoluteString.contains("accounts.google.com"))
        XCTAssertTrue(config.tokenURL.absoluteString.contains("oauth2.googleapis.com"))
    }

    func testNotionConfig() {
        let config = OAuthConfig.notion(
            clientId: "notion-client-id",
            clientSecret: "notion-secret"
        )

        XCTAssertEqual(config.clientId, "notion-client-id")
        XCTAssertEqual(config.clientSecret, "notion-secret")
        XCTAssertTrue(config.authorizationURL.absoluteString.contains("notion.com"))
    }

    func testRedirectURL() {
        let config = OAuthConfig.google(clientId: "test", scopes: [])
        XCTAssertEqual(config.redirectURL.scheme, "com.openwork.OpenWork")
    }
}

// MARK: - ConnectorError Tests

final class ConnectorErrorTests: XCTestCase {

    func testNotFoundError() {
        let error = ConnectorError.notFound("test-connector")
        XCTAssertTrue(error.errorDescription?.contains("test-connector") == true)
    }

    func testTokenExpiredError() {
        let error = ConnectorError.tokenExpired
        XCTAssertEqual(error.errorDescription, "Authentication token expired")
    }

    func testInvalidResponseError() {
        let error = ConnectorError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from service")
    }

    func testAuthenticationFailedError() {
        let error = ConnectorError.authenticationFailed("Bad credentials")
        XCTAssertTrue(error.errorDescription?.contains("Bad credentials") == true)
    }

    func testNetworkError() {
        let error = ConnectorError.networkError(NSError(domain: "test", code: -1))
        XCTAssertNotNil(error.errorDescription)
    }
}
