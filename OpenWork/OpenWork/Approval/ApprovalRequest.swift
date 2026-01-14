import Foundation

/// Represents a pending approval request for a tool execution
struct ApprovalRequest: Identifiable {
    let id: UUID
    let toolID: String
    let toolName: String
    let category: ToolCategory
    let args: [String: Any]
    let workingDirectory: URL
    let timestamp: Date
    
    /// Human-readable description of the action
    var actionDescription: String {
        switch toolID {
        case "write":
            if let path = args["file_path"] as? String {
                return "Write to file: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Write to file"
        case "edit":
            if let path = args["file_path"] as? String {
                return "Edit file: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "Edit file"
        case "bash":
            if let command = args["command"] as? String {
                let truncated = command.count > 50 ? String(command.prefix(50)) + "..." : command
                return "Execute: \(truncated)"
            }
            return "Execute bash command"
        default:
            return "Execute \(toolName)"
        }
    }
    
    /// File path if this is a file operation
    var filePath: String? {
        args["file_path"] as? String
    }
    
    /// New content for write operations
    var newContent: String? {
        args["content"] as? String
    }
    
    /// Old string for edit operations
    var oldString: String? {
        args["old_string"] as? String
    }
    
    /// New string for edit operations
    var newString: String? {
        args["new_string"] as? String
    }
    
    /// Command for bash operations
    var command: String? {
        args["command"] as? String
    }
}

/// The result of an approval request
enum ApprovalDecision {
    case approved(remember: Bool)
    case denied(reason: String?)
    
    var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }
}

/// Details shown in the approval dialog
struct ApprovalDetails {
    let title: String
    let description: String
    let filePath: String?
    let originalContent: String?
    let newContent: String?
    let command: String?
    
    init(from request: ApprovalRequest) {
        self.title = request.actionDescription
        self.description = "Tool: \(request.toolName) (\(request.category.rawValue))"
        self.filePath = request.filePath
        self.command = request.command
        
        // For write operations
        if request.toolID == "write" {
            self.newContent = request.newContent
            // Original content will be loaded separately
            self.originalContent = nil
        } else if request.toolID == "edit" {
            self.originalContent = request.oldString
            self.newContent = request.newString
        } else {
            self.originalContent = nil
            self.newContent = nil
        }
    }
}
