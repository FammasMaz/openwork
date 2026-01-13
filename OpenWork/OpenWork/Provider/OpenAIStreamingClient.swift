import Foundation

/// OpenAI-compatible streaming client for LLM interactions
actor OpenAIStreamingClient {
    private let config: LLMProviderConfig
    private var currentTask: URLSessionDataTask?

    init(config: LLMProviderConfig) {
        self.config = config
    }

    // MARK: - Streaming Chat Completion

    /// Sends a chat completion request with streaming response
    func streamChatCompletion(
        messages: [ChatMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await performStreamRequest(
                        messages: messages,
                        tools: tools,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func performStreamRequest(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        guard let url = config.chatCompletionsURL else {
            throw StreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Add authorization
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build request body
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "temperature": temperature
        ]

        if let maxTokens = maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = try tools.map { tool -> [String: Any] in
                let encoder = JSONEncoder()
                let data = try encoder.encode(tool)
                return try JSONSerialization.jsonObject(with: data) as! [String: Any]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Perform streaming request
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse SSE stream
        var buffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            // Check for complete SSE event (ends with double newline)
            while let eventEnd = buffer.range(of: "\n\n") {
                let eventString = String(buffer[..<eventEnd.lowerBound])
                buffer.removeSubrange(..<eventEnd.upperBound)

                if let event = parseSSEEvent(eventString) {
                    if event.isDone {
                        continuation.finish()
                        return
                    }
                    continuation.yield(event)
                }
            }
        }

        continuation.finish()
    }

    private func parseSSEEvent(_ eventString: String) -> StreamEvent? {
        var data: String?

        for line in eventString.split(separator: "\n") {
            if line.hasPrefix("data: ") {
                data = String(line.dropFirst(6))
            }
        }

        guard let data = data else { return nil }

        if data == "[DONE]" {
            return StreamEvent(isDone: true)
        }

        guard let jsonData = data.data(using: .utf8) else { return nil }

        do {
            let chunk = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
            return StreamEvent(chunk: chunk)
        } catch {
            // Log parsing error but continue
            print("Failed to parse chunk: \(error)")
            return nil
        }
    }

    // MARK: - Non-Streaming Chat Completion

    func chatCompletion(
        messages: [ChatMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> ChatCompletionResponse {
        guard let url = config.chatCompletionsURL else {
            throw StreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "temperature": temperature
        ]

        if let maxTokens = maxTokens {
            body["max_tokens"] = maxTokens
        }

        if let tools = tools, !tools.isEmpty {
            body["tools"] = try tools.map { tool -> [String: Any] in
                let encoder = JSONEncoder()
                let data = try encoder.encode(tool)
                return try JSONSerialization.jsonObject(with: data) as! [String: Any]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw StreamError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }

    // MARK: - Cancel

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - Stream Types

/// A single event from the SSE stream
struct StreamEvent {
    var isDone: Bool = false
    var chunk: StreamChunk?
    var delta: String? {
        chunk?.choices.first?.delta?.content
    }
    var toolCalls: [ToolCallDelta]? {
        chunk?.choices.first?.delta?.toolCalls
    }
    var finishReason: String? {
        chunk?.choices.first?.finishReason
    }
}

/// OpenAI streaming chunk format
struct StreamChunk: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [StreamChoice]

    struct StreamChoice: Codable {
        let index: Int?
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable {
        let role: String?
        let content: String?
        let toolCalls: [ToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
}

/// Tool call delta for streaming
struct ToolCallDelta: Codable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionDelta?

    struct FunctionDelta: Codable {
        let name: String?
        let arguments: String?
    }
}

/// Full chat completion response (non-streaming)
struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Codable {
        let role: String
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Errors

enum StreamError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String? = nil)
    case parsingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid provider URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            if let message = message {
                return "HTTP \(code): \(message)"
            }
            return "HTTP error: \(code)"
        case .parsingError(let details):
            return "Failed to parse response: \(details)"
        }
    }
}
