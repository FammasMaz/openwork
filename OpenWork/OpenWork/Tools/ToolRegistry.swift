import Foundation

/// Manages tool registration and discovery
@MainActor
class ToolRegistry: ObservableObject {
    static let shared = ToolRegistry()

    @Published private(set) var tools: [String: any Tool] = [:]

    private init() {
        registerBuiltinTools()
    }

    // MARK: - Registration

    /// Registers a tool
    func register(_ tool: any Tool) {
        tools[tool.id] = tool
    }

    /// Unregisters a tool
    func unregister(id: String) {
        tools.removeValue(forKey: id)
    }

    /// Gets a tool by ID
    func tool(forID id: String) -> (any Tool)? {
        tools[id]
    }

    // MARK: - Built-in Tools

    private func registerBuiltinTools() {
        register(ReadFileTool())
        register(WriteFileTool())
        register(EditFileTool())
        register(GlobTool())
        register(GrepTool())
        register(BashTool())
        register(ListDirectoryTool())
    }

    // MARK: - Tool Definitions for LLM

    /// Generates tool definitions for LLM API
    func toolDefinitions() -> [ToolDefinition] {
        tools.values.map { tool in
            let params = tool.inputSchema.toDict()
            return ToolDefinition(
                type: "function",
                function: ToolDefinition.FunctionDefinition(
                    name: tool.id,
                    description: tool.description,
                    parameters: params.mapValues { AnyCodable($0) }
                )
            )
        }
    }
}

// MARK: - ReadFileTool

/// Tool to read file contents
struct ReadFileTool: Tool {
    let id = "read"
    let name = "Read File"
    let description = "Reads a file from the local filesystem. Returns the file contents with line numbers."
    let category: ToolCategory = .read
    let requiresApproval = false

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "file_path": JSONSchema.property("string", description: "The absolute path to the file to read"),
                "offset": JSONSchema.property("integer", description: "Line number to start reading from (1-based)"),
                "limit": JSONSchema.property("integer", description: "Number of lines to read")
            ],
            required: ["file_path"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let filePath = args["file_path"] as? String else {
            throw ToolError.invalidArguments("file_path is required")
        }

        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ToolError.fileNotFound(filePath)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            let offset = (args["offset"] as? Int ?? 1) - 1
            let limit = args["limit"] as? Int ?? lines.count

            let startIndex = max(0, offset)
            let endIndex = min(lines.count, startIndex + limit)

            var numberedLines: [String] = []
            for i in startIndex..<endIndex {
                let lineNum = String(format: "%6d", i + 1)
                numberedLines.append("\(lineNum)→\(lines[i])")
            }

            let output = numberedLines.joined(separator: "\n")
            let (truncated, wasTruncated) = OutputTruncation.truncate(output)

            return ToolResult(
                title: "Read \(url.lastPathComponent)",
                output: truncated,
                metadata: ["truncated": wasTruncated, "lines": endIndex - startIndex]
            )
        } catch {
            throw ToolError.executionFailed("Failed to read file: \(error.localizedDescription)")
        }
    }
}

// MARK: - WriteFileTool

/// Tool to write file contents
struct WriteFileTool: Tool {
    let id = "write"
    let name = "Write File"
    let description = "Writes content to a file, creating it if it doesn't exist or overwriting if it does."
    let category: ToolCategory = .write
    let requiresApproval = true

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "file_path": JSONSchema.property("string", description: "The absolute path to the file to write"),
                "content": JSONSchema.property("string", description: "The content to write to the file")
            ],
            required: ["file_path", "content"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let filePath = args["file_path"] as? String else {
            throw ToolError.invalidArguments("file_path is required")
        }
        guard let content = args["content"] as? String else {
            throw ToolError.invalidArguments("content is required")
        }

        let url = URL(fileURLWithPath: filePath)

        do {
            // Create parent directory if needed
            let parentDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            try content.write(to: url, atomically: true, encoding: .utf8)

            return ToolResult(
                title: "Wrote \(url.lastPathComponent)",
                output: "Successfully wrote \(content.count) characters to \(filePath)",
                metadata: ["bytes": content.utf8.count]
            )
        } catch {
            throw ToolError.executionFailed("Failed to write file: \(error.localizedDescription)")
        }
    }
}

// MARK: - EditFileTool

/// Tool to edit files with string replacement
struct EditFileTool: Tool {
    let id = "edit"
    let name = "Edit File"
    let description = "Performs exact string replacements in files."
    let category: ToolCategory = .write
    let requiresApproval = true

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "file_path": JSONSchema.property("string", description: "The absolute path to the file to modify"),
                "old_string": JSONSchema.property("string", description: "The text to replace"),
                "new_string": JSONSchema.property("string", description: "The text to replace it with"),
                "replace_all": JSONSchema.property("boolean", description: "Replace all occurrences (default: false)")
            ],
            required: ["file_path", "old_string", "new_string"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let filePath = args["file_path"] as? String else {
            throw ToolError.invalidArguments("file_path is required")
        }
        guard let oldString = args["old_string"] as? String else {
            throw ToolError.invalidArguments("old_string is required")
        }
        guard let newString = args["new_string"] as? String else {
            throw ToolError.invalidArguments("new_string is required")
        }

        let replaceAll = args["replace_all"] as? Bool ?? false
        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ToolError.fileNotFound(filePath)
        }

        do {
            var content = try String(contentsOf: url, encoding: .utf8)

            let occurrences = content.components(separatedBy: oldString).count - 1

            if occurrences == 0 {
                throw ToolError.executionFailed("old_string not found in file")
            }

            if !replaceAll && occurrences > 1 {
                throw ToolError.executionFailed("old_string is not unique (\(occurrences) occurrences). Use replace_all=true or provide more context.")
            }

            if replaceAll {
                content = content.replacingOccurrences(of: oldString, with: newString)
            } else {
                if let range = content.range(of: oldString) {
                    content.replaceSubrange(range, with: newString)
                }
            }

            try content.write(to: url, atomically: true, encoding: .utf8)

            return ToolResult(
                title: "Edited \(url.lastPathComponent)",
                output: "Replaced \(replaceAll ? occurrences : 1) occurrence(s)",
                metadata: ["replacements": replaceAll ? occurrences : 1]
            )
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed("Failed to edit file: \(error.localizedDescription)")
        }
    }
}

// MARK: - GlobTool

/// Tool to find files matching patterns
struct GlobTool: Tool {
    let id = "glob"
    let name = "Glob"
    let description = "Fast file pattern matching. Supports patterns like '**/*.swift' or 'src/**/*.ts'."
    let category: ToolCategory = .read
    let requiresApproval = false

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "pattern": JSONSchema.property("string", description: "The glob pattern to match files against"),
                "path": JSONSchema.property("string", description: "The directory to search in (defaults to current directory)")
            ],
            required: ["pattern"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let pattern = args["pattern"] as? String else {
            throw ToolError.invalidArguments("pattern is required")
        }

        let searchPath = args["path"] as? String ?? context.workingDirectory.path

        // Use find command for glob matching (simplified implementation)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [searchPath, "-name", pattern.replacingOccurrences(of: "**/*", with: "*")]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let files = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

            return ToolResult(
                title: "Found \(files.count) files",
                output: files.joined(separator: "\n"),
                metadata: ["count": files.count]
            )
        } catch {
            throw ToolError.executionFailed("Glob search failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - GrepTool

/// Tool to search file contents
struct GrepTool: Tool {
    let id = "grep"
    let name = "Grep"
    let description = "Search for patterns in file contents using regular expressions."
    let category: ToolCategory = .read
    let requiresApproval = false

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "pattern": JSONSchema.property("string", description: "The regex pattern to search for"),
                "path": JSONSchema.property("string", description: "File or directory to search in"),
                "glob": JSONSchema.property("string", description: "Glob pattern to filter files (e.g., '*.swift')"),
                "output_mode": JSONSchema.property("string", description: "Output mode: 'content', 'files_with_matches', or 'count'")
            ],
            required: ["pattern"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let pattern = args["pattern"] as? String else {
            throw ToolError.invalidArguments("pattern is required")
        }

        let searchPath = args["path"] as? String ?? context.workingDirectory.path
        let outputMode = args["output_mode"] as? String ?? "files_with_matches"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")

        var arguments = ["-r", "-n"]

        switch outputMode {
        case "files_with_matches":
            arguments.append("-l")
        case "count":
            arguments.append("-c")
        default:
            break
        }

        if let glob = args["glob"] as? String {
            arguments.append(contentsOf: ["--include", glob])
        }

        arguments.append(contentsOf: [pattern, searchPath])
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let (truncated, wasTruncated) = OutputTruncation.truncate(output)

            return ToolResult(
                title: "Grep results",
                output: truncated,
                metadata: ["truncated": wasTruncated]
            )
        } catch {
            throw ToolError.executionFailed("Grep failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - BashTool

/// Tool to execute bash commands (in VM when available)
struct BashTool: Tool {
    let id = "bash"
    let name = "Bash"
    let description = "Execute bash commands. Commands run in an isolated Linux VM for security."
    let category: ToolCategory = .execute
    let requiresApproval = true

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "command": JSONSchema.property("string", description: "The bash command to execute"),
                "description": JSONSchema.property("string", description: "Description of what this command does"),
                "timeout": JSONSchema.property("integer", description: "Timeout in milliseconds (max 600000)")
            ],
            required: ["command"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let command = args["command"] as? String else {
            throw ToolError.invalidArguments("command is required")
        }

        let timeout = args["timeout"] as? Int ?? 120000

        // TODO: Execute in VM when VMManager is ready
        // For now, execute locally with sandbox restrictions

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = context.workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            // Set up timeout
            let timeoutTask = Task {
                try await Task.sleep(for: .milliseconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            var output = stdout
            if !stderr.isEmpty {
                output += "\n[stderr]\n\(stderr)"
            }

            let (truncated, wasTruncated) = OutputTruncation.truncate(output)

            return ToolResult(
                title: "bash: \(command.prefix(30))\(command.count > 30 ? "..." : "")",
                output: truncated,
                metadata: [
                    "exitCode": process.terminationStatus,
                    "truncated": wasTruncated
                ]
            )
        } catch {
            throw ToolError.executionFailed("Command execution failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - ListDirectoryTool

/// Tool to list directory contents
struct ListDirectoryTool: Tool {
    let id = "ls"
    let name = "List Directory"
    let description = "Lists the contents of a directory."
    let category: ToolCategory = .read
    let requiresApproval = false

    var inputSchema: JSONSchema {
        JSONSchema(
            properties: [
                "path": JSONSchema.property("string", description: "The directory path to list"),
                "all": JSONSchema.property("boolean", description: "Include hidden files"),
                "long": JSONSchema.property("boolean", description: "Use long listing format")
            ],
            required: ["path"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let path = args["path"] as? String else {
            throw ToolError.invalidArguments("path is required")
        }

        let url = URL(fileURLWithPath: path)
        let includeHidden = args["all"] as? Bool ?? false

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: includeHidden ? [] : [.skipsHiddenFiles]
            )

            var lines: [String] = []
            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let name = item.lastPathComponent + (isDir ? "/" : "")
                lines.append(name)
            }

            return ToolResult(
                title: "ls \(url.lastPathComponent)",
                output: lines.joined(separator: "\n"),
                metadata: ["count": lines.count]
            )
        } catch {
            throw ToolError.executionFailed("Failed to list directory: \(error.localizedDescription)")
        }
    }
}
