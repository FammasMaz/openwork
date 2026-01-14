import Foundation

/// MCP Client - Connects to external MCP servers
@MainActor
class MCPClient: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var serverInfo: MCPServerInfo?
    @Published var availableTools: [MCPToolDefinition] = []
    @Published var availableResources: [MCPResource] = []
    @Published var availablePrompts: [MCPPrompt] = []
    
    private var transport: MCPTransport?
    private var requestId = 0
    private let clientInfo = MCPClientInfo(name: "OpenWork", version: "1.0.0")
    
    let config: MCPServerConfig
    
    init(config: MCPServerConfig) {
        self.config = config
    }
    
    // MARK: - Connection Lifecycle
    
    func connect() async throws {
        // Create transport based on config
        transport = try StdioTransport(
            command: config.command,
            arguments: config.arguments,
            environment: config.environment
        )
        
        // Initialize connection
        let initResult = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "roots": ["listChanged": true]
                ],
                "clientInfo": [
                    "name": clientInfo.name,
                    "version": clientInfo.version
                ]
            ]
        )
        
        // Parse server info
        if let result = initResult.result?.value as? [String: Any],
           let serverInfoDict = result["serverInfo"] as? [String: Any],
           let name = serverInfoDict["name"] as? String,
           let version = serverInfoDict["version"] as? String {
            serverInfo = MCPServerInfo(name: name, version: version)
        }
        
        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: [:])
        
        // Fetch available capabilities
        try await refreshTools()
        try await refreshResources()
        try await refreshPrompts()
        
        isConnected = true
    }
    
    func disconnect() {
        transport?.close()
        transport = nil
        isConnected = false
        serverInfo = nil
        availableTools = []
        availableResources = []
        availablePrompts = []
    }
    
    // MARK: - Tools
    
    func refreshTools() async throws {
        let response = try await sendRequest(method: "tools/list", params: [:])
        
        if let result = response.result?.value as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            availableTools = tools.compactMap { parseToolDefinition($0) }
        }
    }
    
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let response = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments
            ]
        )
        
        // Check for error
        if let error = response.error {
            throw MCPClientError.serverError(error.message)
        }
        
        // Parse result
        if let result = response.result?.value as? [String: Any],
           let content = result["content"] as? [[String: Any]] {
            // Concatenate all text content
            let textParts = content.compactMap { item -> String? in
                guard item["type"] as? String == "text" else { return nil }
                return item["text"] as? String
            }
            return textParts.joined(separator: "\n")
        }
        
        return ""
    }
    
    // MARK: - Resources
    
    func refreshResources() async throws {
        let response = try await sendRequest(method: "resources/list", params: [:])
        
        if let result = response.result?.value as? [String: Any],
           let resources = result["resources"] as? [[String: Any]] {
            availableResources = resources.compactMap { parseResource($0) }
        }
    }
    
    func readResource(uri: String) async throws -> String {
        let response = try await sendRequest(
            method: "resources/read",
            params: ["uri": uri]
        )
        
        if let result = response.result?.value as? [String: Any],
           let contents = result["contents"] as? [[String: Any]],
           let first = contents.first,
           let text = first["text"] as? String {
            return text
        }
        
        return ""
    }
    
    // MARK: - Prompts
    
    func refreshPrompts() async throws {
        let response = try await sendRequest(method: "prompts/list", params: [:])
        
        if let result = response.result?.value as? [String: Any],
           let prompts = result["prompts"] as? [[String: Any]] {
            availablePrompts = prompts.compactMap { parsePrompt($0) }
        }
    }
    
    func getPrompt(name: String, arguments: [String: String] = [:]) async throws -> String {
        let response = try await sendRequest(
            method: "prompts/get",
            params: [
                "name": name,
                "arguments": arguments
            ]
        )
        
        if let result = response.result?.value as? [String: Any],
           let messages = result["messages"] as? [[String: Any]] {
            // Concatenate message contents
            let textParts = messages.compactMap { msg -> String? in
                guard let content = msg["content"] as? [String: Any],
                      content["type"] as? String == "text" else { return nil }
                return content["text"] as? String
            }
            return textParts.joined(separator: "\n")
        }
        
        return ""
    }
    
    // MARK: - Communication
    
    private func sendRequest(method: String, params: [String: Any]) async throws -> MCPMessage {
        guard let transport = transport else {
            throw MCPClientError.notConnected
        }
        
        requestId += 1
        let request = MCPMessage.request(id: requestId, method: method, params: params)
        
        try await transport.send(request)
        return try await transport.receive()
    }
    
    private func sendNotification(method: String, params: [String: Any]) async throws {
        guard let transport = transport else {
            throw MCPClientError.notConnected
        }
        
        let notification = MCPMessage(
            method: method,
            params: params.mapValues { AnyCodable($0) }
        )
        
        try await transport.send(notification)
    }
    
    // MARK: - Parsing Helpers
    
    private func parseToolDefinition(_ dict: [String: Any]) -> MCPToolDefinition? {
        guard let name = dict["name"] as? String,
              let description = dict["description"] as? String else {
            return nil
        }
        
        var inputSchema = MCPInputSchema(type: "object", properties: nil, required: nil)
        
        if let schemaDict = dict["inputSchema"] as? [String: Any] {
            var properties: [String: MCPPropertySchema]?
            
            if let propsDict = schemaDict["properties"] as? [String: [String: Any]] {
                properties = propsDict.compactMapValues { propDict in
                    guard let type = propDict["type"] as? String else { return nil }
                    return MCPPropertySchema(
                        type: type,
                        description: propDict["description"] as? String,
                        enum: propDict["enum"] as? [String]
                    )
                }
            }
            
            inputSchema = MCPInputSchema(
                type: schemaDict["type"] as? String ?? "object",
                properties: properties,
                required: schemaDict["required"] as? [String]
            )
        }
        
        return MCPToolDefinition(name: name, description: description, inputSchema: inputSchema)
    }
    
    private func parseResource(_ dict: [String: Any]) -> MCPResource? {
        guard let uri = dict["uri"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        
        return MCPResource(
            uri: uri,
            name: name,
            description: dict["description"] as? String,
            mimeType: dict["mimeType"] as? String
        )
    }
    
    private func parsePrompt(_ dict: [String: Any]) -> MCPPrompt? {
        guard let name = dict["name"] as? String else { return nil }
        
        var arguments: [MCPPromptArgument]?
        if let argsArray = dict["arguments"] as? [[String: Any]] {
            arguments = argsArray.compactMap { argDict in
                guard let name = argDict["name"] as? String else { return nil }
                return MCPPromptArgument(
                    name: name,
                    description: argDict["description"] as? String,
                    required: argDict["required"] as? Bool
                )
            }
        }
        
        return MCPPrompt(
            name: name,
            description: dict["description"] as? String,
            arguments: arguments
        )
    }
}

// MARK: - Configuration

struct MCPServerConfig: Identifiable, Codable {
    let id: UUID
    var name: String
    var command: String
    var arguments: [String]
    var environment: [String: String]?
    var isEnabled: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.isEnabled = isEnabled
    }
}

// MARK: - Errors

enum MCPClientError: LocalizedError {
    case notConnected
    case serverError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
