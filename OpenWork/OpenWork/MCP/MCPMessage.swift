import Foundation

// MARK: - JSON-RPC Base Types

/// MCP uses JSON-RPC 2.0 for all messages
struct MCPMessage: Codable {
    let jsonrpc: String
    let id: MCPRequestID?
    let method: String?
    let params: [String: AnyCodable]?
    let result: AnyCodable?
    let error: MCPError?
    
    init(
        id: MCPRequestID? = nil,
        method: String? = nil,
        params: [String: AnyCodable]? = nil,
        result: AnyCodable? = nil,
        error: MCPError? = nil
    ) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
    
    // Request factory
    static func request(id: Int, method: String, params: [String: Any] = [:]) -> MCPMessage {
        MCPMessage(
            id: .int(id),
            method: method,
            params: params.mapValues { AnyCodable($0) }
        )
    }
    
    // Response factory
    static func response(id: MCPRequestID, result: Any) -> MCPMessage {
        MCPMessage(id: id, result: AnyCodable(result))
    }
    
    // Error response factory
    static func errorResponse(id: MCPRequestID?, code: Int, message: String) -> MCPMessage {
        MCPMessage(id: id, error: MCPError(code: code, message: message, data: nil))
    }
}

/// Request ID can be string or int
enum MCPRequestID: Codable, Equatable {
    case string(String)
    case int(Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(MCPRequestID.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// MCP error object
struct MCPError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?
    
    // Standard JSON-RPC error codes
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}

// MARK: - MCP Protocol Types

/// Tool definition in MCP format
struct MCPToolDefinition: Codable {
    let name: String
    let description: String
    let inputSchema: MCPInputSchema
}

struct MCPInputSchema: Codable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

struct MCPPropertySchema: Codable {
    let type: String
    let description: String?
    let `enum`: [String]?
}

/// Resource in MCP format
struct MCPResource: Codable, Identifiable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?
    
    var id: String { uri }
}

/// Prompt in MCP format
struct MCPPrompt: Codable, Identifiable {
    let name: String
    let description: String?
    let arguments: [MCPPromptArgument]?
    
    var id: String { name }
}

struct MCPPromptArgument: Codable {
    let name: String
    let description: String?
    let required: Bool?
}

// MARK: - Capability Negotiation

struct MCPClientCapabilities: Codable {
    let roots: MCPRootsCapability?
    let sampling: [String: AnyCodable]?
}

struct MCPRootsCapability: Codable {
    let listChanged: Bool?
}

struct MCPServerCapabilities: Codable {
    let tools: MCPToolsCapability?
    let resources: MCPResourcesCapability?
    let prompts: MCPPromptsCapability?
}

struct MCPToolsCapability: Codable {
    let listChanged: Bool?
}

struct MCPResourcesCapability: Codable {
    let subscribe: Bool?
    let listChanged: Bool?
}

struct MCPPromptsCapability: Codable {
    let listChanged: Bool?
}

struct MCPClientInfo: Codable {
    let name: String
    let version: String
}

struct MCPServerInfo: Codable {
    let name: String
    let version: String
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
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
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
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
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
