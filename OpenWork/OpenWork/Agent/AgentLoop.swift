import Foundation

/// Tracks the agentic execution state
@MainActor
class AgentLoop: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var currentTurn: Int = 0
    @Published var maxTurns: Int = 50
    @Published var messages: [AgentMessage] = []
    @Published var currentToolExecution: String?

    private let providerManager: ProviderManager
    private let toolRegistry: ToolRegistry
    private let vmManager: VMManager?
    private var workingDirectory: URL
    private var abortRequested: Bool = false

    private var doomLoopDetector = DoomLoopDetector()

    init(
        providerManager: ProviderManager,
        toolRegistry: ToolRegistry = .shared,
        vmManager: VMManager? = nil,
        workingDirectory: URL
    ) {
        self.providerManager = providerManager
        self.toolRegistry = toolRegistry
        self.vmManager = vmManager
        self.workingDirectory = workingDirectory
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
            print("[AgentLoop] Turn \(currentTurn) starting...")

            // Check for doom loop
            if let warning = doomLoopDetector.check() {
                messages.append(AgentMessage(
                    role: .system,
                    content: "Warning: \(warning)"
                ))
            }

            // Call LLM
            guard let provider = providerManager.activeProvider else {
                print("[AgentLoop] No provider configured")
                throw AgentError.noProvider
            }

            print("[AgentLoop] Calling LLM: \(provider.name) at \(provider.baseURL)")

            // Use non-streaming API for Ollama compatibility
            let response = try await callLLMNonStreaming(provider: provider)
            print("[AgentLoop] Got response - content length: \(response.content.count), tool calls: \(response.toolCalls.count)")

            // Record assistant message
            if !response.content.isEmpty {
                messages.append(AgentMessage(role: .assistant, content: response.content))
            }

            // Process tool calls
            if response.toolCalls.isEmpty {
                // No tool calls, task might be complete
                print("[AgentLoop] No tool calls - task complete. Response: \(response.content.prefix(200))...")
                break
            }

            print("[AgentLoop] Processing \(response.toolCalls.count) tool calls...")

            for toolCall in response.toolCalls {
                print("[AgentLoop] Tool call: \(toolCall.name) with args: \(toolCall.arguments.prefix(100))...")

                // Parse arguments
                guard let argumentsData = toolCall.arguments.data(using: .utf8),
                      let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
                    messages.append(AgentMessage(
                        role: .tool,
                        content: "Failed to parse tool arguments",
                        toolCallId: toolCall.id
                    ))
                    continue
                }

                // Execute tool
                currentToolExecution = toolCall.name

                let result = await executeTool(name: toolCall.name, arguments: arguments)
                print("[AgentLoop] Tool result: \(result.output.prefix(200))...")

                messages.append(AgentMessage(
                    role: .tool,
                    content: result.output,
                    toolCallId: toolCall.id,
                    toolResult: result
                ))

                // Track for doom loop detection
                doomLoopDetector.record(tool: toolCall.name, args: arguments)

                // Check if doom loop detected
                if let warning = doomLoopDetector.check() {
                    print("[AgentLoop] DOOM LOOP DETECTED: \(warning)")
                    messages.append(AgentMessage(role: .system, content: warning))
                    // Break out of the loop
                    abortRequested = true
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
            var msgDict: [String: Any] = ["role": msg.role.rawValue, "content": msg.content]
            if let toolCallId = msg.toolCallId {
                msgDict["tool_call_id"] = toolCallId
            }
            chatMessages.append(msgDict)
        }

        // Build tools array
        let tools = await toolRegistry.toolDefinitions()
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
        guard let tool = await toolRegistry.tool(forID: name) else {
            return ToolResult.error("Unknown tool: \(name)")
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

    enum Role: String {
        case system = "system"
        case user = "user"
        case assistant = "assistant"
        case tool = "tool"
    }
}

/// Detects when the agent is stuck in a loop
class DoomLoopDetector {
    private var history: [(tool: String, argsHash: Int)] = []
    private let threshold = 3

    /// Records a tool invocation
    func record(tool: String, args: [String: Any]) {
        let argsHash = hashArgs(args)
        history.append((tool: tool, argsHash: argsHash))

        // Keep only recent history
        if history.count > 10 {
            history.removeFirst()
        }
    }

    /// Checks if we're in a doom loop, returns warning message if so
    func check() -> String? {
        guard history.count >= threshold else { return nil }

        let recent = history.suffix(threshold)
        let first = recent.first!

        // Check if all recent calls are the same
        if recent.allSatisfy({ $0.tool == first.tool && $0.argsHash == first.argsHash }) {
            return "Agent appears to be repeating the same action. Consider trying a different approach."
        }

        return nil
    }

    /// Resets the detector
    func reset() {
        history.removeAll()
    }

    private func hashArgs(_ args: [String: Any]) -> Int {
        var hasher = Hasher()
        for (key, value) in args.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(String(describing: value))
        }
        return hasher.finalize()
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
