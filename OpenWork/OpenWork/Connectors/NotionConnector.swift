import Foundation
import AppKit

/// Notion connector for workspace access
@MainActor
class NotionConnector: Connector, ObservableObject {
    let id = "notion"
    let name = "Notion"
    let description = "Access and search Notion pages and databases"
    let icon = "doc.text.image"

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var status: ConnectorStatus = .disconnected

    private var credentials: ConnectorCredentials?
    private let oauth2Helper = OAuth2Helper()
    private let keychainKey = "OpenWork.Notion.Credentials"
    private let apiVersion = "2022-06-28"

    var oauthConfig: OAuthConfig? {
        guard let clientId = UserDefaults.standard.string(forKey: "Notion.ClientID"),
              let clientSecret = UserDefaults.standard.string(forKey: "Notion.ClientSecret"),
              !clientId.isEmpty, !clientSecret.isEmpty else {
            return nil
        }

        return OAuthConfig.notion(clientId: clientId, clientSecret: clientSecret)
    }

    var tools: [any Tool] {
        [NotionTool(connector: self)]
    }

    init() {
        loadCredentials()
    }

    func authenticate() async throws {
        status = .connecting

        guard let config = oauthConfig else {
            status = .error
            throw ConnectorError.authenticationFailed("Notion not configured. Set Client ID and Secret in settings.")
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

    private func getAccessToken() throws -> String {
        guard let token = credentials?.accessToken else {
            throw ConnectorError.tokenExpired
        }
        return token
    }

    func search(query: String) async throws -> [NotionPage] {
        let token = try getAccessToken()

        let url = URL(string: "https://api.notion.com/v1/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "query": query,
            "page_size": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "Notion", code: -1))
        }

        let result = try JSONDecoder().decode(NotionSearchResponse.self, from: data)
        return result.results
    }

    func getPage(pageId: String) async throws -> NotionPageContent {
        let token = try getAccessToken()

        // Get page metadata
        let pageUrl = URL(string: "https://api.notion.com/v1/pages/\(pageId)")!
        var pageRequest = URLRequest(url: pageUrl)
        pageRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        pageRequest.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")

        let (pageData, pageResponse) = try await URLSession.shared.data(for: pageRequest)

        guard let httpResponse = pageResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "Notion", code: -1))
        }

        // Get page blocks (content)
        let blocksUrl = URL(string: "https://api.notion.com/v1/blocks/\(pageId)/children")!
        var blocksRequest = URLRequest(url: blocksUrl)
        blocksRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        blocksRequest.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")

        let (blocksData, blocksResponse) = try await URLSession.shared.data(for: blocksRequest)

        guard let blocksHttpResponse = blocksResponse as? HTTPURLResponse,
              blocksHttpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "Notion", code: -1))
        }

        let page = try JSONDecoder().decode(NotionPage.self, from: pageData)
        let blocks = try JSONDecoder().decode(NotionBlocksResponse.self, from: blocksData)

        return NotionPageContent(page: page, blocks: blocks.results)
    }

    func listDatabases() async throws -> [NotionDatabase] {
        let token = try getAccessToken()

        let url = URL(string: "https://api.notion.com/v1/search")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"],
            "page_size": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectorError.networkError(NSError(domain: "Notion", code: -1))
        }

        let result = try JSONDecoder().decode(NotionDatabasesResponse.self, from: data)
        return result.results
    }
}

// MARK: - Data Models

struct NotionPage: Codable, Identifiable {
    let id: String
    let object: String
    let url: String?
    let properties: [String: NotionProperty]?

    var title: String {
        // Extract title from properties
        if let titleProp = properties?.values.first(where: { $0.type == "title" }),
           let titleArray = titleProp.title,
           let firstTitle = titleArray.first {
            return firstTitle.plainText ?? "Untitled"
        }
        return "Untitled"
    }
}

struct NotionProperty: Codable {
    let type: String
    let title: [NotionRichText]?
}

struct NotionRichText: Codable {
    let plainText: String?

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

struct NotionBlock: Codable, Identifiable {
    let id: String
    let type: String
    let paragraph: NotionParagraph?
    let heading1: NotionHeading?
    let heading2: NotionHeading?
    let heading3: NotionHeading?
    let bulletedListItem: NotionListItem?
    let numberedListItem: NotionListItem?
    let code: NotionCode?

    enum CodingKeys: String, CodingKey {
        case id, type, paragraph
        case heading1 = "heading_1"
        case heading2 = "heading_2"
        case heading3 = "heading_3"
        case bulletedListItem = "bulleted_list_item"
        case numberedListItem = "numbered_list_item"
        case code
    }

    var textContent: String {
        switch type {
        case "paragraph":
            return paragraph?.richText?.map { $0.plainText ?? "" }.joined() ?? ""
        case "heading_1":
            return "# " + (heading1?.richText?.map { $0.plainText ?? "" }.joined() ?? "")
        case "heading_2":
            return "## " + (heading2?.richText?.map { $0.plainText ?? "" }.joined() ?? "")
        case "heading_3":
            return "### " + (heading3?.richText?.map { $0.plainText ?? "" }.joined() ?? "")
        case "bulleted_list_item":
            return "• " + (bulletedListItem?.richText?.map { $0.plainText ?? "" }.joined() ?? "")
        case "numbered_list_item":
            return "1. " + (numberedListItem?.richText?.map { $0.plainText ?? "" }.joined() ?? "")
        case "code":
            let content = code?.richText?.map { $0.plainText ?? "" }.joined() ?? ""
            let language = code?.language ?? ""
            return "```\(language)\n\(content)\n```"
        default:
            return ""
        }
    }
}

struct NotionParagraph: Codable {
    let richText: [NotionRichText]?

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionHeading: Codable {
    let richText: [NotionRichText]?

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionListItem: Codable {
    let richText: [NotionRichText]?

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }
}

struct NotionCode: Codable {
    let richText: [NotionRichText]?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
        case language
    }
}

struct NotionDatabase: Codable, Identifiable {
    let id: String
    let title: [NotionRichText]?

    var name: String {
        title?.first?.plainText ?? "Untitled Database"
    }
}

struct NotionSearchResponse: Codable {
    let results: [NotionPage]
}

struct NotionBlocksResponse: Codable {
    let results: [NotionBlock]
}

struct NotionDatabasesResponse: Codable {
    let results: [NotionDatabase]
}

struct NotionPageContent {
    let page: NotionPage
    let blocks: [NotionBlock]

    var markdown: String {
        var content = "# \(page.title)\n\n"
        for block in blocks {
            let text = block.textContent
            if !text.isEmpty {
                content += text + "\n\n"
            }
        }
        return content
    }
}

// MARK: - Notion Tool

struct NotionTool: Tool {
    let id = "notion"
    let name = "Notion"
    let description = "Search and read Notion pages and databases"
    let category: ToolCategory = .network
    let requiresApproval: Bool = false

    weak var connector: NotionConnector?

    init(connector: NotionConnector) {
        self.connector = connector
    }

    var inputSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "action": PropertySchema(
                    type: "string",
                    description: "Action to perform: search, read, databases",
                    enumValues: ["search", "read", "databases"]
                ),
                "query": PropertySchema(
                    type: "string",
                    description: "Search query (for search action)"
                ),
                "page_id": PropertySchema(
                    type: "string",
                    description: "Page ID (for read action)"
                )
            ],
            required: ["action"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let connector = connector else {
            return ToolResult.error("Notion connector not available", title: "Connector Error")
        }

        guard await connector.isAuthenticated else {
            return ToolResult.error("Notion not authenticated. Connect in Settings.", title: "Auth Required")
        }

        guard let action = args["action"] as? String else {
            return ToolResult.error("'action' parameter is required", title: "Parameter Error")
        }

        switch action.lowercased() {
        case "search":
            guard let query = args["query"] as? String else {
                return ToolResult.error("'query' parameter is required for search", title: "Parameter Error")
            }
            do {
                let pages = try await connector.search(query: query)
                let output = formatPageList(pages)
                return ToolResult.success(output, title: "Search Results", didChange: false)
            } catch {
                return ToolResult.error("Search failed: \(error.localizedDescription)", title: "Search Error")
            }

        case "read":
            guard let pageId = args["page_id"] as? String else {
                return ToolResult.error("'page_id' parameter is required for read", title: "Parameter Error")
            }
            do {
                let content = try await connector.getPage(pageId: pageId)
                let (truncated, wasTruncated) = OutputTruncation.truncate(content.markdown)
                var output = truncated
                if wasTruncated {
                    output += "\n\n[Content truncated]"
                }
                return ToolResult.success(output, title: content.page.title, didChange: false)
            } catch {
                return ToolResult.error("Failed to read page: \(error.localizedDescription)", title: "Read Error")
            }

        case "databases":
            do {
                let databases = try await connector.listDatabases()
                let output = formatDatabaseList(databases)
                return ToolResult.success(output, title: "Databases", didChange: false)
            } catch {
                return ToolResult.error("Failed to list databases: \(error.localizedDescription)", title: "List Error")
            }

        default:
            return ToolResult.error("Unknown action: \(action)", title: "Action Error")
        }
    }

    private func formatPageList(_ pages: [NotionPage]) -> String {
        if pages.isEmpty {
            return "No pages found."
        }

        var output = "Found \(pages.count) pages:\n\n"
        for page in pages {
            output += "- \(page.title)\n"
            output += "  ID: \(page.id)\n"
            if let url = page.url {
                output += "  URL: \(url)\n"
            }
            output += "\n"
        }
        return output
    }

    private func formatDatabaseList(_ databases: [NotionDatabase]) -> String {
        if databases.isEmpty {
            return "No databases found."
        }

        var output = "Found \(databases.count) databases:\n\n"
        for db in databases {
            output += "- \(db.name)\n"
            output += "  ID: \(db.id)\n\n"
        }
        return output
    }
}
