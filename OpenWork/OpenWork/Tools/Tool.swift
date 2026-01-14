import Foundation

/// Result of tool execution
struct ToolResult {
    let title: String
    let output: String
    var metadata: [String: Any]
    var attachments: [URL]
    
    /// Whether the tool actually changed something (for loop detection)
    /// - true: Something was modified (file written, command executed successfully)
    /// - false: No change occurred (file already had same content, command failed, read-only operation)
    var didChange: Bool
    
    /// Normalized key for loop detection (e.g., "write:/path/to/file")
    var normalizedKey: String?

    init(
        title: String,
        output: String,
        metadata: [String: Any] = [:],
        attachments: [URL] = [],
        didChange: Bool = false,
        normalizedKey: String? = nil
    ) {
        self.title = title
        self.output = output
        self.metadata = metadata
        self.attachments = attachments
        self.didChange = didChange
        self.normalizedKey = normalizedKey
    }

    /// Creates a success result
    static func success(_ output: String, title: String = "Success", didChange: Bool = true) -> ToolResult {
        ToolResult(title: title, output: output, didChange: didChange)
    }

    /// Creates an error result
    static func error(_ message: String, title: String = "Error") -> ToolResult {
        ToolResult(title: title, output: message, metadata: ["error": true], didChange: false)
    }
}

/// Context provided to tools during execution
struct ToolContext {
    let sessionID: String
    let messageID: String
    let workingDirectory: URL
    let abort: () -> Bool
    weak var vmManager: VMManager?

    /// Check if execution should be aborted
    var shouldAbort: Bool {
        abort()
    }
}

/// Property schema for JSON Schema - using class to allow recursive structure
final class PropertySchema {
    let type: String
    var description: String?
    var items: PropertySchema?
    var enumValues: [String]?

    init(
        type: String,
        description: String? = nil,
        items: PropertySchema? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.items = items
        self.enumValues = enumValues
    }

    /// Convert to dictionary for JSON encoding
    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type]
        if let desc = description {
            dict["description"] = desc
        }
        if let items = items {
            dict["items"] = items.toDict()
        }
        if let enumVals = enumValues {
            dict["enum"] = enumVals
        }
        return dict
    }
}

/// JSON Schema for tool parameters
struct JSONSchema {
    let type: String
    var properties: [String: PropertySchema]?
    var required: [String]?
    var additionalProperties: Bool?

    init(
        type: String = "object",
        properties: [String: PropertySchema]? = nil,
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = false
    }

    /// Creates a simple property schema
    static func property(
        _ type: String,
        description: String? = nil
    ) -> PropertySchema {
        PropertySchema(type: type, description: description)
    }

    /// Creates an array property schema
    static func array(
        of itemType: String,
        description: String? = nil
    ) -> PropertySchema {
        PropertySchema(
            type: "array",
            description: description,
            items: PropertySchema(type: itemType)
        )
    }

    /// Convert to dictionary for JSON encoding
    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type]

        if let props = properties {
            var propsDict: [String: Any] = [:]
            for (key, value) in props {
                propsDict[key] = value.toDict()
            }
            dict["properties"] = propsDict
        }

        if let req = required {
            dict["required"] = req
        }

        return dict
    }
}

/// Protocol for all tools
protocol Tool {
    /// Unique identifier for this tool
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this tool does
    var description: String { get }

    /// JSON Schema for input parameters
    var inputSchema: JSONSchema { get }

    /// Whether this tool requires user approval before execution
    var requiresApproval: Bool { get }

    /// Category of this tool for permission grouping
    var category: ToolCategory { get }

    /// Execute the tool with given arguments
    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult
}

/// Categories for tool permissions
enum ToolCategory: String, CaseIterable {
    case read = "read"
    case write = "write"
    case execute = "execute"
    case network = "network"
    case system = "system"
}

/// Built-in tool implementations
extension Tool {
    var requiresApproval: Bool { true }
    var category: ToolCategory { .read }
}

/// Errors that can occur during tool execution
enum ToolError: LocalizedError {
    case invalidArguments(String)
    case executionFailed(String)
    case timeout
    case aborted
    case permissionDenied(String)
    case fileNotFound(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg):
            return "Invalid arguments: \(msg)"
        case .executionFailed(let msg):
            return "Execution failed: \(msg)"
        case .timeout:
            return "Tool execution timed out"
        case .aborted:
            return "Execution was aborted"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

/// Truncation utilities for tool output
enum OutputTruncation {
    /// Maximum output length before truncation
    static let maxOutputLength = 30000

    /// Truncates output if it exceeds the maximum length
    static func truncate(_ output: String, limit: Int = maxOutputLength) -> (content: String, truncated: Bool) {
        if output.count <= limit {
            return (output, false)
        }

        let halfLimit = limit / 2
        let prefix = String(output.prefix(halfLimit))
        let suffix = String(output.suffix(halfLimit))
        let truncatedCount = output.count - limit

        let truncatedOutput = """
        \(prefix)

        ... [\(truncatedCount) characters truncated] ...

        \(suffix)
        """

        return (truncatedOutput, true)
    }
}
