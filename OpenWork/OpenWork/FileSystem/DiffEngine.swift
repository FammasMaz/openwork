import Foundation

/// Represents a line in a diff
enum DiffLine: Equatable {
    case context(lineNum: Int, text: String)
    case added(lineNum: Int, text: String)
    case removed(lineNum: Int, text: String)
    
    var text: String {
        switch self {
        case .context(_, let text), .added(_, let text), .removed(_, let text):
            return text
        }
    }
    
    var lineNumber: Int {
        switch self {
        case .context(let num, _), .added(let num, _), .removed(let num, _):
            return num
        }
    }
    
    var isAddition: Bool {
        if case .added = self { return true }
        return false
    }
    
    var isRemoval: Bool {
        if case .removed = self { return true }
        return false
    }
    
    var isContext: Bool {
        if case .context = self { return true }
        return false
    }
}

/// Result of a diff operation
struct DiffResult {
    let lines: [DiffLine]
    let additions: Int
    let deletions: Int
    let isIdentical: Bool
    
    init(lines: [DiffLine]) {
        self.lines = lines
        self.additions = lines.filter { $0.isAddition }.count
        self.deletions = lines.filter { $0.isRemoval }.count
        self.isIdentical = additions == 0 && deletions == 0
    }
    
    static let empty = DiffResult(lines: [])
}

/// Engine for computing diffs between strings
enum DiffEngine {
    
    /// Generate a unified diff between original and modified content
    static func diff(original: String, modified: String, contextLines: Int = 3) -> DiffResult {
        let originalLines = original.components(separatedBy: "\n")
        let modifiedLines = modified.components(separatedBy: "\n")
        
        // Compute LCS-based diff
        let diffLines = computeDiff(originalLines, modifiedLines, contextLines: contextLines)
        return DiffResult(lines: diffLines)
    }
    
    /// Compute diff for a file edit (old string -> new string replacement)
    static func diffEdit(
        originalContent: String,
        oldString: String,
        newString: String,
        contextLines: Int = 3
    ) -> DiffResult {
        let modified = originalContent.replacingOccurrences(of: oldString, with: newString)
        return diff(original: originalContent, modified: modified, contextLines: contextLines)
    }
    
    // MARK: - LCS-based Diff Algorithm
    
    private static func computeDiff(
        _ original: [String],
        _ modified: [String],
        contextLines: Int
    ) -> [DiffLine] {
        // Compute LCS (Longest Common Subsequence) table
        let m = original.count
        let n = modified.count
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if original[i - 1] == modified[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        
        // Backtrack to find the diff
        var result: [DiffLine] = []
        var i = m
        var j = n
        var originalLineNum = m
        var modifiedLineNum = n
        
        var tempResult: [DiffLine] = []
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && original[i - 1] == modified[j - 1] {
                // Common line
                tempResult.append(.context(lineNum: originalLineNum, text: original[i - 1]))
                i -= 1
                j -= 1
                originalLineNum -= 1
                modifiedLineNum -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                // Addition
                tempResult.append(.added(lineNum: modifiedLineNum, text: modified[j - 1]))
                j -= 1
                modifiedLineNum -= 1
            } else if i > 0 {
                // Deletion
                tempResult.append(.removed(lineNum: originalLineNum, text: original[i - 1]))
                i -= 1
                originalLineNum -= 1
            }
        }
        
        // Reverse to get correct order
        result = tempResult.reversed()
        
        // Filter to show only changes with context
        return filterWithContext(result, contextLines: contextLines)
    }
    
    private static func filterWithContext(_ lines: [DiffLine], contextLines: Int) -> [DiffLine] {
        guard contextLines > 0 else { return lines.filter { !$0.isContext } }
        
        // Find indices of changed lines
        var changedIndices = Set<Int>()
        for (index, line) in lines.enumerated() {
            if !line.isContext {
                changedIndices.insert(index)
            }
        }
        
        // Include context lines around changes
        var includedIndices = Set<Int>()
        for changedIndex in changedIndices {
            for offset in -contextLines...contextLines {
                let index = changedIndex + offset
                if index >= 0 && index < lines.count {
                    includedIndices.insert(index)
                }
            }
        }
        
        // Build filtered result
        var result: [DiffLine] = []
        let sortedIndices = includedIndices.sorted()
        
        for (i, index) in sortedIndices.enumerated() {
            // Add separator if there's a gap
            if i > 0 && sortedIndices[i - 1] < index - 1 {
                result.append(.context(lineNum: -1, text: "..."))
            }
            result.append(lines[index])
        }
        
        return result
    }
    
    // MARK: - Utilities
    
    /// Check if two strings are identical
    static func areIdentical(_ a: String, _ b: String) -> Bool {
        return a == b
    }
    
    /// Get a summary of changes
    static func summary(original: String, modified: String) -> String {
        let result = diff(original: original, modified: modified)
        if result.isIdentical {
            return "No changes"
        }
        return "\(result.additions) addition\(result.additions == 1 ? "" : "s"), \(result.deletions) deletion\(result.deletions == 1 ? "" : "s")"
    }
}
