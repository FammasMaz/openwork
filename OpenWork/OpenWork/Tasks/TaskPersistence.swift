import Foundation
import Combine

/// Persistence layer for task queue with JSON file storage and debounced writes
class TaskPersistence {
    static let shared = TaskPersistence()

    private let maxHistoryItems = 500
    private let debounceInterval: TimeInterval = 0.5 // 500ms debounce

    // File URLs
    private var queueURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let openworkDir = appSupport.appendingPathComponent("OpenWork", isDirectory: true)
        try? FileManager.default.createDirectory(at: openworkDir, withIntermediateDirectories: true)
        return openworkDir.appendingPathComponent("task-queue.json")
    }

    private var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let openworkDir = appSupport.appendingPathComponent("OpenWork", isDirectory: true)
        try? FileManager.default.createDirectory(at: openworkDir, withIntermediateDirectories: true)
        return openworkDir.appendingPathComponent("task-history.json")
    }

    // Debounce support
    private var saveQueueSubject = PassthroughSubject<[QueuedTask], Never>()
    private var saveHistorySubject = PassthroughSubject<[QueuedTask], Never>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDebouncedSaving()
        migrateFromUserDefaultsIfNeeded()
    }

    private func setupDebouncedSaving() {
        saveQueueSubject
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.global(qos: .background))
            .sink { [weak self] tasks in
                self?.performSaveQueue(tasks)
            }
            .store(in: &cancellables)

        saveHistorySubject
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.global(qos: .background))
            .sink { [weak self] tasks in
                self?.performSaveHistory(tasks)
            }
            .store(in: &cancellables)
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "OpenWork.TaskPersistence.Migrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Migrate queue
        if let queueData = UserDefaults.standard.data(forKey: "OpenWork.TaskQueue"),
           let tasks = try? JSONDecoder().decode([QueuedTask].self, from: queueData) {
            performSaveQueue(tasks)
            UserDefaults.standard.removeObject(forKey: "OpenWork.TaskQueue")
        }

        // Migrate history
        if let historyData = UserDefaults.standard.data(forKey: "OpenWork.TaskHistory"),
           let tasks = try? JSONDecoder().decode([QueuedTask].self, from: historyData) {
            performSaveHistory(tasks)
            UserDefaults.standard.removeObject(forKey: "OpenWork.TaskHistory")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Queue Persistence

    func saveQueue(_ tasks: [QueuedTask]) {
        saveQueueSubject.send(tasks)
    }

    private func performSaveQueue(_ tasks: [QueuedTask]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: queueURL, options: .atomic)
        } catch {
            print("[TaskPersistence] Failed to save queue: \(error)")
        }
    }

    func loadQueue() -> [QueuedTask] {
        do {
            let data = try Data(contentsOf: queueURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([QueuedTask].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - History Persistence

    func saveHistory(_ tasks: [QueuedTask]) {
        let trimmed = Array(tasks.prefix(maxHistoryItems))
        saveHistorySubject.send(trimmed)
    }

    private func performSaveHistory(_ tasks: [QueuedTask]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tasks)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            print("[TaskPersistence] Failed to save history: \(error)")
        }
    }

    func loadHistory() -> [QueuedTask] {
        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([QueuedTask].self, from: data)
        } catch {
            return []
        }
    }

    func appendToHistory(_ task: QueuedTask) {
        var history = loadHistory()
        history.insert(task, at: 0)
        saveHistory(history)
    }

    // MARK: - Search and Filter

    func searchHistory(query: String, status: QueuedTaskStatus? = nil, dateRange: ClosedRange<Date>? = nil) -> [QueuedTask] {
        var results = loadHistory()

        // Filter by query (search in description)
        if !query.isEmpty {
            let lowercasedQuery = query.lowercased()
            results = results.filter { task in
                task.description.lowercased().contains(lowercasedQuery) ||
                task.workingDirectory.path.lowercased().contains(lowercasedQuery)
            }
        }

        // Filter by status
        if let status = status {
            results = results.filter { $0.status == status }
        }

        // Filter by date range
        if let dateRange = dateRange {
            results = results.filter { task in
                dateRange.contains(task.createdAt)
            }
        }

        return results
    }

    func getTaskStats() -> TaskStats {
        let history = loadHistory()

        let completed = history.filter { $0.status == .completed }.count
        let failed = history.filter { $0.status == .failed }.count
        let running = history.filter { $0.status == .running }.count
        let pending = history.filter { $0.status == .queued }.count

        let totalDuration: TimeInterval = history.compactMap { task -> TimeInterval? in
            guard let start = task.startTime, let end = task.endTime else { return nil }
            return end.timeIntervalSince(start)
        }.reduce(0, +)

        let avgDuration = completed > 0 ? totalDuration / Double(completed) : 0

        return TaskStats(
            total: history.count,
            completed: completed,
            failed: failed,
            running: running,
            pending: pending,
            averageDuration: avgDuration
        )
    }

    // MARK: - Cleanup

    func clearQueue() {
        try? FileManager.default.removeItem(at: queueURL)
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: historyURL)
    }

    // Force immediate save (e.g., before app termination)
    func flushImmediately() {
        let queue = loadQueue()
        performSaveQueue(queue)
        let history = loadHistory()
        performSaveHistory(history)
    }
}

// MARK: - Task Statistics

struct TaskStats {
    let total: Int
    let completed: Int
    let failed: Int
    let running: Int
    let pending: Int
    let averageDuration: TimeInterval

    var successRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(completed + failed)
    }

    var formattedAverageDuration: String {
        if averageDuration < 60 {
            return String(format: "%.1fs", averageDuration)
        } else if averageDuration < 3600 {
            return String(format: "%.1fm", averageDuration / 60)
        } else {
            return String(format: "%.1fh", averageDuration / 3600)
        }
    }
}
