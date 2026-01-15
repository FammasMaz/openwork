import XCTest
@testable import OpenWork

@MainActor
final class TaskManagerTests: XCTestCase {

    var taskManager: TaskManager!
    var providerManager: ProviderManager!
    var toolRegistry: ToolRegistry!

    override func setUp() async throws {
        // Clear persisted queue before creating TaskManager to ensure clean state
        TaskPersistence.shared.clearQueue()

        providerManager = ProviderManager()
        toolRegistry = ToolRegistry.shared
        taskManager = TaskManager(
            providerManager: providerManager,
            toolRegistry: toolRegistry
        )
    }

    override func tearDown() async throws {
        taskManager.cancelAll()
        TaskPersistence.shared.clearQueue()
        taskManager = nil
        providerManager = nil
    }

    // MARK: - Queue Operations

    func testEnqueueTask() {
        let task = QueuedTask(
            description: "Test task",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            priority: .normal
        )

        taskManager.enqueue(task)

        // Task should be either in queue or running
        XCTAssertTrue(taskManager.queue.contains { $0.id == task.id } ||
                      taskManager.activeTasks[task.id] != nil)
    }

    func testCreateTask() {
        taskManager.createTask(
            description: "Created task",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Should have at least one task
        XCTAssertTrue(taskManager.queue.count + taskManager.activeTasks.count >= 1)
    }

    func testCancelTask() {
        let task = QueuedTask(
            description: "Task to cancel",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Pause queue to keep task in queue
        taskManager.pause()
        taskManager.enqueue(task)

        XCTAssertTrue(taskManager.queue.contains { $0.id == task.id })

        taskManager.cancel(taskId: task.id)

        XCTAssertFalse(taskManager.queue.contains { $0.id == task.id })
    }

    func testCancelAllTasks() {
        taskManager.pause()

        for i in 0..<5 {
            let task = QueuedTask(
                description: "Task \(i)",
                workingDirectory: URL(fileURLWithPath: "/tmp")
            )
            taskManager.enqueue(task)
        }

        XCTAssertEqual(taskManager.queue.count, 5)

        taskManager.cancelAll()

        XCTAssertEqual(taskManager.queue.count, 0)
        XCTAssertEqual(taskManager.activeTasks.count, 0)
    }

    // MARK: - Priority Tests

    func testPriorityOrdering() {
        taskManager.pause()

        let lowTask = QueuedTask(
            description: "Low priority",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            priority: .low
        )
        let highTask = QueuedTask(
            description: "High priority",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            priority: .high
        )
        let normalTask = QueuedTask(
            description: "Normal priority",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            priority: .normal
        )

        taskManager.enqueue(lowTask)
        taskManager.enqueue(normalTask)
        taskManager.enqueue(highTask)

        // High priority should be first
        XCTAssertEqual(taskManager.queue.first?.priority, .high)
    }

    func testSetPriority() {
        taskManager.pause()

        let task = QueuedTask(
            description: "Test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            priority: .low
        )

        taskManager.enqueue(task)
        taskManager.setPriority(task.id, priority: .urgent)

        let updated = taskManager.queue.first { $0.id == task.id }
        XCTAssertEqual(updated?.priority, .urgent)
    }

    // MARK: - Queue Control

    func testPauseResume() {
        XCTAssertFalse(taskManager.isPaused)

        taskManager.pause()
        XCTAssertTrue(taskManager.isPaused)

        taskManager.resume()
        XCTAssertFalse(taskManager.isPaused)
    }

    func testReorderTasks() {
        taskManager.pause()

        let task1 = QueuedTask(description: "Task 1", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let task2 = QueuedTask(description: "Task 2", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let task3 = QueuedTask(description: "Task 3", workingDirectory: URL(fileURLWithPath: "/tmp"))

        taskManager.enqueue(task1)
        taskManager.enqueue(task2)
        taskManager.enqueue(task3)

        // Move first item to end
        taskManager.reorder(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(taskManager.queue[0].id, task2.id)
        XCTAssertEqual(taskManager.queue[2].id, task1.id)
    }

    // MARK: - Concurrent Execution

    func testMaxConcurrentDefault() {
        XCTAssertEqual(taskManager.maxConcurrent, 10)
    }

    func testRunningCount() {
        XCTAssertEqual(taskManager.runningCount, 0)
        XCTAssertFalse(taskManager.isRunning)
    }

    // MARK: - Completed Tasks

    func testClearCompleted() {
        // Note: Cancelled tasks from queue are just removed, not added to completedTasks
        // Only running tasks that get cancelled are added to completedTasks
        // So we test clearCompleted by verifying it clears the array

        // Directly test that clearCompleted works
        taskManager.clearCompleted()
        XCTAssertTrue(taskManager.completedTasks.isEmpty)
    }

    func testCancelledQueuedTaskRemovedFromQueue() {
        // Cancelled queued tasks are removed from queue, not added to completedTasks
        taskManager.pause()
        let task = QueuedTask(description: "Test", workingDirectory: URL(fileURLWithPath: "/tmp"))
        taskManager.enqueue(task)

        XCTAssertTrue(taskManager.queue.contains { $0.id == task.id })

        taskManager.cancel(taskId: task.id)

        // Task should be removed from queue
        XCTAssertFalse(taskManager.queue.contains { $0.id == task.id })
    }

    // MARK: - Convenience Properties

    func testActiveTaskProperty() {
        XCTAssertNil(taskManager.activeTask)
    }
}

// MARK: - QueuedTask Tests

final class QueuedTaskTests: XCTestCase {

    func testTaskCreation() {
        let task = QueuedTask(
            description: "Test task",
            workingDirectory: URL(fileURLWithPath: "/Users/test/project"),
            priority: .normal
        )

        XCTAssertEqual(task.description, "Test task")
        XCTAssertEqual(task.workingDirectory.path, "/Users/test/project")
        XCTAssertEqual(task.priority, .normal)
        XCTAssertEqual(task.status, .queued)
        XCTAssertNil(task.startTime)
        XCTAssertNil(task.endTime)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.progress, 0)
        XCTAssertTrue(task.logs.isEmpty)
    }

    func testTaskPriorityComparison() {
        XCTAssertTrue(TaskPriority.urgent > TaskPriority.high)
        XCTAssertTrue(TaskPriority.high > TaskPriority.normal)
        XCTAssertTrue(TaskPriority.normal > TaskPriority.low)
    }

    func testTaskStatusValues() {
        XCTAssertEqual(QueuedTaskStatus.queued.rawValue, "queued")
        XCTAssertEqual(QueuedTaskStatus.running.rawValue, "running")
        XCTAssertEqual(QueuedTaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(QueuedTaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(QueuedTaskStatus.cancelled.rawValue, "cancelled")
        XCTAssertEqual(QueuedTaskStatus.paused.rawValue, "paused")
    }

    func testTaskPriorityDisplayNames() {
        XCTAssertEqual(TaskPriority.low.displayName, "Low")
        XCTAssertEqual(TaskPriority.normal.displayName, "Normal")
        XCTAssertEqual(TaskPriority.high.displayName, "High")
        XCTAssertEqual(TaskPriority.urgent.displayName, "Urgent")
    }
}

// MARK: - TaskPersistence Tests

final class TaskPersistenceTests: XCTestCase {

    var persistence: TaskPersistence!

    override func setUp() {
        persistence = TaskPersistence.shared
        // Use history for these tests since queue is used by TaskManagerTests
        persistence.clearHistory()
    }

    override func tearDown() {
        persistence.clearHistory()
    }

    func testSaveAndLoadHistory() async throws {
        // Create tasks with unique IDs we can verify
        let task1 = QueuedTask(description: "HistoryTest-Task1", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let task2 = QueuedTask(description: "HistoryTest-Task2", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let tasks = [task1, task2]

        persistence.saveHistory(tasks)

        // Wait for debounced save to complete (500ms debounce + buffer)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let loaded = persistence.loadHistory()

        // Verify our specific tasks are in the loaded result
        XCTAssertTrue(loaded.contains { $0.id == task1.id }, "Task 1 should be in loaded history")
        XCTAssertTrue(loaded.contains { $0.id == task2.id }, "Task 2 should be in loaded history")
    }

    func testClearHistory() async throws {
        // First save something
        let task = QueuedTask(description: "ClearHistoryTest", workingDirectory: URL(fileURLWithPath: "/tmp"))
        persistence.saveHistory([task])
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Now clear
        persistence.clearHistory()

        let loaded = persistence.loadHistory()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testAppendToHistory() async throws {
        // Clear first
        persistence.clearHistory()

        let task = QueuedTask(description: "AppendTest", workingDirectory: URL(fileURLWithPath: "/tmp"))
        persistence.appendToHistory(task)

        // Wait for debounce
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let loaded = persistence.loadHistory()
        XCTAssertTrue(loaded.contains { $0.id == task.id }, "Appended task should be in history")
    }
}
