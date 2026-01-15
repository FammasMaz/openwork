import SwiftUI

/// MCP Server configuration settings view
struct MCPSettingsView: View {
    @EnvironmentObject var mcpManager: MCPManager
    @State private var selectedServer: MCPServerConfig?
    @State private var showAddSheet: Bool = false
    @State private var connectionError: String?

    var body: some View {
        HSplitView {
            // Server list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedServer) {
                    ForEach(mcpManager.configs) { config in
                        HStack {
                            connectionStatusIcon(for: config.id)
                            Text(config.name)
                            Spacer()
                            if !config.isEnabled {
                                Text("Disabled")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(config)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Menu {
                        ForEach(MCPPreset.allCases, id: \.self) { preset in
                            Button(preset.rawValue) {
                                mcpManager.addPreset(preset)
                            }
                        }
                        Divider()
                        Button("Custom Server...") {
                            showAddSheet = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        if let server = selectedServer {
                            mcpManager.removeConfig(id: server.id)
                            selectedServer = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedServer == nil)

                    Spacer()

                    Button {
                        Task {
                            await mcpManager.connectAll()
                        }
                    } label: {
                        Image(systemName: "bolt.fill")
                    }
                    .help("Connect all enabled servers")
                }
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Server editor
            if let server = selectedServer {
                MCPServerEditorView(
                    server: binding(for: server),
                    connectionState: mcpManager.connectionStates[server.id] ?? .disconnected,
                    error: mcpManager.errors[server.id],
                    onConnect: {
                        Task {
                            do {
                                try await mcpManager.connect(id: server.id)
                            } catch {
                                connectionError = error.localizedDescription
                            }
                        }
                    },
                    onDisconnect: {
                        mcpManager.disconnect(id: server.id)
                    },
                    onToggleEnabled: { enabled in
                        mcpManager.setEnabled(id: server.id, enabled: enabled)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Server Selected",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Select a server from the list or add a new one")
                )
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet { config in
                mcpManager.addConfig(config)
                showAddSheet = false
            }
        }
    }

    private func binding(for server: MCPServerConfig) -> Binding<MCPServerConfig> {
        Binding(
            get: { mcpManager.configs.first { $0.id == server.id } ?? server },
            set: { mcpManager.updateConfig($0) }
        )
    }

    private func connectionStatusIcon(for serverId: UUID) -> some View {
        let state = mcpManager.connectionStates[serverId] ?? .disconnected

        return Image(systemName: state.icon)
            .foregroundColor(iconColor(for: state))
    }

    private func iconColor(for state: MCPManager.ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }
}

/// Editor view for a single MCP server configuration
struct MCPServerEditorView: View {
    @Binding var server: MCPServerConfig
    let connectionState: MCPManager.ConnectionState
    let error: String?
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onToggleEnabled: (Bool) -> Void

    @State private var newArgument: String = ""
    @State private var newEnvKey: String = ""
    @State private var newEnvValue: String = ""

    var body: some View {
        Form {
            Section("Configuration") {
                TextField("Name", text: $server.name)
                TextField("Command", text: $server.command)
                    .font(.system(.body, design: .monospaced))

                Toggle("Enabled", isOn: Binding(
                    get: { server.isEnabled },
                    set: { onToggleEnabled($0) }
                ))
            }

            Section("Arguments") {
                ForEach(Array(server.arguments.enumerated()), id: \.offset) { index, arg in
                    HStack {
                        Text(arg)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            server.arguments.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("New argument", text: $newArgument)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        if !newArgument.isEmpty {
                            server.arguments.append(newArgument)
                            newArgument = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newArgument.isEmpty)
                }
            }

            Section("Environment Variables") {
                if let env = server.environment {
                    ForEach(Array(env.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(env[key] ?? "")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                            Button {
                                server.environment?.removeValue(forKey: key)
                                if server.environment?.isEmpty == true {
                                    server.environment = nil
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    TextField("Key", text: $newEnvKey)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100)
                    TextField("Value", text: $newEnvValue)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        if !newEnvKey.isEmpty && !newEnvValue.isEmpty {
                            if server.environment == nil {
                                server.environment = [:]
                            }
                            server.environment?[newEnvKey] = newEnvValue
                            newEnvKey = ""
                            newEnvValue = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newEnvKey.isEmpty || newEnvValue.isEmpty)
                }
            }

            Section("Connection") {
                HStack {
                    Label(connectionState.rawValue, systemImage: connectionState.icon)
                        .foregroundColor(statusColor)

                    Spacer()

                    if connectionState == .connected {
                        Button("Disconnect") {
                            onDisconnect()
                        }
                    } else if connectionState == .connecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Connect") {
                            onConnect()
                        }
                        .disabled(!server.isEnabled)
                    }
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }
}

/// Sheet for adding a new custom MCP server
struct AddMCPServerSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var command: String = ""
    @State private var arguments: String = ""

    let onAdd: (MCPServerConfig) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add MCP Server")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Command", text: $command)
                    .font(.system(.body, design: .monospaced))
                TextField("Arguments (space-separated)", text: $arguments)
                    .font(.system(.body, design: .monospaced))
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let args = arguments
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }

                    let config = MCPServerConfig(
                        name: name,
                        command: command,
                        arguments: args
                    )
                    onAdd(config)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || command.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

/// View showing available tools from connected MCP servers
struct MCPToolsListView: View {
    @EnvironmentObject var mcpManager: MCPManager

    var body: some View {
        List {
            if mcpManager.allAvailableTools.isEmpty {
                ContentUnavailableView(
                    "No Tools Available",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Connect to MCP servers to see available tools")
                )
            } else {
                ForEach(groupedByServer, id: \.key) { serverName, tools in
                    Section(header: Text(serverName)) {
                        ForEach(tools, id: \.id) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.tool.name)
                                    .font(.headline)
                                Text(tool.tool.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var groupedByServer: [(key: String, value: [MCPToolWithServer])] {
        Dictionary(grouping: mcpManager.allAvailableTools) { $0.serverName }
            .sorted { $0.key < $1.key }
    }
}

#Preview {
    MCPSettingsView()
        .environmentObject(MCPManager())
}
