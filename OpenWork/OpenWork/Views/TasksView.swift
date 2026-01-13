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

    @EnvironmentObject var providerManager: ProviderManager
    @EnvironmentObject var vmManager: VMManager

    var body: some View {
        HSplitView {
            // Left panel: Task input and controls
            VStack(alignment: .leading, spacing: 16) {
                // Folder selection
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

                // Task input
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

                // VM Status
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

                        // Show VM error if any
                        if let error = vmManager.error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }

                        // Note about VM being optional for now
                        if vmManager.state != .running {
                            Text("VM is optional - tasks will run without code isolation")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Task history
                GroupBox("Recent Tasks") {
                    if taskHistory.isEmpty {
                        Text("No tasks yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        List(taskHistory) { task in
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
                        }
                        .listStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)

            // Right panel: Current task execution
            VStack {
                if let task = currentTask {
                    TaskExecutionView(task: task)
                } else {
                    ContentUnavailableView(
                        "No Active Task",
                        systemImage: "checklist",
                        description: Text("Select a folder and describe a task to get started")
                    )
                }
            }
        }
        .navigationTitle("Tasks")
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedFolder = url
                // TODO: Create security-scoped bookmark
            }
        }
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

        var task = AgentTask(
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

            // Add initial log
            await MainActor.run {
                currentTask?.logs.append(TaskLog(
                    timestamp: Date(),
                    type: .info,
                    message: "Starting task: \(taskDescription)"
                ))
            }

            // Create and run agent loop
            let loop = AgentLoop(
                providerManager: providerManager,
                vmManager: vmManager.state == .running ? vmManager : nil,
                workingDirectory: folder
            )

            do {
                try await loop.start(task: taskDescription)

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

            // Execution logs
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if task.logs.isEmpty {
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
        }
        .padding()
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

#Preview {
    TasksView()
        .environmentObject(ProviderManager())
        .environmentObject(VMManager())
}
