import SwiftUI

/// Settings/Preferences view for OpenWork
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .providers
    @EnvironmentObject var providerManager: ProviderManager

    enum SettingsTab: String, CaseIterable {
        case providers = "Providers"
        case vm = "Virtual Machine"
        case permissions = "Permissions"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .providers: return "server.rack"
            case .vm: return "desktopcomputer"
            case .permissions: return "lock.shield"
            case .advanced: return "gearshape.2"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ProviderSettingsView()
                .tabItem {
                    Label(SettingsTab.providers.rawValue, systemImage: SettingsTab.providers.icon)
                }
                .tag(SettingsTab.providers)

            VMSettingsView()
                .tabItem {
                    Label(SettingsTab.vm.rawValue, systemImage: SettingsTab.vm.icon)
                }
                .tag(SettingsTab.vm)

            PermissionSettingsView()
                .tabItem {
                    Label(SettingsTab.permissions.rawValue, systemImage: SettingsTab.permissions.icon)
                }
                .tag(SettingsTab.permissions)

            AdvancedSettingsView()
                .tabItem {
                    Label(SettingsTab.advanced.rawValue, systemImage: SettingsTab.advanced.icon)
                }
                .tag(SettingsTab.advanced)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 450)
    }
}

/// Provider configuration settings
struct ProviderSettingsView: View {
    @EnvironmentObject var providerManager: ProviderManager
    @State private var selectedProvider: LLMProviderConfig?
    @State private var showAddSheet: Bool = false
    @State private var testResult: String?
    @State private var isTesting: Bool = false

    var body: some View {
        HSplitView {
            // Provider list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedProvider) {
                    ForEach(providerManager.providers) { provider in
                        HStack {
                            Image(systemName: provider.id == providerManager.activeProviderID ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(provider.id == providerManager.activeProviderID ? .green : .secondary)
                            Text(provider.name)
                        }
                        .tag(provider)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Menu {
                        ForEach(LLMProviderConfig.Preset.allCases, id: \.self) { preset in
                            Button(preset.defaultConfig.name) {
                                providerManager.addPreset(preset)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        if let provider = selectedProvider {
                            providerManager.removeProvider(id: provider.id)
                            selectedProvider = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedProvider == nil)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Provider editor
            if let provider = selectedProvider {
                ProviderEditorView(
                    provider: binding(for: provider),
                    isActive: provider.id == providerManager.activeProviderID,
                    testResult: $testResult,
                    isTesting: $isTesting,
                    onSetActive: {
                        providerManager.setActiveProvider(id: provider.id)
                    },
                    onTest: {
                        testProvider(provider)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Provider Selected",
                    systemImage: "server.rack",
                    description: Text("Select a provider from the list or add a new one")
                )
            }
        }
    }

    private func binding(for provider: LLMProviderConfig) -> Binding<LLMProviderConfig> {
        Binding(
            get: { providerManager.providers.first { $0.id == provider.id } ?? provider },
            set: { providerManager.updateProvider($0) }
        )
    }

    private func testProvider(_ provider: LLMProviderConfig) {
        isTesting = true
        testResult = nil

        // Get the LATEST version of the provider from the manager (not the stale selection)
        guard let latestProvider = providerManager.providers.first(where: { $0.id == provider.id }) else {
            testResult = "❌ Provider not found"
            isTesting = false
            return
        }

        Task {
            let result = await providerManager.testConnection(for: latestProvider)

            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let message):
                    testResult = "✅ \(message)"
                case .failure(let error):
                    testResult = "❌ \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Editor for a single provider
struct ProviderEditorView: View {
    @Binding var provider: LLMProviderConfig
    let isActive: Bool
    @Binding var testResult: String?
    @Binding var isTesting: Bool
    let onSetActive: () -> Void
    let onTest: () -> Void

    var body: some View {
        Form {
            Section("Configuration") {
                TextField("Name", text: $provider.name)
                TextField("Base URL", text: $provider.baseURL)
                    .textContentType(.URL)
                SecureField("API Key (optional)", text: $provider.apiKey)
                TextField("Model", text: $provider.model)
                Picker("API Format", selection: $provider.apiFormat) {
                    Text("OpenAI Compatible").tag(APIFormat.openAICompatible)
                    Text("Ollama Native").tag(APIFormat.ollamaNative)
                }
            }

            Section("Status") {
                HStack {
                    if isActive {
                        Label("Active Provider", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Set as Active") {
                            onSetActive()
                        }
                    }

                    Spacer()

                    Button {
                        onTest()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTesting)
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.starts(with: "✅") ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// VM settings placeholder
struct VMSettingsView: View {
    var body: some View {
        Form {
            Section("Virtual Machine") {
                Text("VM configuration coming soon")
                    .foregroundColor(.secondary)
            }

            Section("Resources") {
                Stepper("CPU Cores: 4", value: .constant(4), in: 1...8)
                Stepper("Memory: 2 GB", value: .constant(2), in: 1...8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Permission settings placeholder
struct PermissionSettingsView: View {
    var body: some View {
        Form {
            Section("Default Permissions") {
                Toggle("Auto-approve read operations", isOn: .constant(true))
                Toggle("Auto-approve write to working directory", isOn: .constant(false))
                Toggle("Auto-approve network requests", isOn: .constant(false))
            }

            Section("Custom Rules") {
                Text("Permission rules coming soon")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Advanced settings placeholder
struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section("Agent") {
                Stepper("Max turns: 50", value: .constant(50), in: 10...200)
                Toggle("Enable doom loop detection", isOn: .constant(true))
            }

            Section("Snapshots") {
                Toggle("Auto-snapshot before write operations", isOn: .constant(true))
            }

            Section("Debug") {
                Toggle("Verbose logging", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(ProviderManager())
}
