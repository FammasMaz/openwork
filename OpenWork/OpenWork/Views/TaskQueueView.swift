import SwiftUI

/// View for displaying and managing the task queue
struct TaskQueueView: View {
    @ObservedObject var taskManager: TaskManager
    
    @State private var newTaskDescription: String = ""
    @State private var selectedPriority: TaskPriority = .normal
    @State private var useSubAgents: Bool = false
    @State private var showNewTaskSheet: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if taskManager.queue.isEmpty && taskManager.activeTask == nil && taskManager.completedTasks.isEmpty {
                emptyStateView
            } else {
                taskListView
            }
        }
        .sheet(isPresented: $showNewTaskSheet) {
            newTaskSheet
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Task Queue")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 12) {
                if taskManager.isPaused {
                    Button("Resume") {
                        taskManager.resume()
                    }
                } else if taskManager.activeTask != nil || !taskManager.queue.isEmpty {
                    Button("Pause") {
                        taskManager.pause()
                    }
                }
                
                Button {
                    showNewTaskSheet = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    private var statusText: String {
        var parts: [String] = []
        if let active = taskManager.activeTask {
            parts.append("1 running")
        }
        if !taskManager.queue.isEmpty {
            parts.append("\(taskManager.queue.count) queued")
        }
        if taskManager.isPaused {
            parts.append("(paused)")
        }
        return parts.isEmpty ? "No tasks" : parts.joined(separator: ", ")
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No tasks in queue")
                .font(.headline)
            
            Text("Add a task to get started")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Add Task") {
                showNewTaskSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Task List
    
    private var taskListView: some View {
        List {
            // Active task
            if let active = taskManager.activeTask {
                Section("Running") {
                    TaskQueueRow(task: active, isActive: true) {
                        taskManager.cancel(taskId: active.id)
                    }
                }
            }
            
            // Queued tasks
            if !taskManager.queue.isEmpty {
                Section("Queued (\(taskManager.queue.count))") {
                    ForEach(taskManager.queue) { task in
                        TaskQueueRow(task: task, isActive: false) {
                            taskManager.cancel(taskId: task.id)
                        }
                    }
                    .onMove { from, to in
                        taskManager.reorder(from: from, to: to)
                    }
                }
            }
            
            // Completed tasks
            if !taskManager.completedTasks.isEmpty {
                Section {
                    ForEach(taskManager.completedTasks.prefix(10)) { task in
                        TaskQueueRow(task: task, isActive: false) {
                            if task.status == .failed {
                                taskManager.retry(task.id)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Button("Clear") {
                            taskManager.clearCompleted()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
    
    // MARK: - New Task Sheet
    
    private var newTaskSheet: some View {
        VStack(spacing: 20) {
            Text("Add New Task")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Task Description")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $newTaskDescription)
                    .font(.body)
                    .frame(minHeight: 100)
                    .border(Color.gray.opacity(0.3))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Priority", selection: $selectedPriority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Spacer()
                
                Toggle("Use Sub-Agents", isOn: $useSubAgents)
            }
            
            HStack {
                Button("Cancel") {
                    showNewTaskSheet = false
                    newTaskDescription = ""
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add Task") {
                    guard !newTaskDescription.isEmpty else { return }
                    
                    taskManager.createTask(
                        description: newTaskDescription,
                        workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                        priority: selectedPriority,
                        useSubAgents: useSubAgents
                    )
                    
                    newTaskDescription = ""
                    selectedPriority = .normal
                    useSubAgents = false
                    showNewTaskSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskDescription.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(minWidth: 450)
    }
}

/// Row view for a task in the queue
struct TaskQueueRow: View {
    let task: QueuedTask
    let isActive: Bool
    let onAction: () -> Void
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                statusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.description)
                        .lineLimit(isExpanded ? nil : 2)
                    
                    HStack(spacing: 8) {
                        Text(task.status.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                        
                        if task.status == .running {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        
                        Text(task.formattedDuration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        // Priority badge
                        if task.priority != .normal {
                            Text(task.priority.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(priorityColor.opacity(0.2))
                                .foregroundColor(priorityColor)
                                .cornerRadius(2)
                        }
                    }
                }
                
                Spacer()
                
                // Action button
                Button(action: onAction) {
                    Image(systemName: actionIcon)
                        .foregroundColor(actionColor)
                }
                .buttonStyle(.plain)
                
                // Expand button
                if !task.logs.isEmpty {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Progress bar for running tasks
            if task.status == .running && task.progress > 0 {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
            }
            
            // Expanded logs
            if isExpanded && !task.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.logs.suffix(5)) { log in
                        HStack(alignment: .top, spacing: 6) {
                            logIcon(for: log.type)
                            Text(log.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 28)
            }
            
            // Error message
            if let error = task.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: some View {
        Group {
            switch task.status {
            case .queued:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            case .running:
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.yellow)
            }
        }
        .font(.title3)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .queued: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .paused: return .yellow
        }
    }
    
    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
    
    private var actionIcon: String {
        switch task.status {
        case .queued, .running:
            return "xmark.circle"
        case .failed:
            return "arrow.clockwise"
        default:
            return "trash"
        }
    }
    
    private var actionColor: Color {
        switch task.status {
        case .failed:
            return .blue
        default:
            return .secondary
        }
    }
    
    private func logIcon(for type: QueuedTaskLogType) -> some View {
        Group {
            switch type {
            case .info:
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
            case .warning:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            case .error:
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            case .toolCall:
                Image(systemName: "hammer")
                    .foregroundColor(.blue)
            case .toolResult:
                Image(systemName: "checkmark.square")
                    .foregroundColor(.green)
            }
        }
        .font(.caption)
    }
}

#Preview {
    TaskQueueView(taskManager: TaskManager(
        providerManager: ProviderManager(),
        toolRegistry: ToolRegistry.shared
    ))
    .frame(width: 500, height: 600)
}
