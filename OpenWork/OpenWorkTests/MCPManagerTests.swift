import XCTest
@testable import OpenWork

@MainActor
final class MCPManagerTests: XCTestCase {

    var mcpManager: MCPManager!

    override func setUp() async throws {
        mcpManager = MCPManager()
    }

    override func tearDown() async throws {
        mcpManager.disconnectAll()
        // Remove all configs
        for config in mcpManager.configs {
            mcpManager.removeConfig(id: config.id)
        }
        mcpManager = nil
    }

    // MARK: - Configuration Management

    func testAddConfig() {
        let config = MCPServerConfig(
            name: "Test Server",
            command: "npx",
            arguments: ["-y", "@modelcontextprotocol/server-test"],
            isEnabled: true
        )

        mcpManager.addConfig(config)

        XCTAssertTrue(mcpManager.configs.contains { $0.id == config.id })
        XCTAssertEqual(mcpManager.connectionStates[config.id], .disconnected)
    }

    func testUpdateConfig() {
        let config = MCPServerConfig(
            name: "Original",
            command: "npx",
            arguments: [],
            isEnabled: true
        )

        mcpManager.addConfig(config)

        var updated = config
        updated.name = "Updated"
        updated.arguments = ["new-arg"]

        mcpManager.updateConfig(updated)

        let found = mcpManager.configs.first { $0.id == config.id }
        XCTAssertEqual(found?.name, "Updated")
        XCTAssertEqual(found?.arguments, ["new-arg"])
    }

    func testRemoveConfig() {
        let config = MCPServerConfig(
            name: "To Remove",
            command: "npx",
            arguments: [],
            isEnabled: true
        )

        mcpManager.addConfig(config)
        XCTAssertTrue(mcpManager.configs.contains { $0.id == config.id })

        mcpManager.removeConfig(id: config.id)

        XCTAssertFalse(mcpManager.configs.contains { $0.id == config.id })
        XCTAssertNil(mcpManager.connectionStates[config.id])
    }

    // MARK: - Enable/Disable

    func testSetEnabled() {
        let config = MCPServerConfig(
            name: "Test",
            command: "npx",
            arguments: [],
            isEnabled: true
        )

        mcpManager.addConfig(config)

        mcpManager.setEnabled(id: config.id, enabled: false)

        let found = mcpManager.configs.first { $0.id == config.id }
        XCTAssertEqual(found?.isEnabled, false)
    }

    // MARK: - Connection States

    func testInitialConnectionState() {
        let config = MCPServerConfig(
            name: "Test",
            command: "npx",
            arguments: [],
            isEnabled: true
        )

        mcpManager.addConfig(config)

        XCTAssertEqual(mcpManager.connectionStates[config.id], .disconnected)
    }

    func testConnectionStateIcons() {
        XCTAssertEqual(MCPManager.ConnectionState.disconnected.icon, "circle")
        XCTAssertEqual(MCPManager.ConnectionState.connecting.icon, "circle.dotted")
        XCTAssertEqual(MCPManager.ConnectionState.connected.icon, "circle.fill")
        XCTAssertEqual(MCPManager.ConnectionState.error.icon, "exclamationmark.circle.fill")
    }

    func testConnectionStateRawValues() {
        XCTAssertEqual(MCPManager.ConnectionState.disconnected.rawValue, "Disconnected")
        XCTAssertEqual(MCPManager.ConnectionState.connecting.rawValue, "Connecting")
        XCTAssertEqual(MCPManager.ConnectionState.connected.rawValue, "Connected")
        XCTAssertEqual(MCPManager.ConnectionState.error.rawValue, "Error")
    }

    // MARK: - Disconnect

    func testDisconnect() {
        let config = MCPServerConfig(
            name: "Test",
            command: "npx",
            arguments: [],
            isEnabled: true
        )

        mcpManager.addConfig(config)
        mcpManager.disconnect(id: config.id)

        XCTAssertEqual(mcpManager.connectionStates[config.id], .disconnected)
        XCTAssertNil(mcpManager.clients[config.id])
    }

    func testDisconnectAll() {
        let config1 = MCPServerConfig(name: "Server 1", command: "npx", arguments: [], isEnabled: true)
        let config2 = MCPServerConfig(name: "Server 2", command: "npx", arguments: [], isEnabled: true)

        mcpManager.addConfig(config1)
        mcpManager.addConfig(config2)

        mcpManager.disconnectAll()

        XCTAssertEqual(mcpManager.connectionStates[config1.id], .disconnected)
        XCTAssertEqual(mcpManager.connectionStates[config2.id], .disconnected)
    }

    // MARK: - Presets

    func testFilesystemPreset() {
        let preset = MCPPreset.filesystem
        let config = preset.config

        XCTAssertEqual(config.name, "Filesystem")
        XCTAssertEqual(config.command, "npx")
        XCTAssertTrue(config.arguments.contains("@modelcontextprotocol/server-filesystem"))
    }

    func testGitPreset() {
        let preset = MCPPreset.git
        let config = preset.config

        XCTAssertEqual(config.name, "Git")
        XCTAssertTrue(config.arguments.contains("@modelcontextprotocol/server-git"))
    }

    func testFetchPreset() {
        let preset = MCPPreset.fetch
        let config = preset.config

        XCTAssertEqual(config.name, "Fetch")
        XCTAssertTrue(config.arguments.contains("@modelcontextprotocol/server-fetch"))
    }

    func testMemoryPreset() {
        let preset = MCPPreset.memory
        let config = preset.config

        XCTAssertEqual(config.name, "Memory")
        XCTAssertTrue(config.arguments.contains("@modelcontextprotocol/server-memory"))
    }

    func testAddPreset() {
        mcpManager.addPreset(.filesystem)

        XCTAssertTrue(mcpManager.configs.contains { $0.name == "Filesystem" })
    }

    // MARK: - Available Tools

    func testAllAvailableToolsEmpty() {
        XCTAssertTrue(mcpManager.allAvailableTools.isEmpty)
    }

    // MARK: - Error Cases

    func testConnectDisabledServer() async {
        let config = MCPServerConfig(
            name: "Disabled",
            command: "npx",
            arguments: [],
            isEnabled: false
        )

        mcpManager.addConfig(config)

        do {
            try await mcpManager.connect(id: config.id)
            XCTFail("Should throw error for disabled server")
        } catch {
            XCTAssertTrue(error is MCPManagerError)
        }
    }

    func testConnectNonExistentConfig() async {
        let fakeId = UUID()

        do {
            try await mcpManager.connect(id: fakeId)
            XCTFail("Should throw error for non-existent config")
        } catch MCPManagerError.configNotFound {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - MCPManagerError Tests

final class MCPManagerErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertEqual(MCPManagerError.configNotFound.errorDescription, "MCP server configuration not found")
        XCTAssertEqual(MCPManagerError.serverDisabled.errorDescription, "MCP server is disabled")
        XCTAssertEqual(MCPManagerError.notConnected.errorDescription, "Not connected to MCP server")
        XCTAssertEqual(MCPManagerError.toolNotFound.errorDescription, "Tool not found on MCP server")
    }
}

// MARK: - MCPServerConfig Tests

final class MCPServerConfigTests: XCTestCase {

    func testConfigCreation() {
        let config = MCPServerConfig(
            name: "Test",
            command: "/usr/bin/node",
            arguments: ["server.js", "--port", "3000"],
            isEnabled: true
        )

        XCTAssertEqual(config.name, "Test")
        XCTAssertEqual(config.command, "/usr/bin/node")
        XCTAssertEqual(config.arguments.count, 3)
        XCTAssertTrue(config.isEnabled)
    }
}
