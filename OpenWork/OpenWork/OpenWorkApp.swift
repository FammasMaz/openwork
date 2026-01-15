import SwiftUI

@main
struct OpenWorkApp: App {
    @StateObject private var providerManager = ProviderManager()
    @StateObject private var vmManager = VMManager()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var approvalManager = ApprovalManager()
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var questionManager = QuestionManager()
    @StateObject private var mcpManager: MCPManager

    init() {
        let toolRegistry = ToolRegistry.shared
        _mcpManager = StateObject(wrappedValue: MCPManager(toolRegistry: toolRegistry))

        // Connect SkillRegistry to ToolRegistry for tool registration
        SkillRegistry.shared.setToolRegistry(toolRegistry)

        // Activate default-enabled skills
        for skill in SkillRegistry.shared.availableSkills where skill.enabledByDefault {
            SkillRegistry.shared.activate(id: skill.id)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(providerManager)
                .environmentObject(vmManager)
                .environmentObject(sessionStore)
                .environmentObject(approvalManager)
                .environmentObject(permissionManager)
                .environmentObject(questionManager)
                .environmentObject(mcpManager)
                .onAppear {
                    // Start accessing all previously permitted folders
                    permissionManager.startAccessingAllFolders()

                    // Auto-connect to enabled MCP servers
                    if mcpManager.autoConnectOnLaunch {
                        Task {
                            await mcpManager.connectAll()
                        }
                    }
                }
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(providerManager)
                .environmentObject(mcpManager)
                .frame(minWidth: 700, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 600)
    }
}
