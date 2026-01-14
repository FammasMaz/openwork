import Foundation

/// Represents a saved session with message history
struct Session: Identifiable, Codable {
    let id: UUID
    let workingDirectory: URL
    let createdAt: Date
    var endedAt: Date?
    var messages: [SessionMessage]
    var summary: String?
    var title: String?
    
    init(
        id: UUID = UUID(),
        workingDirectory: URL,
        createdAt: Date = Date(),
        endedAt: Date? = nil,
        messages: [SessionMessage] = [],
        summary: String? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.messages = messages
        self.summary = summary
        self.title = title
    }
    
    var duration: TimeInterval? {
        guard let endedAt = endedAt else { return nil }
        return endedAt.timeIntervalSince(createdAt)
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "In progress" }
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else if duration < 3600 {
            return String(format: "%.0fm", duration / 60)
        } else {
            return String(format: "%.1fh", duration / 3600)
        }
    }
    
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Use first user message as title
        if let firstUserMessage = messages.first(where: { $0.role == "user" }) {
            let truncated = String(firstUserMessage.content.prefix(50))
            return truncated + (firstUserMessage.content.count > 50 ? "..." : "")
        }
        return "Session \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// A message within a session
struct SessionMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
    let toolName: String?
    let toolResult: String?
    
    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        toolName: String? = nil,
        toolResult: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolResult = toolResult
    }
}

/// Context retrieved from past sessions
struct SessionContext {
    let session: Session
    let relevance: Double
    let matchedMessages: [SessionMessage]
    
    var summary: String {
        if let sessionSummary = session.summary {
            return sessionSummary
        }
        return matchedMessages.map { $0.content }.joined(separator: "\n")
    }
}
