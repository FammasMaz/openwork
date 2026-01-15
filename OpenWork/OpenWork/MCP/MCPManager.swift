import Foundation
import Combine

/// Manages multiple MCP server connections and integrates with ToolRegistry
@MainActor
class MCPManager: ObservableObject {
    @Published private(set) var configs: [MCPServerConfig] = []
    @Published private(set) var clients: [UUID: MCPClient] = [:]
    @Published private(set) var connectionStates: [UUID: ConnectionState] = [:]
    @Published var autoConnectOnLaunch: Bool = true

    /// Current connection errors per server
    @Published private(set) var errors: [UUID: String] = [:]

    /// Reference to tool registry for registering MCP tools
    private weak var toolRegistry: ToolRegistry?

    /// Persistence key
    private let configsKey = "openwork.mcp.configs"
    private let settingsKey = "openwork.mcp.settings"

    enum ConnectionState: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case error = "Error"

        var icon: String {
            switch self {
            case .disconnected: return "circle"
            case .connecting: return "circle.dotted"
            case .connected: return "circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }
    }

    init(toolRegistry: ToolRegistry? = nil) {
        self.toolRegistry = toolRegistry
        loadConfigs()
        loadSettings()
    }

    // MARK: - Configuration Management

    /// Adds a new MCP server configuration
    func addConfig(_ config: MCPServerConfig) {
        configs.append(config)
        connectionStates[config.id] = .disconnected
        saveConfigs()
    }

    /// Updates an existing configuration
    func updateConfig(_ config: MCPServerConfig) {
        guard let index = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[index] = config
        saveConfigs()
    }

    /// Removes a configuration (and disconnects if connected)
    func removeConfig(id: UUID) {
        disconnect(id: id)
        configs.removeAll { $0.id == id }
        connectionStates.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        saveConfigs()
    }

    /// Enables or disables a server
    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[index].isEnabled = enabled
        saveConfigs()

        if enabled && autoConnectOnLaunch {
            Task { try? await connect(id: id) }
        } else if !enabled {
            disconnect(id: id)
        }
    }

    // MARK: - Connection Management

    /// Connects to a specific MCP server
    func connect(id: UUID) async throws {
        guard let config = configs.first(where: { $0.id == id }) else {
            throw MCPManagerError.configNotFound
        }

        guard config.isEnabled else {
            throw MCPManagerError.serverDisabled
        }

        // Already connected
        if connectionStates[id] == .connected {
            return
        }

        connectionStates[id] = .connecting
        errors.removeValue(forKey: id)

        let client = MCPClient(config: config)

        do {
            try await client.connect()
            clients[id] = client
            connectionStates[id] = .connected

            // Register tools with ToolRegistry
            registerTools(from: client)

        } catch {
            connectionStates[id] = .error
            errors[id] = error.localizedDescription
            throw error
        }
    }

    /// Disconnects from a specific MCP server
    func disconnect(id: UUID) {
        if let client = clients[id] {
            // Unregister tools
            unregisterTools(from: client)

            client.disconnect()
            clients.removeValue(forKey: id)
        }
        connectionStates[id] = .disconnected
    }

    /// Connects to all enabled servers
    func connectAll() async {
        for config in configs where config.isEnabled {
            do {
                try await connect(id: config.id)
            } catch {
                print("Failed to connect to \(config.name): \(error)")
            }
        }
    }

    /// Disconnects from all servers
    func disconnectAll() {
        for config in configs {
            disconnect(id: config.id)
        }
    }

    /// Refreshes tools from a connected server
    func refreshTools(id: UUID) async throws {
        guard let client = clients[id] else {
            throw MCPManagerError.notConnected
        }

        try await client.refreshTools()
        registerTools(from: client)
    }

    // MARK: - Tool Integration

    /// Returns all available tools from all connected servers
    var allAvailableTools: [MCPToolWithServer] {
        clients.flatMap { (serverId, client) -> [MCPToolWithServer] in
            let serverName = configs.first(where: { $0.id == serverId })?.name ?? "Unknown"
            return client.availableTools.map { tool in
                MCPToolWithServer(serverId: serverId, serverName: serverName, tool: tool)
            }
        }
    }

    /// Calls a tool on a specific server
    func callTool(serverId: UUID, name: String, arguments: [String: Any]) async throws -> String {
        guard let client = clients[serverId] else {
            throw MCPManagerError.notConnected
        }
        return try await client.callTool(name: name, arguments: arguments)
    }

    /// Registers MCP tools with the ToolRegistry
    private func registerTools(from client: MCPClient) {
        guard let registry = toolRegistry else { return }

        for toolDef in client.availableTools {
            let wrappedTool = MCPToolWrapper(
                serverConfig: client.config,
                toolDefinition: toolDef,
                mcpManager: self
            )
            registry.register(wrappedTool)
        }
    }

    /// Unregisters MCP tools from the ToolRegistry
    private func unregisterTools(from client: MCPClient) {
        guard let registry = toolRegistry else { return }

        for toolDef in client.availableTools {
            let toolId = "mcp_\(client.config.name)_\(toolDef.name)"
            registry.unregister(id: toolId)
        }
    }

    // MARK: - Persistence

    private func saveConfigs() {
        do {
            let data = try JSONEncoder().encode(configs)
            UserDefaults.standard.set(data, forKey: configsKey)
        } catch {
            print("Failed to save MCP configs: \(error)")
        }
    }

    private func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: configsKey) else { return }
        do {
            configs = try JSONDecoder().decode([MCPServerConfig].self, from: data)
            for config in configs {
                connectionStates[config.id] = .disconnected
            }
        } catch {
            print("Failed to load MCP configs: \(error)")
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(autoConnectOnLaunch, forKey: settingsKey)
    }

    private func loadSettings() {
        autoConnectOnLaunch = UserDefaults.standard.bool(forKey: settingsKey)
    }

    // MARK: - Presets

    /// Adds a preset MCP server configuration
    func addPreset(_ preset: MCPPreset) {
        addConfig(preset.config)
    }
}

// MARK: - Supporting Types

/// MCP tool with server context
struct MCPToolWithServer: Identifiable {
    let serverId: UUID
    let serverName: String
    let tool: MCPToolDefinition

    var id: String { "\(serverId)_\(tool.name)" }
}

/// Wrapper to integrate MCP tools with the Tool protocol
struct MCPToolWrapper: Tool {
    let serverConfig: MCPServerConfig
    let toolDefinition: MCPToolDefinition
    let mcpManager: MCPManager

    var id: String { "mcp_\(serverConfig.name)_\(toolDefinition.name)" }
    var name: String { "\(serverConfig.name): \(toolDefinition.name)" }
    var description: String { toolDefinition.description }
    var category: ToolCategory { .mcp }
    var requiresApproval: Bool { true }

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: toolDefinition.inputSchema.properties?.mapValues { prop in
                JSONSchema.property(
                    prop.type,
                    description: prop.description ?? ""
                )
            } ?? [:],
            required: toolDefinition.inputSchema.required ?? []
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        let result = try await mcpManager.callTool(
            serverId: serverConfig.id,
            name: toolDefinition.name,
            arguments: args
        )

        return ToolResult(
            title: "\(serverConfig.name): \(toolDefinition.name)",
            output: result,
            metadata: ["server": serverConfig.name]
        )
    }
}

// MARK: - Presets

enum MCPPreset: String, CaseIterable {
    case filesystem = "Filesystem"
    case git = "Git"
    case fetch = "Fetch"
    case memory = "Memory"

    var config: MCPServerConfig {
        switch self {
        case .filesystem:
            return MCPServerConfig(
                name: "Filesystem",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-filesystem", "."],
                isEnabled: true
            )
        case .git:
            return MCPServerConfig(
                name: "Git",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-git"],
                isEnabled: true
            )
        case .fetch:
            return MCPServerConfig(
                name: "Fetch",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-fetch"],
                isEnabled: true
            )
        case .memory:
            return MCPServerConfig(
                name: "Memory",
                command: "npx",
                arguments: ["-y", "@modelcontextprotocol/server-memory"],
                isEnabled: true
            )
        }
    }
}

// MARK: - Errors

enum MCPManagerError: LocalizedError {
    case configNotFound
    case serverDisabled
    case notConnected
    case toolNotFound

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "MCP server configuration not found"
        case .serverDisabled:
            return "MCP server is disabled"
        case .notConnected:
            return "Not connected to MCP server"
        case .toolNotFound:
            return "Tool not found on MCP server"
        }
    }
}
