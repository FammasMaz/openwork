import Foundation

/// Manages agent memory and session persistence across restarts
@MainActor
class AgentMemory: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var currentSession: Session?
    
    private let persistence = SessionPersistence()
    private let maxSessions = 50
    
    init() {
        loadSessions()
    }
    
    // MARK: - Session Lifecycle
    
    /// Start a new session
    func startSession(workingDirectory: URL, title: String? = nil) -> Session {
        // End current session if active
        if currentSession != nil {
            endSession(withSummary: false)
        }
        
        let session = Session(
            workingDirectory: workingDirectory,
            title: title
        )
        
        currentSession = session
        return session
    }
    
    /// Append a message to the current session
    func appendMessage(role: String, content: String, toolName: String? = nil, toolResult: String? = nil) {
        guard currentSession != nil else { return }
        
        let message = SessionMessage(
            role: role,
            content: content,
            toolName: toolName,
            toolResult: toolResult
        )
        
        currentSession?.messages.append(message)
    }
    
    /// End the current session
    func endSession(withSummary: Bool = true) {
        guard var session = currentSession else { return }
        
        session.endedAt = Date()
        
        // Generate summary if requested
        if withSummary && session.summary == nil {
            session.summary = generateLocalSummary(for: session)
        }
        
        // Add to history
        sessions.insert(session, at: 0)
        
        // Trim old sessions
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }
        
        // Persist
        persistence.saveSessions(sessions)
        
        currentSession = nil
    }
    
    /// Resume a previous session
    func resumeSession(_ session: Session) -> Session {
        // End current if active
        if currentSession != nil {
            endSession(withSummary: false)
        }
        
        // Remove from history (will be re-added when ended)
        sessions.removeAll { $0.id == session.id }
        
        // Set as current
        var resumed = session
        resumed.endedAt = nil  // Mark as active again
        currentSession = resumed
        
        return resumed
    }
    
    /// Delete a session
    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        persistence.saveSessions(sessions)
    }
    
    /// Clear all sessions
    func clearAllSessions() {
        sessions.removeAll()
        persistence.clearSessions()
    }
    
    // MARK: - Context Retrieval
    
    /// Get relevant context from past sessions for a query
    func getRelevantContext(for query: String, maxResults: Int = 3) -> [SessionContext] {
        let keywords = extractKeywords(from: query)
        
        var results: [(Session, Double, [SessionMessage])] = []
        
        for session in sessions {
            var matchedMessages: [SessionMessage] = []
            var totalScore: Double = 0
            
            for message in session.messages {
                let messageScore = calculateRelevance(message.content, keywords: keywords)
                if messageScore > 0.2 {
                    matchedMessages.append(message)
                    totalScore += messageScore
                }
            }
            
            if !matchedMessages.isEmpty {
                let avgScore = totalScore / Double(matchedMessages.count)
                results.append((session, avgScore, matchedMessages))
            }
        }
        
        return results
            .sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map { SessionContext(session: $0.0, relevance: $0.1, matchedMessages: $0.2) }
    }
    
    /// Build a context string from relevant past sessions
    func buildContextString(for query: String, maxTokens: Int = 2000) -> String? {
        let contexts = getRelevantContext(for: query)
        
        guard !contexts.isEmpty else { return nil }
        
        var contextString = "## Relevant context from previous sessions:\n\n"
        var currentLength = contextString.count
        
        for context in contexts {
            let sessionContext = """
            ### Session: \(context.session.displayTitle)
            \(context.summary)
            
            """
            
            if currentLength + sessionContext.count > maxTokens * 4 {  // Rough token estimate
                break
            }
            
            contextString += sessionContext
            currentLength += sessionContext.count
        }
        
        return contextString
    }
    
    // MARK: - Helpers
    
    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
                            "have", "has", "had", "do", "does", "did", "will", "would", "could",
                            "should", "may", "might", "must", "shall", "can", "to", "of", "in",
                            "for", "on", "with", "at", "by", "from", "as", "into", "through",
                            "during", "before", "after", "above", "below", "between", "under",
                            "again", "further", "then", "once", "here", "there", "when", "where",
                            "why", "how", "all", "each", "few", "more", "most", "other", "some",
                            "such", "no", "nor", "not", "only", "own", "same", "so", "than",
                            "too", "very", "just", "and", "but", "if", "or", "because", "until",
                            "while", "this", "that", "these", "those", "what", "which", "who"])
        
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
    
    private func calculateRelevance(_ text: String, keywords: [String]) -> Double {
        let textLower = text.lowercased()
        var matchCount = 0
        
        for keyword in keywords {
            if textLower.contains(keyword) {
                matchCount += 1
            }
        }
        
        return keywords.isEmpty ? 0 : Double(matchCount) / Double(keywords.count)
    }
    
    private func generateLocalSummary(for session: Session) -> String {
        // Simple local summary - just extract key information
        var summary = ""
        
        // Get first user message as task
        if let firstUser = session.messages.first(where: { $0.role == "user" }) {
            summary += "Task: \(String(firstUser.content.prefix(100)))\n"
        }
        
        // Count tool usage
        let toolMessages = session.messages.filter { $0.toolName != nil }
        if !toolMessages.isEmpty {
            let toolCounts = Dictionary(grouping: toolMessages, by: { $0.toolName ?? "" })
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(3)
            
            let toolSummary = toolCounts.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            summary += "Tools used: \(toolSummary)\n"
        }
        
        // Get last assistant message as outcome
        if let lastAssistant = session.messages.last(where: { $0.role == "assistant" }) {
            summary += "Outcome: \(String(lastAssistant.content.prefix(100)))"
        }
        
        return summary
    }
    
    // MARK: - Persistence
    
    private func loadSessions() {
        sessions = persistence.loadSessions()
    }
}

/// Persistence layer for sessions
class SessionPersistence {
    private let storageKey = "OpenWork.Sessions"
    
    func saveSessions(_ sessions: [Session]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    func loadSessions() -> [Session] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else {
            return []
        }
        return sessions
    }
    
    func clearSessions() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
