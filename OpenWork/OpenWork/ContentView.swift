import SwiftUI

enum AppMode: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case tasks = "Tasks"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tasks: return "checklist"
        }
    }
}

struct ContentView: View {
    @State private var selectedMode: AppMode = .tasks
    @State private var showSettings = false
    @EnvironmentObject var providerManager: ProviderManager

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedMode) {
                Section("Mode") {
                    ForEach(AppMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }

                Section("Recent") {
                    Text("No recent sessions")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        } detail: {
            switch selectedMode {
            case .chat:
                ChatView()
            case .tasks:
                TasksView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProviderManager())
        .environmentObject(VMManager())
}
