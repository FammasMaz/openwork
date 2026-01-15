import SwiftUI

/// Represents a task for the agentic system
struct AgentTask: Identifiable {
    let id = UUID()
    var description: String
    var status: TaskStatus
    var workingDirectory: URL?
    var startTime: Date?
    var endTime: Date?
    var logs: [TaskLog] = []

    enum TaskStatus: String {
        case pending = "Pending"
        case running = "Running"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }
}

/// Log entry for task execution
struct TaskLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let message: String

    enum LogType {
        case info
        case toolCall
        case toolResult
        case error
        case warning
    }
}

/// Cowork-style task interface for autonomous agent execution
struct TasksView: View {
    @State private var taskInput: String = ""
    @State private var currentTask: AgentTask?
    @State private var taskHistory: [AgentTask] = []
    @State private var selectedFolder: URL?
    @State private var showFolderPicker: Bool = false
    @State private var agentLoop: AgentLoop?
    @State private var vmErrorMessage: String?

    // Search and filter state
    @State private var searchQuery: String = ""
    @State private var selectedStatusFilter: AgentTask.TaskStatus? = nil
    @State private var showStats: Bool = false

    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var vmManager: VMManager
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var questionManager: QuestionManager
    @EnvironmentObject var permissionManager: PermissionManager

    var body: some View {
        HSplitView {
            leftPanel
            rightPanel
        }
        .navigationTitle("Tasks")
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedFolder = url
                // Register folder with PermissionManager for security-scoped access
                do {
                    try permissionManager.addFolder(url, readOnly: false)
                } catch {
                    print("[TasksView] Failed to add folder permission: \(error)")
                }
            }
        }
        .approvalOverlay(approvalManager)
        .questionOverlay(questionManager)
    }
    
    @ViewBuilder
    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            folderSelectionSection
            taskInputSection
            vmStatusSection
            taskHistorySection
            Spacer()
        }
        .padding()
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
    }
    
    @ViewBuilder
    private var rightPanel: some View {
        VStack {
            if let task = currentTask {
                TaskExecutionView(
                    task: task,
                    agentLoop: agentLoop,
                    onSendFollowUp: { message in
                        sendFollowUpMessage(message)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Active Task",
                    systemImage: "checklist",
                    description: Text("Select a folder and describe a task to get started")
                )
            }
        }
    }
    
    @ViewBuilder
    private var folderSelectionSection: some View {
        GroupBox("Working Directory") {
            HStack {
                if let folder = selectedFolder {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(folder.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Change") {
                        showFolderPicker = true
                    }
                } else {
                    Text("No folder selected")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Select Folder") {
                        showFolderPicker = true
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var taskInputSection: some View {
        GroupBox("Task Description") {
            TextEditor(text: $taskInput)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 200)

            HStack {
                Spacer()
                Button {
                    startTask()
                } label: {
                    Label("Start Task", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskInput.isEmpty || selectedFolder == nil || currentTask?.status == .running)
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var vmStatusSection: some View {
        GroupBox("VM Status") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(vmStatusColor)
                        .frame(width: 8, height: 8)
                    Text(vmManager.state.rawValue)
                    Spacer()

                    if vmManager.state == .stopped || vmManager.state == .error {
                        Button("Start VM") {
                            Task {
                                do {
                                    try await vmManager.start()
                                } catch {
                                    vmErrorMessage = error.localizedDescription
                                }
                            }
                        }
                    } else if vmManager.state == .running {
                        Button("Stop VM") {
                            Task {
                                try? await vmManager.stop()
                            }
                        }
                    }
                }

                if let error = vmManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                if vmManager.state != .running {
                    Text("VM is optional - tasks will run without code isolation")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private var taskHistorySection: some View {
        GroupBox("Recent Tasks") {
            VStack(spacing: 8) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search tasks...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // Status filter pills
                HStack(spacing: 4) {
                    FilterPill(
                        title: "All",
                        isSelected: selectedStatusFilter == nil,
                        action: { selectedStatusFilter = nil }
                    )
                    FilterPill(
                        title: "Completed",
                        isSelected: selectedStatusFilter == .completed,
                        color: .green,
                        action: { selectedStatusFilter = .completed }
                    )
                    FilterPill(
                        title: "Failed",
                        isSelected: selectedStatusFilter == .failed,
                        color: .red,
                        action: { selectedStatusFilter = .failed }
                    )
                    FilterPill(
                        title: "Running",
                        isSelected: selectedStatusFilter == .running,
                        color: .blue,
                        action: { selectedStatusFilter = .running }
                    )
                    Spacer()

                    Button {
                        showStats.toggle()
                    } label: {
                        Image(systemName: "chart.bar")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Show task statistics")
                }

                // Stats panel
                if showStats {
                    TaskStatsView()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                // Task list
                if filteredHistory.isEmpty {
                    Text(taskHistory.isEmpty ? "No tasks yet" : "No matching tasks")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    List(filteredHistory) { task in
                        HStack {
                            Image(systemName: taskStatusIcon(task.status))
                                .foregroundColor(taskStatusColor(task.status))
                            VStack(alignment: .leading) {
                                Text(task.description)
                                    .lineLimit(1)
                                if let startTime = task.startTime {
                                    Text(startTime, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Restore selected task for viewing
                            currentTask = task
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var filteredHistory: [AgentTask] {
        var results = taskHistory

        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            results = results.filter { task in
                task.description.lowercased().contains(query) ||
                task.workingDirectory?.path.lowercased().contains(query) == true
            }
        }

        // Filter by status
        if let status = selectedStatusFilter {
            results = results.filter { $0.status == status }
        }

        return results
    }

    private var vmStatusColor: Color {
        switch vmManager.state {
        case .running: return .green
        case .starting: return .yellow
        case .paused: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }
    
    /// Send a follow-up message to continue the conversation
    private func sendFollowUpMessage(_ message: String) {
        guard let loop = agentLoop else { return }
        
        // Update task status back to running
        currentTask?.status = .running
        
        // Add to session
        sessionStore.addUserMessage(message)
        
        // Continue the agent loop with the follow-up
        Task {
            do {
                try await loop.continueWith(message: message)
                
                // Get the final response
                let finalResponse = loop.messages.last(where: { $0.role == .assistant })?.content ?? "Conversation continued"
                sessionStore.addAssistantMessage(finalResponse)
                
                await MainActor.run {
                    currentTask?.status = .completed
                }
            } catch {
                await MainActor.run {
                    currentTask?.status = .failed
                    currentTask?.logs.append(TaskLog(
                        timestamp: Date(),
                        type: .error,
                        message: "Follow-up failed: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func taskStatusIcon(_ status: AgentTask.TaskStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .running: return "play.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "stop.circle"
        }
    }

    private func taskStatusColor(_ status: AgentTask.TaskStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private func startTask() {
        guard !taskInput.isEmpty, let folder = selectedFolder else { return }

        let task = AgentTask(
            description: taskInput,
            status: .running,
            workingDirectory: folder,
            startTime: Date()
        )

        currentTask = task
        let taskDescription = taskInput
        taskInput = ""

        // Start the agent loop
        Task {
            // Access the folder with security scope
            let didAccess = folder.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    folder.stopAccessingSecurityScopedResource()
                }
            }

            await MainActor.run {
                currentTask?.logs.append(TaskLog(
                    timestamp: Date(),
                    type: .info,
                    message: "Starting task: \(taskDescription)"
                ))
            }

            let loop = AgentLoop(
                providerManager: providerManager,
                toolRegistry: ToolRegistry.shared,
                vmManager: vmManager.state == .running ? vmManager : nil,
                workingDirectory: folder,
                approvalManager: approvalManager,
                permissionManager: permissionManager,
                logCallback: { (message: String, logType: AgentLogType) in
                    Task { @MainActor in
                        let taskLogType: TaskLog.LogType = {
                            switch logType {
                            case .info: return .info
                            case .toolCall: return .toolCall
                            case .toolResult: return .toolResult
                            case .error: return .error
                            case .warning: return .warning
                            }
                        }()
                        self.currentTask?.logs.append(TaskLog(
                            timestamp: Date(),
                            type: taskLogType,
                            message: message
                        ))
                    }
                }
            )
            
            // Store reference to display messages
            await MainActor.run {
                self.agentLoop = loop
            }

            do {
                // Create a session for this task
                let session = sessionStore.createSession(
                    title: taskDescription,
                    workingDirectory: folder
                )
                sessionStore.addUserMessage(taskDescription)
                
                try await loop.start(task: taskDescription)
                
                // Get the final assistant response
                let finalResponse = loop.messages.last(where: { $0.role == .assistant })?.content ?? "Task completed"
                sessionStore.addAssistantMessage(finalResponse)

                await MainActor.run {
                    currentTask?.status = .completed
                    currentTask?.endTime = Date()
                    currentTask?.logs.append(TaskLog(
                        timestamp: Date(),
                        type: .info,
                        message: "Task completed successfully"
                    ))
                    if var completedTask = currentTask {
                        completedTask.status = .completed
                        taskHistory.insert(completedTask, at: 0)
                    }
                }
                
                // Save the session
                sessionStore.completeCurrentSession(summary: finalResponse)
            } catch {
                await MainActor.run {
                    currentTask?.status = .failed
                    currentTask?.endTime = Date()
                    currentTask?.logs.append(TaskLog(
                        timestamp: Date(),
                        type: .error,
                        message: "Task failed: \(error.localizedDescription)"
                    ))
                    if var failedTask = currentTask {
                        failedTask.status = .failed
                        taskHistory.insert(failedTask, at: 0)
                    }
                }
            }
        }
    }
}

/// Shows the execution progress of a task
struct TaskExecutionView: View {
    let task: AgentTask
    var agentLoop: AgentLoop?
    var onSendFollowUp: ((String) -> Void)?
    
    @State private var followUpText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Task header
            HStack {
                VStack(alignment: .leading) {
                    Text(task.description)
                        .font(.headline)
                    if let dir = task.workingDirectory {
                        Text(dir.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                StatusBadge(status: task.status)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // Execution content - both logs and agent messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Show agent messages if available (filter out empty ones)
                        if let loop = agentLoop, !loop.messages.isEmpty {
                            ForEach(Array(loop.messages.enumerated()), id: \.offset) { index, message in
                                // Skip system messages and empty assistant messages
                                if shouldShowMessage(message) {
                                    AgentMessageView(message: message)
                                        .id(index)
                                }
                            }
                        }
                        
                        // Show execution logs
                        if task.logs.isEmpty && (agentLoop?.messages.isEmpty ?? true) {
                            Text("Waiting for execution...")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(task.logs) { log in
                                LogEntryView(log: log)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: agentLoop?.messages.count) { _, _ in
                    // Auto-scroll to latest message
                    if let count = agentLoop?.messages.count, count > 0 {
                        withAnimation {
                            proxy.scrollTo(count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Follow-up input field - show when task is completed or waiting
            if task.status == .completed || task.status == .running {
                Divider()
                
                HStack(spacing: 12) {
                    TextField("Reply to continue the conversation...", text: $followUpText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendFollowUp()
                        }
                    
                    Button {
                        sendFollowUp()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(followUpText.isEmpty ? .secondary : .accentColor)
                    .disabled(followUpText.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .padding()
    }
    
    private func sendFollowUp() {
        guard !followUpText.isEmpty else { return }
        let message = followUpText
        followUpText = ""
        onSendFollowUp?(message)
    }
    
    /// Determines if a message should be displayed in the UI
    private func shouldShowMessage(_ message: AgentMessage) -> Bool {
        // Hide system messages (they're internal)
        if message.role == .system {
            return false
        }
        
        // Hide empty assistant messages (tool-use-only responses)
        if message.role == .assistant && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        
        return true
    }
}

/// Display an agent message (user, assistant, or tool)
struct AgentMessageView: View {
    let message: AgentMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Role icon
            Image(systemName: roleIcon)
                .foregroundColor(roleColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(roleName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
    }
    
    private var roleIcon: String {
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "brain"
        case .system: return "gear"
        case .tool: return "wrench.and.screwdriver"
        }
    }
    
    private var roleColor: Color {
        switch message.role {
        case .user: return .blue
        case .assistant: return .green
        case .system: return .gray
        case .tool: return .purple
        }
    }
    
    private var roleName: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.1)
        case .assistant: return Color.green.opacity(0.1)
        case .system: return Color.gray.opacity(0.1)
        case .tool: return Color.purple.opacity(0.1)
        }
    }
}

/// Status badge component
struct StatusBadge: View {
    let status: AgentTask.TaskStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

/// Log entry display
struct LogEntryView: View {
    let log: TaskLog

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: logIcon)
                .foregroundColor(logColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(.system(.body, design: .monospaced))
                Text(log.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var logIcon: String {
        switch log.type {
        case .info: return "info.circle"
        case .toolCall: return "wrench"
        case .toolResult: return "checkmark.circle"
        case .error: return "xmark.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }

    private var logColor: Color {
        switch log.type {
        case .info: return .blue
        case .toolCall: return .purple
        case .toolResult: return .green
        case .error: return .red
        case .warning: return .orange
        }
    }
}

/// Filter pill button for status filtering
struct FilterPill: View {
    let title: String
    let isSelected: Bool
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? color.opacity(0.2) : Color.clear)
                .foregroundColor(isSelected ? color : .secondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Task statistics view showing completion rates and averages
struct TaskStatsView: View {
    @State private var stats: TaskStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stats = stats {
                HStack(spacing: 16) {
                    StatItem(label: "Total", value: "\(stats.total)", color: .primary)
                    StatItem(label: "Completed", value: "\(stats.completed)", color: .green)
                    StatItem(label: "Failed", value: "\(stats.failed)", color: .red)
                    StatItem(label: "Avg Time", value: stats.formattedAverageDuration, color: .blue)

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("Success Rate")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", stats.successRate * 100))
                            .font(.headline)
                            .foregroundColor(stats.successRate > 0.8 ? .green : stats.successRate > 0.5 ? .orange : .red)
                    }
                }
            } else {
                ProgressView()
                    .frame(height: 40)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            stats = TaskPersistence.shared.getTaskStats()
        }
    }
}

/// Individual stat item display
struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

#Preview {
    TasksView()
        .environmentObject(ProviderManager())
        .environmentObject(VMManager())
        .environmentObject(SessionStore())
        .environmentObject(ApprovalManager())
        .environmentObject(QuestionManager())
        .environmentObject(PermissionManager())
}
