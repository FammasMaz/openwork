import Foundation

/// Coordinates parallel sub-agent execution for complex tasks
@MainActor
class SubAgentCoordinator: ObservableObject {
    @Published var activeSubTasks: [SubTaskState] = []
    @Published var completedSubTasks: [SubTaskState] = []
    @Published var isRunning: Bool = false
    @Published var overallProgress: Double = 0
    
    private let providerManager: ProviderManager
    private let toolRegistry: ToolRegistry
    private let maxParallelAgents: Int
    private var runningTasks: [UUID: Task<SubTaskResult, Error>] = [:]
    
    init(
        providerManager: ProviderManager,
        toolRegistry: ToolRegistry,
        maxParallelAgents: Int = 3
    ) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.maxParallelAgents = maxParallelAgents
    }
    
    // MARK: - Public API
    
    /// Execute a complex task by decomposing it and running sub-agents
    func execute(
        task: String,
        workingDirectory: URL,
        approvalManager: ApprovalManager? = nil,
        permissionManager: PermissionManager? = nil,
        onProgress: ((SubTaskProgress) -> Void)? = nil
    ) async throws -> [SubTaskResult] {
        isRunning = true
        activeSubTasks = []
        completedSubTasks = []
        overallProgress = 0
        
        defer { isRunning = false }
        
        // Decompose the task
        let decomposer = TaskDecomposer(providerManager: providerManager)
        let availableTools = toolRegistry.tools.values.map { $0.id }
        
        let decomposition = try await decomposer.decompose(
            task: task,
            workingDirectory: workingDirectory,
            availableTools: availableTools
        )
        
        // Initialize states for all subtasks
        for subtask in decomposition.subtasks {
            activeSubTasks.append(SubTaskState(
                id: subtask.id,
                description: subtask.description,
                status: .pending
            ))
        }
        
        // Execute subtasks respecting dependencies
        let results = try await executeSubtasks(
            decomposition: decomposition,
            workingDirectory: workingDirectory,
            approvalManager: approvalManager,
            permissionManager: permissionManager,
            onProgress: onProgress
        )
        
        onProgress?(.allCompleted)
        return results
    }
    
    /// Cancel all running sub-agents
    func cancel() {
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
        
        // Mark active tasks as cancelled
        for i in activeSubTasks.indices {
            if activeSubTasks[i].status == .running || activeSubTasks[i].status == .pending {
                activeSubTasks[i].status = .cancelled
            }
        }
        
        isRunning = false
    }
    
    // MARK: - Execution Engine
    
    private func executeSubtasks(
        decomposition: TaskDecomposition,
        workingDirectory: URL,
        approvalManager: ApprovalManager?,
        permissionManager: PermissionManager?,
        onProgress: ((SubTaskProgress) -> Void)?
    ) async throws -> [SubTaskResult] {
        var results: [UUID: SubTaskResult] = [:]
        var completedIds: Set<UUID> = []
        var pending = decomposition.subtasks
        
        while !pending.isEmpty || !runningTasks.isEmpty {
            // Find subtasks ready to run (dependencies satisfied)
            let ready = pending.filter { subtask in
                decomposition.dependenciesSatisfied(for: subtask, completedIds: completedIds)
            }
            
            // Start new tasks up to max parallel limit
            let availableSlots = maxParallelAgents - runningTasks.count
            let toStart = Array(ready.prefix(availableSlots))
            
            for subtask in toStart {
                pending.removeAll { $0.id == subtask.id }
                
                // Update state to running
                if let index = activeSubTasks.firstIndex(where: { $0.id == subtask.id }) {
                    activeSubTasks[index].status = .running
                    activeSubTasks[index].startTime = Date()
                }
                
                onProgress?(.started(subtaskId: subtask.id))
                
                // Start the sub-agent task
                let task = Task<SubTaskResult, Error> {
                    try await self.runSubAgent(
                        subtask: subtask,
                        workingDirectory: workingDirectory,
                        dependencyResults: subtask.dependencies.compactMap { results[$0] },
                        approvalManager: approvalManager,
                        permissionManager: permissionManager,
                        onProgress: onProgress
                    )
                }
                runningTasks[subtask.id] = task
            }
            
            // Wait for at least one task to complete
            if !runningTasks.isEmpty {
                let (completedId, result) = await waitForAnyTask()
                runningTasks.removeValue(forKey: completedId)
                
                // Store result
                results[completedId] = result
                completedIds.insert(completedId)
                
                // Update state
                if let index = activeSubTasks.firstIndex(where: { $0.id == completedId }) {
                    var state = activeSubTasks.remove(at: index)
                    state.status = result.success ? .completed : .failed
                    state.endTime = Date()
                    state.result = result
                    completedSubTasks.append(state)
                }
                
                // Update overall progress
                let total = decomposition.subtasks.count
                overallProgress = Double(completedIds.count) / Double(total)
                
                onProgress?(.subtaskCompleted(result))
            }
            
            // Small delay to prevent tight loop
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        return Array(results.values)
    }
    
    private func waitForAnyTask() async -> (UUID, SubTaskResult) {
        // This is a simplified version - in production you'd use TaskGroup
        while true {
            for (id, task) in runningTasks {
                // Check if task is done using a non-blocking approach
                let result = await Task {
                    do {
                        return try await task.value
                    } catch {
                        return SubTaskResult(
                            subtaskId: id,
                            success: false,
                            output: "",
                            errorMessage: error.localizedDescription
                        )
                    }
                }.value
                
                return (id, result)
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
    
    // MARK: - Sub-Agent Execution
    
    private func runSubAgent(
        subtask: SubTaskDefinition,
        workingDirectory: URL,
        dependencyResults: [SubTaskResult],
        approvalManager: ApprovalManager?,
        permissionManager: PermissionManager?,
        onProgress: ((SubTaskProgress) -> Void)?
    ) async throws -> SubTaskResult {
        // Build context from dependency results
        let contextPrompt = buildDependencyContext(dependencyResults)
        let fullTask = contextPrompt.isEmpty
            ? subtask.description
            : "\(contextPrompt)\n\nYour task: \(subtask.description)"
        
        // Create a sub-agent (new AgentLoop instance)
        let subAgent = AgentLoop(
            providerManager: providerManager,
            toolRegistry: toolRegistry,
            vmManager: nil,  // Sub-agents share parent's context
            workingDirectory: workingDirectory,
            approvalManager: approvalManager,
            permissionManager: permissionManager,
            logCallback: { message, type in
                let logType: SubTaskLogType
                switch type {
                case .info: logType = .info
                case .warning: logType = .warning
                case .error: logType = .error
                case .toolCall: logType = .toolCall
                case .toolResult: logType = .toolResult
                }
                onProgress?(.log(subtaskId: subtask.id, message: message, type: logType))
            }
        )
        
        // Run the sub-agent
        do {
            try await subAgent.start(task: fullTask)
            
            // Extract final output from agent messages
            let output = subAgent.messages
                .filter { $0.role == .assistant }
                .map { $0.content }
                .joined(separator: "\n")
            
            return SubTaskResult(
                subtaskId: subtask.id,
                success: true,
                output: output
            )
        } catch {
            return SubTaskResult(
                subtaskId: subtask.id,
                success: false,
                output: "",
                errorMessage: error.localizedDescription
            )
        }
    }
    
    private func buildDependencyContext(_ results: [SubTaskResult]) -> String {
        guard !results.isEmpty else { return "" }
        
        var context = "## Context from completed subtasks:\n\n"
        for (index, result) in results.enumerated() {
            if result.success {
                context += "### Subtask \(index + 1) Result:\n\(result.output)\n\n"
            }
        }
        return context
    }
}
