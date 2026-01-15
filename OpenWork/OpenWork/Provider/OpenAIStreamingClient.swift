import Foundation

/// Multi-provider streaming client for LLM interactions
/// Supports OpenAI-compatible, Anthropic, Gemini, and Ollama APIs
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
        let request = try buildRequest(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: true
        )

        // Perform streaming request
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw StreamError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse SSE stream based on API format
        switch config.apiFormat {
        case .anthropic:
            try await parseAnthropicStream(bytes: bytes, continuation: continuation)
        case .gemini:
            try await parseGeminiStream(bytes: bytes, continuation: continuation)
        default:
            try await parseOpenAIStream(bytes: bytes, continuation: continuation)
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stream: Bool
    ) throws -> URLRequest {
        var url = config.chatCompletionsURL!

        // Gemini uses API key as query param
        if config.apiFormat == .gemini && !config.secureAPIKey.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "key", value: config.secureAPIKey))
            if stream {
                queryItems.append(URLQueryItem(name: "alt", value: "sse"))
            }
            components.queryItems = queryItems
            url = components.url!
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Add authorization based on API format
        let apiKey = config.secureAPIKey
        if !apiKey.isEmpty {
            switch config.apiFormat {
            case .anthropic:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            case .gemini:
                // Already added as query param
                break
            default:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        // Add custom headers
        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build request body based on API format
        let body: [String: Any]
        switch config.apiFormat {
        case .anthropic:
            body = try buildAnthropicBody(messages: messages, tools: tools, temperature: temperature, maxTokens: maxTokens, stream: stream)
        case .gemini:
            body = try buildGeminiBody(messages: messages, tools: tools, temperature: temperature, maxTokens: maxTokens)
        default:
            body = try buildOpenAIBody(messages: messages, tools: tools, temperature: temperature, maxTokens: maxTokens, stream: stream)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - OpenAI Request Body

    private func buildOpenAIBody(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stream: Bool
    ) throws -> [String: Any] {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream,
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

        return body
    }

    // MARK: - Anthropic Request Body

    private func buildAnthropicBody(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stream: Bool
    ) throws -> [String: Any] {
        // Anthropic uses system as top-level param, not in messages
        var systemPrompt: String?
        var nonSystemMessages: [[String: Any]] = []

        for message in messages {
            if message.role == "system" {
                systemPrompt = message.content
            } else {
                nonSystemMessages.append([
                    "role": message.role,
                    "content": message.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": nonSystemMessages,
            "max_tokens": maxTokens ?? 4096
        ]

        if let systemPrompt = systemPrompt {
            body["system"] = systemPrompt
        }

        if stream {
            body["stream"] = true
        }

        // Anthropic tool format
        if let tools = tools, !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "input_schema": tool.function.parameters.mapValues { $0.value }
                ]
            }
        }

        return body
    }

    // MARK: - Gemini Request Body

    private func buildGeminiBody(
        messages: [ChatMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?
    ) throws -> [String: Any] {
        // Gemini uses "contents" with parts
        var contents: [[String: Any]] = []
        var systemInstruction: [String: Any]?

        for message in messages {
            if message.role == "system" {
                systemInstruction = [
                    "parts": [["text": message.content]]
                ]
            } else {
                let role = message.role == "assistant" ? "model" : "user"
                contents.append([
                    "role": role,
                    "parts": [["text": message.content]]
                ])
            }
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxTokens ?? 8192
            ]
        ]

        if let systemInstruction = systemInstruction {
            body["systemInstruction"] = systemInstruction
        }

        // Gemini tool format
        if let tools = tools, !tools.isEmpty {
            body["tools"] = [[
                "functionDeclarations": tools.map { tool -> [String: Any] in
                    [
                        "name": tool.function.name,
                        "description": tool.function.description,
                        "parameters": tool.function.parameters.mapValues { $0.value }
                    ]
                }
            ]]
        }

        return body
    }

    // MARK: - OpenAI Stream Parsing

    private func parseOpenAIStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var buffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            while let eventEnd = buffer.range(of: "\n\n") {
                let eventString = String(buffer[..<eventEnd.lowerBound])
                buffer.removeSubrange(..<eventEnd.upperBound)

                if let event = parseOpenAISSEEvent(eventString) {
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

    private func parseOpenAISSEEvent(_ eventString: String) -> StreamEvent? {
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
            print("Failed to parse OpenAI chunk: \(error)")
            return nil
        }
    }

    // MARK: - Anthropic Stream Parsing

    private func parseAnthropicStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var buffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            while let eventEnd = buffer.range(of: "\n\n") {
                let eventString = String(buffer[..<eventEnd.lowerBound])
                buffer.removeSubrange(..<eventEnd.upperBound)

                if let event = parseAnthropicSSEEvent(eventString) {
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

    private func parseAnthropicSSEEvent(_ eventString: String) -> StreamEvent? {
        var eventType: String?
        var data: String?

        for line in eventString.split(separator: "\n") {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                data = String(line.dropFirst(6))
            }
        }

        guard let data = data, let jsonData = data.data(using: .utf8) else { return nil }

        // Handle different Anthropic event types
        switch eventType {
        case "message_stop":
            return StreamEvent(isDone: true)
        case "content_block_delta":
            // Parse delta content
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                // Convert to OpenAI-compatible format
                let chunk = StreamChunk(
                    id: nil,
                    object: nil,
                    created: nil,
                    model: nil,
                    choices: [StreamChunk.StreamChoice(
                        index: 0,
                        delta: StreamChunk.Delta(role: nil, content: text, toolCalls: nil),
                        finishReason: nil
                    )]
                )
                return StreamEvent(chunk: chunk)
            }
        case "message_delta":
            // Check for stop reason
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                let chunk = StreamChunk(
                    id: nil,
                    object: nil,
                    created: nil,
                    model: nil,
                    choices: [StreamChunk.StreamChoice(
                        index: 0,
                        delta: nil,
                        finishReason: stopReason
                    )]
                )
                return StreamEvent(chunk: chunk)
            }
        default:
            break
        }

        return nil
    }

    // MARK: - Gemini Stream Parsing

    private func parseGeminiStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var buffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            while let eventEnd = buffer.range(of: "\n\n") {
                let eventString = String(buffer[..<eventEnd.lowerBound])
                buffer.removeSubrange(..<eventEnd.upperBound)

                if let event = parseGeminiSSEEvent(eventString) {
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

    private func parseGeminiSSEEvent(_ eventString: String) -> StreamEvent? {
        var data: String?

        for line in eventString.split(separator: "\n") {
            if line.hasPrefix("data: ") {
                data = String(line.dropFirst(6))
            }
        }

        guard let data = data, let jsonData = data.data(using: .utf8) else { return nil }

        // Parse Gemini response format
        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let text = firstPart["text"] as? String {

            let finishReason = firstCandidate["finishReason"] as? String

            let chunk = StreamChunk(
                id: nil,
                object: nil,
                created: nil,
                model: nil,
                choices: [StreamChunk.StreamChoice(
                    index: 0,
                    delta: StreamChunk.Delta(role: nil, content: text, toolCalls: nil),
                    finishReason: finishReason?.lowercased()
                )]
            )

            if finishReason == "STOP" {
                return StreamEvent(isDone: true)
            }

            return StreamEvent(chunk: chunk)
        }

        return nil
    }

    // MARK: - Non-Streaming Chat Completion

    func chatCompletion(
        messages: [ChatMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> ChatCompletionResponse {
        let request = try buildRequest(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw StreamError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response based on API format
        switch config.apiFormat {
        case .anthropic:
            return try parseAnthropicResponse(data: data)
        case .gemini:
            return try parseGeminiResponse(data: data)
        default:
            return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        }
    }

    // MARK: - Anthropic Response Parsing

    private func parseAnthropicResponse(data: Data) throws -> ChatCompletionResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamError.parsingError("Invalid Anthropic response")
        }

        let id = json["id"] as? String ?? ""
        let model = json["model"] as? String ?? ""

        var content: String?
        var toolCalls: [ToolCall]?

        if let contentArray = json["content"] as? [[String: Any]] {
            for block in contentArray {
                if block["type"] as? String == "text" {
                    content = block["text"] as? String
                } else if block["type"] as? String == "tool_use" {
                    let toolCall = ToolCall(
                        id: block["id"] as? String ?? "",
                        type: "function",
                        function: ToolCall.FunctionCall(
                            name: block["name"] as? String ?? "",
                            arguments: {
                                if let input = block["input"],
                                   let inputData = try? JSONSerialization.data(withJSONObject: input) {
                                    return String(data: inputData, encoding: .utf8) ?? "{}"
                                }
                                return "{}"
                            }()
                        )
                    )
                    if toolCalls == nil { toolCalls = [] }
                    toolCalls?.append(toolCall)
                }
            }
        }

        let stopReason = json["stop_reason"] as? String

        return ChatCompletionResponse(
            id: id,
            object: "message",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [ChatCompletionResponse.Choice(
                index: 0,
                message: ChatCompletionResponse.ResponseMessage(
                    role: "assistant",
                    content: content,
                    toolCalls: toolCalls
                ),
                finishReason: stopReason
            )],
            usage: nil
        )
    }

    // MARK: - Gemini Response Parsing

    private func parseGeminiResponse(data: Data) throws -> ChatCompletionResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            throw StreamError.parsingError("Invalid Gemini response")
        }

        var content: String?
        var toolCalls: [ToolCall]?

        if let contentDict = firstCandidate["content"] as? [String: Any],
           let parts = contentDict["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String {
                    content = text
                } else if let functionCall = part["functionCall"] as? [String: Any] {
                    let toolCall = ToolCall(
                        id: UUID().uuidString,
                        type: "function",
                        function: ToolCall.FunctionCall(
                            name: functionCall["name"] as? String ?? "",
                            arguments: {
                                if let args = functionCall["args"],
                                   let argsData = try? JSONSerialization.data(withJSONObject: args) {
                                    return String(data: argsData, encoding: .utf8) ?? "{}"
                                }
                                return "{}"
                            }()
                        )
                    )
                    if toolCalls == nil { toolCalls = [] }
                    toolCalls?.append(toolCall)
                }
            }
        }

        let finishReason = firstCandidate["finishReason"] as? String

        return ChatCompletionResponse(
            id: UUID().uuidString,
            object: "generateContent",
            created: Int(Date().timeIntervalSince1970),
            model: config.model,
            choices: [ChatCompletionResponse.Choice(
                index: 0,
                message: ChatCompletionResponse.ResponseMessage(
                    role: "assistant",
                    content: content,
                    toolCalls: toolCalls
                ),
                finishReason: finishReason?.lowercased()
            )],
            usage: nil
        )
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
