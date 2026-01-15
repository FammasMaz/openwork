import Foundation
import SwiftUI

/// Manages session persistence and retrieval across app launches
@MainActor
class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var currentSession: Session?
    @Published var searchText: String = ""

    private let maxSessions = 100

    /// Debounce delay for persistence (milliseconds)
    private let persistDebounceMs: UInt64 = 500

    /// Pending save task for debouncing
    private var saveTask: Task<Void, Never>?

    /// File URL for JSON storage
    private var sessionsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("OpenWork", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("sessions.json")
    }

    /// Filtered sessions based on search text
    var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return sessions }

        let query = searchText.lowercased()
        return sessions.filter { session in
            if let title = session.title?.lowercased(), title.contains(query) {
                return true
            }
            if let summary = session.summary?.lowercased(), summary.contains(query) {
                return true
            }
            if session.messages.contains(where: { $0.content.lowercased().contains(query) }) {
                return true
            }
            return false
        }
    }

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

    /// Schedule a debounced save
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(persistDebounceMs))
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }

    /// Actually perform the save to disk
    private func performSave() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sessions)
            try data.write(to: sessionsFileURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    /// Immediate save (for critical operations)
    private func saveSessionsNow() {
        saveTask?.cancel()
        Task {
            await performSave()
        }
    }

    /// Legacy method for compatibility - now uses debounced save
    private func saveSessions() {
        scheduleSave()
    }

    private func loadSessions() {
        // Try loading from JSON file first
        if FileManager.default.fileExists(atPath: sessionsFileURL.path) {
            do {
                let data = try Data(contentsOf: sessionsFileURL)
                sessions = try JSONDecoder().decode([Session].self, from: data)
                return
            } catch {
                print("Failed to load sessions from file: \(error)")
            }
        }

        // Fall back to UserDefaults for migration
        let sessionsKey = "openwork.sessions"
        if let data = UserDefaults.standard.data(forKey: sessionsKey) {
            do {
                sessions = try JSONDecoder().decode([Session].self, from: data)
                // Migrate to file storage
                scheduleSave()
                // Remove from UserDefaults after migration
                UserDefaults.standard.removeObject(forKey: sessionsKey)
                return
            } catch {
                print("Failed to load sessions from UserDefaults: \(error)")
            }
        }

        sessions = []
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
