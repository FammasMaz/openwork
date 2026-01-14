import SwiftUI

@main
struct OpenWorkApp: App {
    @StateObject private var providerManager = ProviderManager()
    @StateObject private var vmManager = VMManager()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var approvalManager = ApprovalManager()
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var questionManager = QuestionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(providerManager)
                .environmentObject(vmManager)
                .environmentObject(sessionStore)
                .environmentObject(approvalManager)
                .environmentObject(permissionManager)
                .environmentObject(questionManager)
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
                .frame(minWidth: 700, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 700, height: 600)
    }
}
