import Foundation

/// Rule for auto-approving certain tool executions
struct ApprovalRule: Identifiable, Codable, Equatable {
    let id: UUID
    let toolID: String
    let pattern: String?  // Optional path pattern or command pattern
    let category: String
    let createdAt: Date
    
    init(id: UUID = UUID(), toolID: String, pattern: String? = nil, category: String, createdAt: Date = Date()) {
        self.id = id
        self.toolID = toolID
        self.pattern = pattern
        self.category = category
        self.createdAt = createdAt
    }
    
    /// Check if this rule matches the given tool and arguments
    func matches(toolID: String, args: [String: Any], workingDirectory: URL) -> Bool {
        guard self.toolID == toolID else { return false }
        
        // If no pattern specified, match all invocations of this tool
        guard let pattern = pattern else { return true }
        
        // Check path patterns for file operations
        if let filePath = args["file_path"] as? String {
            return matchesPattern(path: filePath, pattern: pattern, workingDirectory: workingDirectory)
        }
        
        // Check command patterns for bash
        if let command = args["command"] as? String {
            return command.hasPrefix(pattern) || command.contains(pattern)
        }
        
        return false
    }
    
    private func matchesPattern(path: String, pattern: String, workingDirectory: URL) -> Bool {
        let fullPath = path.hasPrefix("/") ? path : workingDirectory.appendingPathComponent(path).path
        
        // Simple glob-like matching
        if pattern.hasSuffix("/*") {
            let dir = String(pattern.dropLast(2))
            return fullPath.hasPrefix(dir)
        }
        
        if pattern.hasSuffix("/**") {
            let dir = String(pattern.dropLast(3))
            return fullPath.hasPrefix(dir)
        }
        
        // Exact match or prefix match
        return fullPath == pattern || fullPath.hasPrefix(pattern)
    }
}

/// Engine for evaluating auto-approve rules
@MainActor
class ApprovalPolicy: ObservableObject {
    @Published var rules: [ApprovalRule] = []
    
    private let storageKey = "OpenWork.ApprovalRules"
    
    init() {
        loadRules()
    }
    
    /// Evaluate if a tool execution should be auto-approved
    func evaluate(toolID: String, args: [String: Any], workingDirectory: URL) -> ApprovalDecision? {
        for rule in rules {
            if rule.matches(toolID: toolID, args: args, workingDirectory: workingDirectory) {
                return .approved(remember: false)
            }
        }
        return nil
    }
    
    /// Add a new auto-approve rule
    func addRule(_ rule: ApprovalRule) {
        // Avoid duplicates
        if !rules.contains(where: { $0.toolID == rule.toolID && $0.pattern == rule.pattern }) {
            rules.append(rule)
            saveRules()
        }
    }
    
    /// Add rule from an approval request
    func addRule(from request: ApprovalRequest) {
        let pattern: String?
        
        // Create pattern based on tool type
        switch request.toolID {
        case "write", "edit", "read":
            // Use directory pattern for file operations
            if let filePath = request.filePath {
                let url = URL(fileURLWithPath: filePath)
                pattern = url.deletingLastPathComponent().path + "/*"
            } else {
                pattern = nil
            }
        case "bash":
            // Use command prefix for bash
            if let command = request.command {
                // Extract first word/command
                let firstWord = command.split(separator: " ").first.map(String.init) ?? command
                pattern = firstWord
            } else {
                pattern = nil
            }
        default:
            pattern = nil
        }
        
        let rule = ApprovalRule(
            toolID: request.toolID,
            pattern: pattern,
            category: request.category.rawValue
        )
        
        addRule(rule)
    }
    
    /// Remove a rule
    func removeRule(_ rule: ApprovalRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    /// Remove all rules
    func clearRules() {
        rules.removeAll()
        saveRules()
    }
    
    // MARK: - Persistence
    
    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ApprovalRule].self, from: data) else {
            return
        }
        rules = decoded
    }
    
    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
