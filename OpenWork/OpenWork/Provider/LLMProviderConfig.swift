import Foundation

/// API format types
enum APIFormat: String, Codable, CaseIterable {
    case openAICompatible = "openai"
    case ollamaNative = "ollama"
}

/// Represents a configured LLM provider
struct LLMProviderConfig: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var customHeaders: [String: String]
    var isEnabled: Bool
    var apiFormat: APIFormat = .openAICompatible

    /// Built-in provider presets
    enum Preset: String, CaseIterable {
        case ollama
        case lmStudio
        case openAI
        case anthropic
        case custom

        var defaultConfig: LLMProviderConfig {
            switch self {
            case .ollama:
                return LLMProviderConfig(
                    name: "Ollama",
                    baseURL: "http://localhost:11434",
                    apiKey: "",
                    model: "llama3.2",
                    customHeaders: [:],
                    isEnabled: true,
                    apiFormat: .ollamaNative
                )
            case .lmStudio:
                return LLMProviderConfig(
                    name: "LM Studio",
                    baseURL: "http://localhost:1234/v1",
                    apiKey: "",
                    model: "local-model",
                    customHeaders: [:],
                    isEnabled: false,
                    apiFormat: .openAICompatible
                )
            case .openAI:
                return LLMProviderConfig(
                    name: "OpenAI",
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "",
                    model: "gpt-4o",
                    customHeaders: [:],
                    isEnabled: false,
                    apiFormat: .openAICompatible
                )
            case .anthropic:
                return LLMProviderConfig(
                    name: "Anthropic",
                    baseURL: "https://api.anthropic.com/v1",
                    apiKey: "",
                    model: "claude-sonnet-4-20250514",
                    customHeaders: [:],
                    isEnabled: false,
                    apiFormat: .openAICompatible
                )
            case .custom:
                return LLMProviderConfig(
                    name: "Custom Provider",
                    baseURL: "",
                    apiKey: "",
                    model: "",
                    customHeaders: [:],
                    isEnabled: false,
                    apiFormat: .openAICompatible
                )
            }
        }
    }

    /// Validates the provider configuration
    var isValid: Bool {
        !baseURL.isEmpty && !model.isEmpty && URL(string: baseURL) != nil
    }

    /// Returns the chat completions endpoint URL
    var chatCompletionsURL: URL? {
        guard var url = URL(string: baseURL) else { return nil }

        switch apiFormat {
        case .openAICompatible:
            url.appendPathComponent("chat/completions")
        case .ollamaNative:
            url.appendPathComponent("api/chat")
        }

        return url
    }
}

/// Message format for OpenAI-compatible API
struct ChatMessage: Codable {
    let role: String
    let content: String

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

/// Tool definition for function calling
struct ToolDefinition: Codable {
    let type: String
    let function: FunctionDefinition

    struct FunctionDefinition: Codable {
        let name: String
        let description: String
        let parameters: [String: AnyCodable]
    }
}

/// Tool call from assistant response
struct ToolCall: Codable, Identifiable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

/// A type-erased Codable value for flexible JSON handling
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
