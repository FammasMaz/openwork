import Foundation
import SwiftUI

/// Manages the task queue and lifecycle
@MainActor
class TaskManager: ObservableObject {
    @Published var queue: [QueuedTask] = []
    @Published var activeTask: QueuedTask?
    @Published var completedTasks: [QueuedTask] = []
    @Published var maxConcurrent: Int = 1
    @Published var isPaused: Bool = false
    
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private let persistence = TaskPersistence()
    
    private let providerManager: ProviderManager
    private let toolRegistry: ToolRegistry
    private var approvalManager: ApprovalManager?
    private var permissionManager: PermissionManager?
    
    init(
        providerManager: ProviderManager,
        toolRegistry: ToolRegistry,
        approvalManager: ApprovalManager? = nil,
        permissionManager: PermissionManager? = nil
    ) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.approvalManager = approvalManager
        self.permissionManager = permissionManager
        loadPersistedState()
    }
    
    // MARK: - Dependency Injection
    
    func setApprovalManager(_ manager: ApprovalManager) {
        self.approvalManager = manager
    }
    
    func setPermissionManager(_ manager: PermissionManager) {
        self.permissionManager = manager
    }
    
    // MARK: - Queue Operations
    
    /// Add a task to the queue
    func enqueue(_ task: QueuedTask) {
        var newTask = task
        newTask.status = .queued
        
        // Insert based on priority
        let insertIndex = queue.firstIndex { $0.priority < task.priority } ?? queue.endIndex
        queue.insert(newTask, at: insertIndex)
        
        persistence.saveQueue(queue)
        processQueue()
    }
    
    /// Create and enqueue a new task
    func createTask(
        description: String,
        workingDirectory: URL,
        priority: TaskPriority = .normal,
        useSubAgents: Bool = false
    ) {
        let task = QueuedTask(
            description: description,
            workingDirectory: workingDirectory,
            priority: priority,
            useSubAgents: useSubAgents
        )
        enqueue(task)
    }
    
    /// Cancel a specific task
    func cancel(taskId: UUID) {
        // Cancel if running
        if let runningTask = runningTasks[taskId] {
            runningTask.cancel()
            runningTasks.removeValue(forKey: taskId)
        }
        
        // Update status if active
        if activeTask?.id == taskId {
            var cancelled = activeTask!
            cancelled.status = .cancelled
            cancelled.endTime = Date()
            completedTasks.insert(cancelled, at: 0)
            persistence.appendToHistory(cancelled)
            activeTask = nil
        }
        
        // Remove from queue if pending
        queue.removeAll { $0.id == taskId }
        persistence.saveQueue(queue)
        
        processQueue()
    }
    
    /// Cancel all tasks
    func cancelAll() {
        // Cancel running tasks
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
        
        // Cancel active task
        if var active = activeTask {
            active.status = .cancelled
            active.endTime = Date()
            completedTasks.insert(active, at: 0)
            persistence.appendToHistory(active)
            activeTask = nil
        }
        
        // Cancel queued tasks
        for var task in queue {
            task.status = .cancelled
            completedTasks.insert(task, at: 0)
        }
        queue.removeAll()
        
        persistence.saveQueue(queue)
    }
    
    /// Pause queue processing
    func pause() {
        isPaused = true
    }
    
    /// Resume queue processing
    func resume() {
        isPaused = false
        processQueue()
    }
    
    /// Reorder tasks in queue
    func reorder(from: IndexSet, to: Int) {
        queue.move(fromOffsets: from, toOffset: to)
        persistence.saveQueue(queue)
    }
    
    /// Update task priority
    func setPriority(_ taskId: UUID, priority: TaskPriority) {
        guard let index = queue.firstIndex(where: { $0.id == taskId }) else { return }
        queue[index].priority = priority
        
        // Re-sort by priority
        queue.sort { $0.priority > $1.priority }
        persistence.saveQueue(queue)
    }
    
    /// Clear completed tasks
    func clearCompleted() {
        completedTasks.removeAll()
    }
    
    /// Retry a failed task
    func retry(_ taskId: UUID) {
        guard let index = completedTasks.firstIndex(where: { $0.id == taskId }),
              completedTasks[index].status == .failed else { return }
        
        var task = completedTasks.remove(at: index)
        task.status = .queued
        task.startTime = nil
        task.endTime = nil
        task.error = nil
        task.logs = []
        task.progress = 0
        
        enqueue(task)
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        guard !isPaused else { return }
        guard activeTask == nil else { return }
        guard let next = queue.first else { return }
        
        queue.removeFirst()
        activeTask = next
        activeTask?.status = .running
        activeTask?.startTime = Date()
        
        persistence.saveQueue(queue)
        
        let taskRunner = Task {
            await runTask(next)
        }
        runningTasks[next.id] = taskRunner
    }
    
    private func runTask(_ task: QueuedTask) async {
        let logHandler: (String, AgentLogType) -> Void = { [weak self] message, type in
            Task { @MainActor in
                guard var active = self?.activeTask, active.id == task.id else { return }
                
                let logType: QueuedTaskLogType
                switch type {
                case .info: logType = .info
                case .warning: logType = .warning
                case .error: logType = .error
                case .toolCall: logType = .toolCall
                case .toolResult: logType = .toolResult
                }
                
                active.logs.append(QueuedTaskLog(message: message, type: logType))
                self?.activeTask = active
            }
        }
        
        if task.useSubAgents {
            // Use sub-agent coordinator for complex tasks
            await runWithSubAgents(task: task, logHandler: logHandler)
        } else {
            // Use regular agent loop
            await runWithAgentLoop(task: task, logHandler: logHandler)
        }
    }
    
    private func runWithAgentLoop(
        task: QueuedTask,
        logHandler: @escaping (String, AgentLogType) -> Void
    ) async {
        let agentLoop = AgentLoop(
            providerManager: providerManager,
            toolRegistry: toolRegistry,
            vmManager: nil,
            workingDirectory: task.workingDirectory,
            approvalManager: approvalManager,
            permissionManager: permissionManager,
            logCallback: logHandler
        )
        
        do {
            try await agentLoop.start(task: task.description)
            await completeTask(task.id, success: true)
        } catch {
            await completeTask(task.id, success: false, error: error.localizedDescription)
        }
    }
    
    private func runWithSubAgents(
        task: QueuedTask,
        logHandler: @escaping (String, AgentLogType) -> Void
    ) async {
        let coordinator = SubAgentCoordinator(
            providerManager: providerManager,
            toolRegistry: toolRegistry
        )
        
        do {
            _ = try await coordinator.execute(
                task: task.description,
                workingDirectory: task.workingDirectory,
                approvalManager: approvalManager,
                permissionManager: permissionManager
            ) { progress in
                switch progress {
                case .log(_, let message, let type):
                    let agentType: AgentLogType
                    switch type {
                    case .info: agentType = .info
                    case .warning: agentType = .warning
                    case .error: agentType = .error
                    case .toolCall: agentType = .toolCall
                    case .toolResult: agentType = .toolResult
                    }
                    logHandler(message, agentType)
                case .progressUpdate(_, let progress):
                    Task { @MainActor in
                        self.activeTask?.progress = progress
                    }
                default:
                    break
                }
            }
            await completeTask(task.id, success: true)
        } catch {
            await completeTask(task.id, success: false, error: error.localizedDescription)
        }
    }
    
    private func completeTask(_ taskId: UUID, success: Bool, error: String? = nil) async {
        guard var completed = activeTask, completed.id == taskId else { return }
        
        completed.status = success ? .completed : .failed
        completed.endTime = Date()
        completed.error = error
        completed.progress = success ? 1.0 : completed.progress
        
        completedTasks.insert(completed, at: 0)
        persistence.appendToHistory(completed)
        
        activeTask = nil
        runningTasks.removeValue(forKey: taskId)
        
        // Process next task
        processQueue()
    }
    
    // MARK: - Persistence
    
    private func loadPersistedState() {
        queue = persistence.loadQueue()
        completedTasks = persistence.loadHistory()
        
        // Reset any tasks that were running when app closed
        for i in queue.indices {
            if queue[i].status == .running {
                queue[i].status = .queued
            }
        }
    }
}
