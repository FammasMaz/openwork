import SwiftUI

/// Settings/Preferences view for OpenWork
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .providers
    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var mcpManager: MCPManager

    enum SettingsTab: String, CaseIterable {
        case providers = "Providers"
        case mcp = "MCP Servers"
        case skills = "Skills"
        case connectors = "Connectors"
        case vm = "Virtual Machine"
        case permissions = "Permissions"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .providers: return "server.rack"
            case .mcp: return "puzzlepiece.extension"
            case .skills: return "wand.and.stars"
            case .connectors: return "link.circle"
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

            MCPSettingsView()
                .tabItem {
                    Label(SettingsTab.mcp.rawValue, systemImage: SettingsTab.mcp.icon)
                }
                .tag(SettingsTab.mcp)

            SkillsSettingsView()
                .tabItem {
                    Label(SettingsTab.skills.rawValue, systemImage: SettingsTab.skills.icon)
                }
                .tag(SettingsTab.skills)

            ConnectorsSettingsView()
                .tabItem {
                    Label(SettingsTab.connectors.rawValue, systemImage: SettingsTab.connectors.icon)
                }
                .tag(SettingsTab.connectors)

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

/// VM settings with disk management
struct VMSettingsView: View {
    @State private var cpuCores: Int = 4
    @State private var memoryGB: Int = 2
    @State private var diskInfo: DiskInfo = DiskInfo()
    @State private var showResetConfirmation = false
    @State private var isResetting = false

    struct DiskInfo {
        var bundleRootfsExists = false
        var bundleRootfsSize: String = "Unknown"
        var writableRootfsExists = false
        var writableRootfsSize: String = "Unknown"
        var writableRootfsPath: String = ""
    }

    var body: some View {
        Form {
            Section("Resources") {
                Stepper("CPU Cores: \(cpuCores)", value: $cpuCores, in: 1...ProcessInfo.processInfo.processorCount)
                    .help("Number of CPU cores allocated to the VM")
                Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...16)
                    .help("Amount of RAM allocated to the VM")
            }

            Section("Disk Images") {
                VStack(alignment: .leading, spacing: 12) {
                    // Bundle rootfs (source)
                    HStack {
                        Image(systemName: "doc.zipper")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text("Source Image (in app bundle)")
                                .font(.headline)
                            Text(diskInfo.bundleRootfsExists ? "Size: \(diskInfo.bundleRootfsSize)" : "Not found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if diskInfo.bundleRootfsExists {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Divider()

                    // Writable rootfs (working copy)
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Working Copy (writable)")
                                .font(.headline)
                            if diskInfo.writableRootfsExists {
                                Text("Size: \(diskInfo.writableRootfsSize)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(diskInfo.writableRootfsPath)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Will be created on first VM start")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if diskInfo.writableRootfsExists {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "circle.dashed")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Disk Management") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reset VM Disk")
                            .font(.headline)
                        Text("Deletes the working copy and restores from original. All VM changes will be lost.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Reset")
                        }
                    }
                    .disabled(!diskInfo.writableRootfsExists || isResetting)
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Open in Finder")
                            .font(.headline)
                        Text("Show the VM disk location in Finder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reveal") {
                        revealInFinder()
                    }
                    .disabled(!diskInfo.writableRootfsExists)
                }
            }

            Section("Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The VM uses a Linux environment for secure code execution", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("Changes made inside the VM persist in the working copy", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label("Resetting restores the VM to its original clean state", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshDiskInfo()
        }
        .confirmationDialog(
            "Reset VM Disk?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetDisk()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the working copy of the VM disk. All changes made inside the VM will be lost. A fresh copy will be created on next VM start.")
        }
    }

    private func refreshDiskInfo() {
        let fileManager = FileManager.default

        // Check bundle rootfs
        if let bundlePath = Bundle.main.url(forResource: "rootfs", withExtension: "img", subdirectory: "linux") {
            diskInfo.bundleRootfsExists = fileManager.fileExists(atPath: bundlePath.path)
            if diskInfo.bundleRootfsExists {
                diskInfo.bundleRootfsSize = fileSizeString(at: bundlePath)
            }
        }

        // Check writable rootfs
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let writablePath = appSupport.appendingPathComponent("OpenWork/VM/rootfs.img")
        diskInfo.writableRootfsPath = writablePath.path
        diskInfo.writableRootfsExists = fileManager.fileExists(atPath: writablePath.path)
        if diskInfo.writableRootfsExists {
            diskInfo.writableRootfsSize = fileSizeString(at: writablePath)
        }
    }

    private func fileSizeString(at url: URL) -> String {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return formatter.string(fromByteCount: size)
            }
        } catch {}
        return "Unknown"
    }

    private func resetDisk() {
        isResetting = true

        Task {
            do {
                let fileManager = FileManager.default
                let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let vmDir = appSupport.appendingPathComponent("OpenWork/VM")

                if fileManager.fileExists(atPath: vmDir.path) {
                    try fileManager.removeItem(at: vmDir)
                }

                await MainActor.run {
                    isResetting = false
                    refreshDiskInfo()
                }
            } catch {
                await MainActor.run {
                    isResetting = false
                    print("[VMSettings] Error resetting disk: \(error)")
                }
            }
        }
    }

    private func revealInFinder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vmDir = appSupport.appendingPathComponent("OpenWork/VM")

        if FileManager.default.fileExists(atPath: vmDir.path) {
            NSWorkspace.shared.selectFile(diskInfo.writableRootfsPath, inFileViewerRootedAtPath: vmDir.path)
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appSupport.path)
        }
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
        .environmentObject(MCPManager())
}
