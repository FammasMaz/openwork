import Foundation

/// Decomposes complex tasks into smaller sub-tasks using LLM
@MainActor
class TaskDecomposer {
    private let providerManager: ProviderManager
    
    init(providerManager: ProviderManager) {
        self.providerManager = providerManager
    }
    
    /// Decompose a complex task into smaller sub-tasks
    func decompose(
        task: String,
        workingDirectory: URL,
        availableTools: [String]
    ) async throws -> TaskDecomposition {
        guard let provider = providerManager.activeProvider else {
            throw TaskDecomposerError.noProvider
        }
        
        let prompt = buildDecompositionPrompt(
            task: task,
            workingDirectory: workingDirectory,
            availableTools: availableTools
        )
        
        let response = try await callLLM(provider: provider, prompt: prompt)
        let subtasks = try parseSubtasks(from: response)
        
        return TaskDecomposition(
            originalTask: task,
            subtasks: subtasks,
            estimatedDuration: nil,
            parallelizable: hasParallelizableSubtasks(subtasks)
        )
    }
    
    // MARK: - Prompt Building
    
    private func buildDecompositionPrompt(
        task: String,
        workingDirectory: URL,
        availableTools: [String]
    ) -> String {
        """
        You are a task decomposition expert. Your job is to break down complex tasks into smaller, independent subtasks that can be executed by an AI agent.

        ## Guidelines:
        1. Each subtask should be specific and actionable
        2. Identify dependencies between subtasks (which must complete before others can start)
        3. Maximize parallelization - subtasks without dependencies can run concurrently
        4. Keep subtasks focused - each should accomplish one clear goal
        5. Order by priority (0 = highest priority)

        ## Context:
        - Working directory: \(workingDirectory.path)
        - Available tools: \(availableTools.joined(separator: ", "))

        ## Task to decompose:
        \(task)

        ## Response Format:
        Respond with a JSON object containing an array of subtasks:
        ```json
        {
          "subtasks": [
            {
              "id": "unique-id-1",
              "description": "Clear description of what this subtask should accomplish",
              "dependencies": [],
              "expectedOutput": "What the subtask should produce",
              "priority": 0
            },
            {
              "id": "unique-id-2", 
              "description": "Another subtask that depends on the first",
              "dependencies": ["unique-id-1"],
              "expectedOutput": "Expected result",
              "priority": 1
            }
          ]
        }
        ```

        Important:
        - Use descriptive string IDs that will be converted to UUIDs
        - Dependencies should reference IDs of other subtasks
        - Empty dependencies array means the subtask can start immediately
        - Lower priority numbers = higher priority (0 is highest)

        Respond ONLY with the JSON object, no additional text.
        """
    }
    
    // MARK: - LLM Call
    
    private func callLLM(provider: LLMProviderConfig, prompt: String) async throws -> String {
        guard let url = provider.chatCompletionsURL else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        if !provider.apiKey.isEmpty {
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        
        let body: [String: Any] = [
            "model": provider.model,
            "messages": messages,
            "stream": false,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TaskDecomposerError.llmError("Failed to get response from LLM")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TaskDecomposerError.parseError("Failed to parse LLM response")
        }
        
        return content
    }
    
    // MARK: - Parsing
    
    private func parseSubtasks(from response: String) throws -> [SubTaskDefinition] {
        // Extract JSON from response (may be wrapped in markdown code blocks)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subtasksArray = json["subtasks"] as? [[String: Any]] else {
            throw TaskDecomposerError.parseError("Invalid JSON structure")
        }
        
        // Build ID mapping (string ID -> UUID)
        var idMapping: [String: UUID] = [:]
        for subtask in subtasksArray {
            if let stringId = subtask["id"] as? String {
                idMapping[stringId] = UUID()
            }
        }
        
        // Parse subtasks with proper UUID references
        var subtasks: [SubTaskDefinition] = []
        for subtask in subtasksArray {
            guard let stringId = subtask["id"] as? String,
                  let uuid = idMapping[stringId],
                  let description = subtask["description"] as? String else {
                continue
            }
            
            // Map dependency string IDs to UUIDs
            var dependencies: [UUID] = []
            if let depStrings = subtask["dependencies"] as? [String] {
                dependencies = depStrings.compactMap { idMapping[$0] }
            }
            
            let expectedOutput = subtask["expectedOutput"] as? String
            let priority = subtask["priority"] as? Int ?? 0
            
            subtasks.append(SubTaskDefinition(
                id: uuid,
                description: description,
                dependencies: dependencies,
                expectedOutput: expectedOutput,
                priority: priority
            ))
        }
        
        return subtasks
    }
    
    private func hasParallelizableSubtasks(_ subtasks: [SubTaskDefinition]) -> Bool {
        // Check if there are multiple root subtasks (no dependencies)
        let rootCount = subtasks.filter { $0.dependencies.isEmpty }.count
        return rootCount > 1
    }
}

// MARK: - Errors

enum TaskDecomposerError: LocalizedError {
    case noProvider
    case llmError(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "No LLM provider configured"
        case .llmError(let msg):
            return "LLM error: \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}
