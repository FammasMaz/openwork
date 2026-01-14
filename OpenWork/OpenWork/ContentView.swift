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
    @State private var selectedSession: Session?
    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var sessionStore: SessionStore

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
                    if sessionStore.sessions.isEmpty {
                        Text("No recent sessions")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(sessionStore.recentSessions()) { session in
                            Button {
                                selectedSession = session
                                selectedMode = .tasks
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled")
                                        .lineLimit(1)
                                        .font(.subheadline)
                                    Text(session.summary ?? "")
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Resume") {
                                    sessionStore.resumeSession(session)
                                    selectedMode = .tasks
                                }
                                Button("Delete", role: .destructive) {
                                    sessionStore.deleteSession(session)
                                }
                            }
                        }
                    }
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
        .environmentObject(SessionStore())
}
