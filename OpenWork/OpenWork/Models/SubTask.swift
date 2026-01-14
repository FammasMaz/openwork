import Foundation

/// Status of a sub-task
enum SubTaskStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

/// Definition of a sub-task created by task decomposition
struct SubTaskDefinition: Identifiable, Codable {
    let id: UUID
    let description: String
    let dependencies: [UUID]
    let expectedOutput: String?
    let priority: Int
    
    init(
        id: UUID = UUID(),
        description: String,
        dependencies: [UUID] = [],
        expectedOutput: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.description = description
        self.dependencies = dependencies
        self.expectedOutput = expectedOutput
        self.priority = priority
    }
}

/// Runtime state of a sub-task during execution
struct SubTaskState: Identifiable {
    let id: UUID
    let description: String
    var status: SubTaskStatus
    var startTime: Date?
    var endTime: Date?
    var result: SubTaskResult?
    var logs: [SubTaskLog]
    var progress: Double
    
    init(
        id: UUID,
        description: String,
        status: SubTaskStatus = .pending,
        startTime: Date? = nil,
        endTime: Date? = nil,
        result: SubTaskResult? = nil,
        logs: [SubTaskLog] = [],
        progress: Double = 0
    ) {
        self.id = id
        self.description = description
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.result = result
        self.logs = logs
        self.progress = progress
    }
    
    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "--" }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            return String(format: "%.1fm", duration / 60)
        } else {
            return String(format: "%.1fh", duration / 3600)
        }
    }
}

/// Result of a sub-task execution
struct SubTaskResult: Codable {
    let subtaskId: UUID
    let success: Bool
    let output: String
    let artifacts: [String]
    let errorMessage: String?
    
    init(
        subtaskId: UUID,
        success: Bool,
        output: String,
        artifacts: [String] = [],
        errorMessage: String? = nil
    ) {
        self.subtaskId = subtaskId
        self.success = success
        self.output = output
        self.artifacts = artifacts
        self.errorMessage = errorMessage
    }
}

/// Log entry for a sub-task
struct SubTaskLog: Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let type: SubTaskLogType
    
    init(message: String, type: SubTaskLogType = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.type = type
    }
}

enum SubTaskLogType {
    case info
    case warning
    case error
    case toolCall
    case toolResult
}

/// Progress update from sub-agent execution
enum SubTaskProgress {
    case started(subtaskId: UUID)
    case log(subtaskId: UUID, message: String, type: SubTaskLogType)
    case progressUpdate(subtaskId: UUID, progress: Double)
    case subtaskCompleted(SubTaskResult)
    case allCompleted
}

/// Decomposition result from TaskDecomposer
struct TaskDecomposition {
    let originalTask: String
    let subtasks: [SubTaskDefinition]
    let estimatedDuration: TimeInterval?
    let parallelizable: Bool
    
    /// Get subtasks that have no dependencies (can start immediately)
    var rootSubtasks: [SubTaskDefinition] {
        subtasks.filter { $0.dependencies.isEmpty }
    }
    
    /// Get subtasks that depend on a given subtask
    func dependents(of subtaskId: UUID) -> [SubTaskDefinition] {
        subtasks.filter { $0.dependencies.contains(subtaskId) }
    }
    
    /// Check if all dependencies of a subtask are satisfied
    func dependenciesSatisfied(for subtask: SubTaskDefinition, completedIds: Set<UUID>) -> Bool {
        subtask.dependencies.allSatisfy { completedIds.contains($0) }
    }
}
