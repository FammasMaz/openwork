import SwiftUI

/// View for displaying sub-agent execution progress
struct SubAgentView: View {
    @ObservedObject var coordinator: SubAgentCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with overall progress
            headerView
            
            Divider()
            
            // Active subtasks
            if !coordinator.activeSubTasks.isEmpty {
                Section {
                    ForEach(coordinator.activeSubTasks) { subtask in
                        SubTaskRow(subtask: subtask)
                    }
                } header: {
                    Text("Active (\(coordinator.activeSubTasks.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Completed subtasks
            if !coordinator.completedSubTasks.isEmpty {
                Section {
                    ForEach(coordinator.completedSubTasks) { subtask in
                        SubTaskRow(subtask: subtask)
                    }
                } header: {
                    Text("Completed (\(coordinator.completedSubTasks.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sub-Agent Execution")
                    .font(.headline)
                Text("\(Int(coordinator.overallProgress * 100))% complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if coordinator.isRunning {
                Button("Cancel") {
                    coordinator.cancel()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Row view for a single sub-task
struct SubTaskRow: View {
    let subtask: SubTaskState
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack(spacing: 12) {
                statusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtask.description)
                        .font(.callout)
                        .lineLimit(isExpanded ? nil : 2)
                    
                    HStack(spacing: 8) {
                        Text(subtask.status.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundColor(statusColor)
                        
                        if subtask.status == .running {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        
                        Text(subtask.formattedDuration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Expand button if has logs
                if !subtask.logs.isEmpty {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Expanded logs
            if isExpanded && !subtask.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(subtask.logs.suffix(10)) { log in
                        HStack(alignment: .top, spacing: 8) {
                            logIcon(for: log.type)
                            Text(log.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .cornerRadius(8)
    }
    
    private var statusIcon: some View {
        Group {
            switch subtask.status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            case .running:
                Image(systemName: "circle.fill")
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
            }
        }
        .font(.title3)
    }
    
    private var statusColor: Color {
        switch subtask.status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    private var backgroundColor: Color {
        switch subtask.status {
        case .running:
            return Color.blue.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        default:
            return Color(NSColor.controlBackgroundColor)
        }
    }
    
    private func logIcon(for type: SubTaskLogType) -> some View {
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

/// Compact progress indicator for sub-agents
struct SubAgentProgressIndicator: View {
    @ObservedObject var coordinator: SubAgentCoordinator
    
    var body: some View {
        HStack(spacing: 8) {
            // Mini progress dots
            ForEach(coordinator.activeSubTasks.prefix(3)) { subtask in
                Circle()
                    .fill(subtask.status == .running ? Color.blue : Color.gray)
                    .frame(width: 8, height: 8)
            }
            
            if coordinator.activeSubTasks.count > 3 {
                Text("+\(coordinator.activeSubTasks.count - 3)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text("\(Int(coordinator.overallProgress * 100))%")
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
}

#Preview {
    SubAgentView(coordinator: SubAgentCoordinator(
        providerManager: ProviderManager(),
        toolRegistry: ToolRegistry.shared
    ))
    .frame(width: 400, height: 500)
}
