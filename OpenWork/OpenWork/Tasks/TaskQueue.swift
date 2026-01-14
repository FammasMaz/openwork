import Foundation

/// Status of a queued task
enum QueuedTaskStatus: String, Codable {
    case queued = "queued"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    case paused = "paused"
}

/// Priority level for queued tasks
enum TaskPriority: Int, Codable, Comparable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
}

/// A task in the queue
struct QueuedTask: Identifiable, Codable {
    let id: UUID
    var description: String
    var workingDirectory: URL
    var status: QueuedTaskStatus
    var priority: TaskPriority
    var createdAt: Date
    var startTime: Date?
    var endTime: Date?
    var error: String?
    var logs: [QueuedTaskLog]
    var progress: Double
    var useSubAgents: Bool
    
    init(
        id: UUID = UUID(),
        description: String,
        workingDirectory: URL,
        status: QueuedTaskStatus = .queued,
        priority: TaskPriority = .normal,
        createdAt: Date = Date(),
        useSubAgents: Bool = false
    ) {
        self.id = id
        self.description = description
        self.workingDirectory = workingDirectory
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.startTime = nil
        self.endTime = nil
        self.error = nil
        self.logs = []
        self.progress = 0
        self.useSubAgents = useSubAgents
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

/// Log entry for a queued task
struct QueuedTaskLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let message: String
    let type: QueuedTaskLogType
    
    init(message: String, type: QueuedTaskLogType = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.type = type
    }
}

/// Log types for queued tasks
enum QueuedTaskLogType: String, Codable {
    case info
    case warning
    case error
    case toolCall
    case toolResult
}
