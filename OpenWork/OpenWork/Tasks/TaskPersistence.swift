import Foundation

/// Persistence layer for task queue
class TaskPersistence {
    private let storageKey = "OpenWork.TaskQueue"
    private let historyKey = "OpenWork.TaskHistory"
    private let maxHistoryItems = 100
    
    // MARK: - Queue Persistence
    
    func saveQueue(_ tasks: [QueuedTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    func loadQueue() -> [QueuedTask] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tasks = try? JSONDecoder().decode([QueuedTask].self, from: data) else {
            return []
        }
        return tasks
    }
    
    // MARK: - History Persistence
    
    func saveHistory(_ tasks: [QueuedTask]) {
        // Keep only recent items
        let trimmed = Array(tasks.prefix(maxHistoryItems))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
    
    func loadHistory() -> [QueuedTask] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let tasks = try? JSONDecoder().decode([QueuedTask].self, from: data) else {
            return []
        }
        return tasks
    }
    
    func appendToHistory(_ task: QueuedTask) {
        var history = loadHistory()
        history.insert(task, at: 0)
        saveHistory(history)
    }
    
    // MARK: - Cleanup
    
    func clearQueue() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
