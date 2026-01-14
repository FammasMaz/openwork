import Foundation
import SwiftUI

/// Manages session persistence and retrieval across app launches
@MainActor
class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var currentSession: Session?
    
    private let sessionsKey = "openwork.sessions"
    private let maxSessions = 50
    
    init() {
        loadSessions()
    }
    
    // MARK: - Session Management
    
    /// Create a new session for a task
    func createSession(title: String, workingDirectory: URL) -> Session {
        let session = Session(
            workingDirectory: workingDirectory,
            messages: [],
            title: title
        )
        currentSession = session
        return session
    }
    
    /// Add a message to the current session
    func addMessage(_ message: SessionMessage) {
        guard var session = currentSession else { return }
        session.messages.append(message)
        currentSession = session
    }
    
    /// Add a user message to the current session
    func addUserMessage(_ content: String) {
        let message = SessionMessage(role: "user", content: content)
        addMessage(message)
    }
    
    /// Add an assistant message to the current session
    func addAssistantMessage(_ content: String) {
        let message = SessionMessage(role: "assistant", content: content)
        addMessage(message)
    }
    
    /// Add a tool use message to the current session
    func addToolMessage(name: String, result: String) {
        let message = SessionMessage(role: "tool", content: result, toolName: name)
        addMessage(message)
    }
    
    /// Complete and save the current session
    func completeCurrentSession(summary: String? = nil) {
        guard var session = currentSession else { return }
        
        // Generate summary if not provided
        if let summary = summary {
            session.summary = summary
        } else {
            session.summary = generateSummary(for: session)
        }
        
        // Add to sessions list (at the beginning for recency)
        sessions.insert(session, at: 0)
        
        // Trim old sessions if needed
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }
        
        // Persist
        saveSessions()
        
        // Clear current
        currentSession = nil
    }
    
    /// Resume an existing session
    func resumeSession(_ session: Session) {
        currentSession = session
        
        // Remove from saved list (will be re-added on complete)
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }
    
    /// Delete a session
    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }
    
    /// Get recent sessions for display
    func recentSessions(limit: Int = 10) -> [Session] {
        return Array(sessions.prefix(limit))
    }
    
    // MARK: - Persistence
    
    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            UserDefaults.standard.set(data, forKey: sessionsKey)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else {
            return
        }
        
        do {
            sessions = try JSONDecoder().decode([Session].self, from: data)
        } catch {
            print("Failed to load sessions: \(error)")
            sessions = []
        }
    }
    
    // MARK: - Helpers
    
    private func generateSummary(for session: Session) -> String {
        // Use the first user message as summary, truncated
        if let firstUserMessage = session.messages.first(where: { $0.role == "user" }) {
            let content = firstUserMessage.content
            if content.count > 100 {
                return String(content.prefix(97)) + "..."
            }
            return content
        }
        return session.title ?? "Untitled Session"
    }
}
