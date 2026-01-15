import SwiftUI

/// Settings view for managing connectors
struct ConnectorsSettingsView: View {
    @StateObject private var connectorRegistry = ConnectorRegistry.shared
    @State private var selectedConnectorId: String?
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        HSplitView {
            // Connector list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedConnectorId) {
                    ForEach(connectorRegistry.availableConnectors, id: \.id) { connector in
                        ConnectorRowView(
                            connector: connector,
                            isConnected: connectorRegistry.isConnected(connector.id)
                        )
                        .tag(connector.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Summary
                HStack {
                    Text("\(connectorRegistry.connectedConnectors.count) connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

            // Detail view
            if let connectorId = selectedConnectorId,
               let connector = connectorRegistry.connector(forID: connectorId) {
                ConnectorDetailView(
                    connector: connector,
                    isConnecting: $isConnecting,
                    errorMessage: $errorMessage
                )
            } else {
                VStack {
                    Image(systemName: "link.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a connector to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Connectors let you integrate external services like Google Drive and Notion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Row view for a connector in the list
struct ConnectorRowView: View {
    let connector: any Connector
    let isConnected: Bool

    var body: some View {
        HStack {
            Image(systemName: connector.icon)
                .foregroundColor(isConnected ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(connector.name)
                    .fontWeight(isConnected ? .medium : .regular)
                Text(connector.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Detail view for a selected connector
struct ConnectorDetailView: View {
    let connector: any Connector
    @StateObject private var connectorRegistry = ConnectorRegistry.shared
    @Binding var isConnecting: Bool
    @Binding var errorMessage: String?

    // Configuration fields
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""

    private var isConnected: Bool {
        connectorRegistry.isConnected(connector.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: connector.icon)
                                .font(.title)
                                .foregroundColor(isConnected ? .green : .accentColor)
                            Text(connector.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        Text(connector.description)
                            .foregroundColor(.secondary)

                        // Status badge
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(connector.status.rawValue.capitalized)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }

                    Spacer()
                }

                Divider()

                // Configuration section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)

                    if connector.id == "google-drive" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client ID")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Enter Google OAuth Client ID", text: $clientId)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    clientId = UserDefaults.standard.string(forKey: "GoogleDrive.ClientID") ?? ""
                                }
                                .onChange(of: clientId) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "GoogleDrive.ClientID")
                                }

                            Text("Create a project in Google Cloud Console and enable the Drive API. Create OAuth credentials and copy the Client ID here.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if connector.id == "notion" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Client ID")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Enter Notion OAuth Client ID", text: $clientId)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    clientId = UserDefaults.standard.string(forKey: "Notion.ClientID") ?? ""
                                }
                                .onChange(of: clientId) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "Notion.ClientID")
                                }

                            Text("Client Secret")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            SecureField("Enter Notion OAuth Client Secret", text: $clientSecret)
                                .textFieldStyle(.roundedBorder)
                                .onAppear {
                                    clientSecret = UserDefaults.standard.string(forKey: "Notion.ClientSecret") ?? ""
                                }
                                .onChange(of: clientSecret) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "Notion.ClientSecret")
                                }

                            Text("Create an integration in Notion and copy the Client ID and Secret here.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                // Actions
                HStack {
                    if isConnected {
                        Button("Disconnect") {
                            Task {
                                await connectorRegistry.disconnect(id: connector.id)
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Connect") {
                            connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting || !hasRequiredConfig)
                    }

                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                // Tools section
                if !connector.tools.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Tools")
                            .font(.headline)

                        Text("When connected, these tools become available to the agent:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(connector.tools, id: \.id) { tool in
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text(tool.name)
                                        .fontWeight(.medium)
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusColor: Color {
        switch connector.status {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .authRequired: return .yellow
        case .disconnected: return .gray
        }
    }

    private var hasRequiredConfig: Bool {
        if connector.id == "google-drive" {
            return !clientId.isEmpty
        } else if connector.id == "notion" {
            return !clientId.isEmpty && !clientSecret.isEmpty
        }
        return true
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await connectorRegistry.connect(id: connector.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

#Preview {
    ConnectorsSettingsView()
        .frame(width: 700, height: 500)
}
