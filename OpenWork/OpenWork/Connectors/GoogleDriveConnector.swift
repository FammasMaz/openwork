import Foundation
import AppKit

/// Google Drive connector for file operations
@MainActor
class GoogleDriveConnector: Connector, ObservableObject {
    let id = "google-drive"
    let name = "Google Drive"
    let description = "Access and manage files in Google Drive"
    let icon = "externaldrive.badge.icloud"

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var status: ConnectorStatus = .disconnected

    private var credentials: ConnectorCredentials?
    private let oauth2Helper = OAuth2Helper()
    private let keychainKey = "OpenWork.GoogleDrive.Credentials"

    var oauthConfig: OAuthConfig? {
        // In production, these would come from configuration
        guard let clientId = UserDefaults.standard.string(forKey: "GoogleDrive.ClientID"),
              !clientId.isEmpty else {
            return nil
        }

        return OAuthConfig.google(
            clientId: clientId,
            scopes: [
                "https://www.googleapis.com/auth/drive.readonly",
                "https://www.googleapis.com/auth/drive.file"
            ]
        )
    }

    var tools: [any Tool] {
        [GoogleDriveTool(connector: self)]
    }

    init() {
        loadCredentials()
    }

    func authenticate() async throws {
        status = .connecting

        guard let config = oauthConfig else {
            status = .error
            throw ConnectorError.authenticationFailed("Google Drive not configured. Set Client ID in settings.")
        }

        guard let window = NSApplication.shared.keyWindow else {
            status = .error
            throw ConnectorError.authenticationFailed("No window available for authentication")
        }

        do {
            var creds = try await oauth2Helper.authenticate(config: config, presentationAnchor: window)
            creds.connectorId = id
            credentials = creds
            saveCredentials(creds)
            isAuthenticated = true
            status = .connected
        } catch {
            status = .error
            throw error
        }
    }

    func disconnect() async {
        credentials = nil
        isAuthenticated = false
        status = .disconnected
        KeychainManager.shared.delete(key: keychainKey)
    }

    func refreshIfNeeded() async throws {
        guard let creds = credentials, creds.isExpired else { return }

        guard let refreshToken = creds.refreshToken,
              let config = oauthConfig else {
            throw ConnectorError.tokenExpired
        }

        // Refresh the token
        let newCreds = try await performTokenRefresh(refreshToken: refreshToken, config: config)
        credentials = newCreds
        saveCredentials(newCreds)
    }

    private func performTokenRefresh(refreshToken: String, config: OAuthConfig) async throws -> ConnectorCredentials {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "client_id": config.clientId,
            "grant_type": "refresh_token"
        ]

        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.authenticationFailed("Token refresh failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw ConnectorError.invalidResponse
        }

        let expiresIn = json["expires_in"] as? Int
        let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }

        return ConnectorCredentials(
            connectorId: id,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    // MARK: - Keychain

    private func saveCredentials(_ creds: ConnectorCredentials) {
        if let data = try? JSONEncoder().encode(creds) {
            KeychainManager.shared.save(key: keychainKey, data: data)
        }
    }

    private func loadCredentials() {
        if let data = KeychainManager.shared.load(key: keychainKey),
           let creds = try? JSONDecoder().decode(ConnectorCredentials.self, from: data) {
            credentials = creds
            isAuthenticated = true
            status = .connected
        }
    }

    // MARK: - API Methods

    func getAccessToken() async throws -> String {
        try await refreshIfNeeded()
        guard let token = credentials?.accessToken else {
            throw ConnectorError.tokenExpired
        }
        return token
    }

    func listFiles(query: String? = nil, pageSize: Int = 20) async throws -> [DriveFile] {
        let token = try await getAccessToken()

        var urlComponents = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        var queryItems = [
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime,parents)")
        ]

        if let query = query {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "GoogleDrive", code: -1))
        }

        let result = try JSONDecoder().decode(DriveFilesResponse.self, from: data)
        return result.files
    }

    func getFileContent(fileId: String) async throws -> Data {
        let token = try await getAccessToken()

        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "GoogleDrive", code: -1))
        }

        return data
    }

    func searchFiles(query: String) async throws -> [DriveFile] {
        // Escape query for Drive API
        let escapedQuery = query.replacingOccurrences(of: "'", with: "\\'")
        let driveQuery = "name contains '\(escapedQuery)'"
        return try await listFiles(query: driveQuery)
    }
}

// MARK: - Data Models

struct DriveFile: Codable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: String?
    let parents: [String]?
}

struct DriveFilesResponse: Codable {
    let files: [DriveFile]
}

// MARK: - Google Drive Tool

struct GoogleDriveTool: Tool {
    let id = "google-drive"
    let name = "Google Drive"
    let description = "Search, list, and read files from Google Drive"
    let category: ToolCategory = .network
    let requiresApproval: Bool = false

    weak var connector: GoogleDriveConnector?

    init(connector: GoogleDriveConnector) {
        self.connector = connector
    }

    var inputSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "action": PropertySchema(
                    type: "string",
                    description: "Action to perform: list, search, read",
                    enumValues: ["list", "search", "read"]
                ),
                "query": PropertySchema(
                    type: "string",
                    description: "Search query (for search action)"
                ),
                "file_id": PropertySchema(
                    type: "string",
                    description: "File ID (for read action)"
                ),
                "page_size": PropertySchema(
                    type: "number",
                    description: "Number of results (default: 20)"
                )
            ],
            required: ["action"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let connector = connector else {
            return ToolResult.error("Google Drive connector not available", title: "Connector Error")
        }

        guard await connector.isAuthenticated else {
            return ToolResult.error("Google Drive not authenticated. Connect in Settings.", title: "Auth Required")
        }

        guard let action = args["action"] as? String else {
            return ToolResult.error("'action' parameter is required", title: "Parameter Error")
        }

        switch action.lowercased() {
        case "list":
            let pageSize = args["page_size"] as? Int ?? 20
            do {
                let files = try await connector.listFiles(pageSize: pageSize)
                let output = formatFileList(files)
                return ToolResult.success(output, title: "Drive Files", didChange: false)
            } catch {
                return ToolResult.error("Failed to list files: \(error.localizedDescription)", title: "List Error")
            }

        case "search":
            guard let query = args["query"] as? String else {
                return ToolResult.error("'query' parameter is required for search", title: "Parameter Error")
            }
            do {
                let files = try await connector.searchFiles(query: query)
                let output = formatFileList(files)
                return ToolResult.success(output, title: "Search Results", didChange: false)
            } catch {
                return ToolResult.error("Search failed: \(error.localizedDescription)", title: "Search Error")
            }

        case "read":
            guard let fileId = args["file_id"] as? String else {
                return ToolResult.error("'file_id' parameter is required for read", title: "Parameter Error")
            }
            do {
                let data = try await connector.getFileContent(fileId: fileId)
                if let content = String(data: data, encoding: .utf8) {
                    let (truncated, wasTruncated) = OutputTruncation.truncate(content)
                    var output = truncated
                    if wasTruncated {
                        output += "\n\n[Content truncated - \(data.count) total bytes]"
                    }
                    return ToolResult.success(output, title: "File Content", didChange: false)
                } else {
                    return ToolResult.success("Binary file: \(data.count) bytes", title: "File Content", didChange: false)
                }
            } catch {
                return ToolResult.error("Failed to read file: \(error.localizedDescription)", title: "Read Error")
            }

        default:
            return ToolResult.error("Unknown action: \(action)", title: "Action Error")
        }
    }

    private func formatFileList(_ files: [DriveFile]) -> String {
        if files.isEmpty {
            return "No files found."
        }

        var output = "Found \(files.count) files:\n\n"
        for file in files {
            let size = file.size.map { formatSize(Int($0) ?? 0) } ?? "N/A"
            output += "- \(file.name)\n"
            output += "  ID: \(file.id)\n"
            output += "  Type: \(file.mimeType)\n"
            output += "  Size: \(size)\n\n"
        }
        return output
    }

    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
