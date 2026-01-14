import Foundation

enum AgentLogType {
    case info
    case toolCall
    case toolResult
    case error
    case warning
}

/// Tracks the agentic execution state
@MainActor
class AgentLoop: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var currentTurn: Int = 0
    @Published var maxTurns: Int = 50
    @Published var messages: [AgentMessage] = []
    @Published var currentToolExecution: String?
    @Published var pendingApproval: Bool = false

    private let providerManager: ProviderManager
    private let toolRegistry: ToolRegistry
    private let vmManager: VMManager?
    private var workingDirectory: URL
    private var abortRequested: Bool = false
    private let logCallback: ((String, AgentLogType) -> Void)?
    
    /// Approval manager for tool execution approval workflow
    private var approvalManager: ApprovalManager?
    
    /// Permission manager for folder access validation
    private var permissionManager: PermissionManager?

    private var doomLoopDetector = DoomLoopDetector()

    init(
        providerManager: ProviderManager,
        toolRegistry: ToolRegistry,
        vmManager: VMManager? = nil,
        workingDirectory: URL,
        approvalManager: ApprovalManager? = nil,
        permissionManager: PermissionManager? = nil,
        logCallback: ((String, AgentLogType) -> Void)? = nil
    ) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.vmManager = vmManager
        self.workingDirectory = workingDirectory
        self.approvalManager = approvalManager
        self.permissionManager = permissionManager
        self.logCallback = logCallback
    }
    
    /// Set the approval manager (for dependency injection after init)
    func setApprovalManager(_ manager: ApprovalManager) {
        self.approvalManager = manager
    }
    
    /// Set the permission manager (for dependency injection after init)
    func setPermissionManager(_ manager: PermissionManager) {
        self.permissionManager = manager
    }
    
    private func log(_ message: String, type: AgentLogType = .info) {
        logCallback?(message, type)
    }

    // MARK: - Public API

    /// Starts the agent loop with a task description
    func start(task: String) async throws {
        guard !isRunning else { return }

        isRunning = true
        currentTurn = 0
        abortRequested = false
        messages = []

        // Add system message
        let systemPrompt = buildSystemPrompt()
        messages.append(AgentMessage(role: .system, content: systemPrompt))

        // Add user task
        messages.append(AgentMessage(role: .user, content: task))

        // Main agentic loop
        do {
            try await runLoop()
        } catch {
            messages.append(AgentMessage(
                role: .assistant,
                content: "Error: \(error.localizedDescription)"
            ))
            throw error
        }

        isRunning = false
    }

    /// Requests the agent to stop
    func stop() {
        abortRequested = true
    }

    // MARK: - Main Loop

    private func runLoop() async throws {
        while currentTurn < maxTurns && !abortRequested {
            currentTurn += 1
            log("Turn \(currentTurn) starting...", type: .info)

            if let warning = doomLoopDetector.check() {
                log(warning, type: .warning)
                messages.append(AgentMessage(
                    role: .system,
                    content: "Warning: \(warning)"
                ))
                abortRequested = true
                break
            }

            guard let provider = providerManager.activeProvider else {
                log("No provider configured", type: .error)
                throw AgentError.noProvider
            }

            log("Calling LLM: \(provider.name)", type: .info)

            let response = try await callLLMNonStreaming(provider: provider)

            if response.toolCalls.isEmpty {
                log("Task complete", type: .info)
                if !response.content.isEmpty {
                    messages.append(AgentMessage(role: .assistant, content: response.content))
                }
                break
            }
            
            let toolCallsForMessage = response.toolCalls.map { tc -> [String: Any] in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": tc.arguments
                    ]
                ]
            }
            messages.append(AgentMessage(
                role: .assistant,
                content: response.content,
                toolCalls: toolCallsForMessage
            ))

            for toolCall in response.toolCalls {
                log("Tool: \(toolCall.name)", type: .toolCall)

                guard let argumentsData = toolCall.arguments.data(using: .utf8),
                      let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
                    log("Failed to parse tool arguments", type: .error)
                    messages.append(AgentMessage(
                        role: .tool,
                        content: "Failed to parse tool arguments",
                        toolCallId: toolCall.id
                    ))
                    continue
                }

                currentToolExecution = toolCall.name

                let result = await executeTool(name: toolCall.name, arguments: arguments)
                log("\(toolCall.name): \(result.output.prefix(150))...", type: .toolResult)

                messages.append(AgentMessage(
                    role: .tool,
                    content: result.output,
                    toolCallId: toolCall.id,
                    toolResult: result
                ))

                doomLoopDetector.record(
                    tool: toolCall.name,
                    normalizedKey: result.normalizedKey ?? "\(toolCall.name):\(toolCall.id)",
                    didChange: result.didChange
                )

                if let warning = doomLoopDetector.check() {
                    log("LOOP DETECTED: \(warning)", type: .warning)
                    messages.append(AgentMessage(role: .system, content: warning))
                    abortRequested = true
                    break
                }

                currentToolExecution = nil
            }
        }
    }

    // MARK: - Non-Streaming LLM Call

    private struct LLMResponse {
        let content: String
        let toolCalls: [ParsedToolCall]
    }

    private struct ParsedToolCall {
        let id: String
        let name: String
        let arguments: String
    }

    private func callLLMNonStreaming(provider: LLMProviderConfig) async throws -> LLMResponse {
        guard let url = provider.chatCompletionsURL else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if !provider.apiKey.isEmpty {
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build messages array
        var chatMessages: [[String: Any]] = []
        for msg in messages {
            var msgDict: [String: Any] = ["role": msg.role.rawValue]
            
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                msgDict["tool_calls"] = toolCalls
                msgDict["content"] = msg.content.isEmpty ? NSNull() : msg.content
            } else {
                msgDict["content"] = msg.content
            }
            
            if let toolCallId = msg.toolCallId {
                msgDict["tool_call_id"] = toolCallId
            }
            chatMessages.append(msgDict)
        }
        
        #if DEBUG
        if let debugData = try? JSONSerialization.data(withJSONObject: chatMessages, options: .prettyPrinted),
           let debugStr = String(data: debugData, encoding: .utf8) {
            print("[AgentLoop] Sending messages:\n\(debugStr.prefix(3000))")
        }
        #endif

        // Build tools array
        let tools = toolRegistry.toolDefinitions()
        var toolsArray: [[String: Any]] = []
        for tool in tools {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(tool),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                toolsArray.append(dict)
            }
        }

        var body: [String: Any] = [
            "model": provider.model,
            "messages": chatMessages,
            "stream": false
        ]

        if provider.apiFormat == .openAICompatible {
            body["max_tokens"] = 4096
            if !toolsArray.isEmpty {
                body["tools"] = toolsArray
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "LLM", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Parse response based on API format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }

        var content = ""
        var toolCalls: [ParsedToolCall] = []

        if provider.apiFormat == .ollamaNative {
            // Ollama native format
            if let message = json["message"] as? [String: Any] {
                content = message["content"] as? String ?? ""
                // Note: Ollama native format doesn't support tool calls the same way
            }
        } else {
            // OpenAI format
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any] {
                content = message["content"] as? String ?? ""

                // Parse tool calls if present
                if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
                    for tc in rawToolCalls {
                        if let id = tc["id"] as? String,
                           let function = tc["function"] as? [String: Any],
                           let name = function["name"] as? String,
                           let arguments = function["arguments"] as? String {
                            toolCalls.append(ParsedToolCall(id: id, name: name, arguments: arguments))
                        }
                    }
                }
            }
        }

        return LLMResponse(content: content, toolCalls: toolCalls)
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: [String: Any]) async -> ToolResult {
        guard let tool = toolRegistry.tool(forID: name) else {
            return ToolResult.error("Unknown tool: \(name)")
        }
        
        // Check folder permissions for file operations
        if let permManager = permissionManager {
            if let filePath = arguments["file_path"] as? String {
                let fullPath = filePath.hasPrefix("/") ? filePath : workingDirectory.appendingPathComponent(filePath).path
                
                // For write operations, check write permission
                if tool.category == .write {
                    if !permManager.isWriteAllowed(fullPath) {
                        log("Permission denied for write to: \(fullPath)", type: .error)
                        return ToolResult.error("Permission denied: Path not in allowed folders or folder is read-only: \(fullPath)")
                    }
                } else if tool.category == .read {
                    // For read operations, check read permission
                    if !permManager.isPathAllowed(fullPath) {
                        log("Permission denied for read from: \(fullPath)", type: .error)
                        return ToolResult.error("Permission denied: Path not in allowed folders: \(fullPath)")
                    }
                }
            }
        }
        
        // Check if tool requires approval
        if tool.requiresApproval, let approvalMgr = approvalManager {
            log("Requesting approval for: \(tool.name)", type: .info)
            pendingApproval = true
            
            let decision = await approvalMgr.requestApproval(
                tool: tool,
                args: arguments,
                workingDirectory: workingDirectory
            )
            
            pendingApproval = false
            
            switch decision {
            case .denied(let reason):
                log("Tool execution denied: \(reason ?? "User declined")", type: .warning)
                return ToolResult.error("Denied by user: \(reason ?? "User declined")")
            case .approved:
                log("Tool execution approved", type: .info)
                // Continue with execution
            }
        }

        let context = ToolContext(
            sessionID: UUID().uuidString,
            messageID: UUID().uuidString,
            workingDirectory: workingDirectory,
            abort: { self.abortRequested },
            vmManager: vmManager
        )

        do {
            return try await tool.execute(args: arguments, context: context)
        } catch {
            return ToolResult.error(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func buildSystemPrompt() -> String {
        """
        You are OpenWork, an AI coding assistant that can execute tasks autonomously.

        You have access to the following tools:
        - read: Read file contents
        - write: Write file contents
        - edit: Edit files with string replacement
        - glob: Find files by pattern
        - grep: Search file contents
        - bash: Execute bash commands
        - ls: List directory contents

        Guidelines:
        1. Break complex tasks into smaller steps
        2. Read files before modifying them
        3. Verify your changes work correctly
        4. Ask for clarification if requirements are unclear
        5. Be careful with destructive operations

        Working directory: \(workingDirectory.path)
        """
    }
}

/// A message in the agent conversation
struct AgentMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var toolCallId: String?
    var toolResult: ToolResult?
    var toolCalls: [[String: Any]]?

    enum Role: String {
        case system = "system"
        case user = "user"
        case assistant = "assistant"
        case tool = "tool"
    }
}

/// Detects when the agent is stuck in a loop
class DoomLoopDetector {
    struct ToolRecord {
        let tool: String
        let normalizedKey: String
        let didChange: Bool
        let timestamp: Date
    }
    
    private var history: [ToolRecord] = []
    private let cycles = 3
    private let maxPeriod = 4

    func record(tool: String, normalizedKey: String, didChange: Bool) {
        history.append(ToolRecord(
            tool: tool,
            normalizedKey: normalizedKey,
            didChange: didChange,
            timestamp: Date()
        ))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }

    func check() -> String? {
        for period in 1...maxPeriod {
            let window = period * cycles
            guard history.count >= window else { continue }

            let recent = Array(history.suffix(window)).map(\.normalizedKey)
            let firstChunk = Array(recent.prefix(period))

            var matches = true
            for i in 1..<cycles {
                let chunk = Array(recent[(i*period)..<((i+1)*period)])
                if chunk != firstChunk { matches = false; break }
            }

            if matches {
                return "Agent repeating a \(period)-step pattern: \(firstChunk.joined(separator: " → ")). Stopping."
            }
        }

        let lastN = history.suffix(6)
        if lastN.count == 6 && lastN.allSatisfy({ $0.didChange == false }) {
            return "Agent executed 6 tools without making changes. Stopping."
        }

        return nil
    }

    func reset() {
        history.removeAll()
    }
}

/// Agent-specific errors
enum AgentError: LocalizedError {
    case noProvider
    case maxTurnsExceeded
    case aborted
    case toolExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No LLM provider configured"
        case .maxTurnsExceeded:
            return "Maximum turns exceeded"
        case .aborted:
            return "Agent was aborted"
        case .toolExecutionFailed(let msg):
            return "Tool execution failed: \(msg)"
        }
    }
}
