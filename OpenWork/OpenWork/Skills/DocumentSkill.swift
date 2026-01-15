import Foundation

/// Skill for creating documents, presentations, and reports
struct DocumentSkill: Skill {
    let id = "document"
    let name = "Document Creator"
    let description = "Create professional documents, presentations, reports, and formatted content"
    let icon = "doc.richtext"
    let category: SkillCategory = .productivity
    let enabledByDefault = true

    var systemPromptAddition: String {
        """
        ### Document Creation Skill
        You have enhanced document creation capabilities:

        1. **Document Types**: You can create:
           - Markdown documents (.md)
           - HTML documents and web pages
           - Plain text files
           - JSON/YAML configuration files
           - CSV data files

        2. **Formatting Guidelines**:
           - Use clear hierarchical headings
           - Include tables for structured data
           - Add code blocks with syntax highlighting
           - Use bullet points for lists
           - Include metadata when appropriate

        3. **Best Practices**:
           - Start with a clear title and purpose
           - Use consistent formatting throughout
           - Include a table of contents for long documents
           - Add sections for executive summary when needed
           - Use diagrams described in text or ASCII art

        4. **Templates Available**:
           - Technical documentation
           - Project proposals
           - Meeting notes
           - Status reports
           - API documentation
           - README files

        When asked to create documents, use the appropriate file format and follow professional formatting standards.
        """
    }

    var tools: [any Tool] {
        [DocumentTool()]
    }
}

/// Tool for document-specific operations
struct DocumentTool: Tool {
    let id = "document"
    let name = "Document"
    let description = "Create and format documents with templates and structured content"
    let category: ToolCategory = .write
    let requiresApproval: Bool = true

    var inputSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "action": PropertySchema(
                    type: "string",
                    description: "Document action: create, template, export",
                    enumValues: ["create", "template", "export"]
                ),
                "type": PropertySchema(
                    type: "string",
                    description: "Document type: markdown, html, readme, proposal, report, notes",
                    enumValues: ["markdown", "html", "readme", "proposal", "report", "notes"]
                ),
                "title": PropertySchema(
                    type: "string",
                    description: "Document title"
                ),
                "content": PropertySchema(
                    type: "string",
                    description: "Document content or outline"
                ),
                "path": PropertySchema(
                    type: "string",
                    description: "Output file path"
                ),
                "metadata": PropertySchema(
                    type: "object",
                    description: "Optional metadata (author, date, version)"
                )
            ],
            required: ["action"]
        )
    }

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let action = args["action"] as? String else {
            return ToolResult.error("'action' parameter is required", title: "Document Error")
        }

        switch action.lowercased() {
        case "create":
            return try await createDocument(args: args, context: context)
        case "template":
            return generateTemplate(args: args)
        case "export":
            return try await exportDocument(args: args, context: context)
        default:
            return ToolResult.error("Unknown action: \(action)", title: "Document Error")
        }
    }

    private func createDocument(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let content = args["content"] as? String else {
            return ToolResult.error("'content' parameter is required for create action", title: "Document Error")
        }

        guard let path = args["path"] as? String else {
            return ToolResult.error("'path' parameter is required for create action", title: "Document Error")
        }

        let title = args["title"] as? String ?? "Untitled Document"
        let docType = args["type"] as? String ?? "markdown"

        // Generate document based on type
        let formattedContent = formatDocument(
            type: docType,
            title: title,
            content: content,
            metadata: args["metadata"] as? [String: Any]
        )

        // Write to file
        let fileURL: URL
        if path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = context.workingDirectory.appendingPathComponent(path)
        }

        do {
            try formattedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult(
                title: "Document Created",
                output: "Created \(docType) document: \(fileURL.path)\nTitle: \(title)\nSize: \(formattedContent.count) characters",
                didChange: true,
                normalizedKey: "document:\(fileURL.path)"
            )
        } catch {
            return ToolResult.error("Failed to write document: \(error.localizedDescription)", title: "Write Error")
        }
    }

    private func generateTemplate(args: [String: Any]) -> ToolResult {
        let docType = args["type"] as? String ?? "markdown"
        let title = args["title"] as? String ?? "Document Title"

        let template: String
        switch docType.lowercased() {
        case "readme":
            template = readmeTemplate(title: title)
        case "proposal":
            template = proposalTemplate(title: title)
        case "report":
            template = reportTemplate(title: title)
        case "notes":
            template = meetingNotesTemplate(title: title)
        default:
            template = markdownTemplate(title: title)
        }

        return ToolResult.success(template, title: "Template Generated", didChange: false)
    }

    private func exportDocument(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        // Export functionality - convert between formats
        guard let sourcePath = args["path"] as? String else {
            return ToolResult.error("'path' parameter is required for export action", title: "Document Error")
        }

        let sourceURL: URL
        if sourcePath.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: sourcePath)
        } else {
            sourceURL = context.workingDirectory.appendingPathComponent(sourcePath)
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return ToolResult.error("Source file not found: \(sourcePath)", title: "File Not Found")
        }

        let content = try String(contentsOf: sourceURL, encoding: .utf8)
        let targetType = args["type"] as? String ?? "html"

        if targetType == "html" {
            // Simple markdown to HTML conversion
            let html = convertMarkdownToHTML(content)
            let outputPath = sourceURL.deletingPathExtension().appendingPathExtension("html")
            try html.write(to: outputPath, atomically: true, encoding: .utf8)
            return ToolResult.success(
                "Exported to HTML: \(outputPath.path)",
                title: "Export Complete",
                didChange: true
            )
        }

        return ToolResult.error("Unsupported export type: \(targetType)", title: "Export Error")
    }

    // MARK: - Formatting

    private func formatDocument(type: String, title: String, content: String, metadata: [String: Any]?) -> String {
        switch type.lowercased() {
        case "html":
            return formatAsHTML(title: title, content: content, metadata: metadata)
        default:
            return formatAsMarkdown(title: title, content: content, metadata: metadata)
        }
    }

    private func formatAsMarkdown(title: String, content: String, metadata: [String: Any]?) -> String {
        var doc = "# \(title)\n\n"

        if let meta = metadata {
            if let author = meta["author"] as? String {
                doc += "**Author:** \(author)  \n"
            }
            if let date = meta["date"] as? String {
                doc += "**Date:** \(date)  \n"
            }
            if let version = meta["version"] as? String {
                doc += "**Version:** \(version)  \n"
            }
            doc += "\n---\n\n"
        }

        doc += content
        return doc
    }

    private func formatAsHTML(title: String, content: String, metadata: [String: Any]?) -> String {
        var meta = ""
        if let m = metadata {
            if let author = m["author"] as? String {
                meta += "<meta name=\"author\" content=\"\(author)\">\n"
            }
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(meta)
            <title>\(title)</title>
            <style>
                body { font-family: system-ui, -apple-system, sans-serif; max-width: 800px; margin: 0 auto; padding: 2rem; }
                h1 { border-bottom: 2px solid #333; padding-bottom: 0.5rem; }
            </style>
        </head>
        <body>
            <h1>\(title)</h1>
            \(convertMarkdownToHTML(content))
        </body>
        </html>
        """
    }

    private func convertMarkdownToHTML(_ markdown: String) -> String {
        var html = markdown

        // Headers
        html = html.replacingOccurrences(of: "(?m)^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "(?m)^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // Bold and italic
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)

        // Paragraphs
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = "<p>" + html + "</p>"

        return html
    }

    // MARK: - Templates

    private func markdownTemplate(title: String) -> String {
        """
        # \(title)

        ## Overview

        Brief description of this document.

        ## Details

        Main content goes here.

        ## Conclusion

        Summary and next steps.
        """
    }

    private func readmeTemplate(title: String) -> String {
        """
        # \(title)

        Brief description of the project.

        ## Installation

        ```bash
        # Installation commands
        ```

        ## Usage

        ```bash
        # Usage examples
        ```

        ## Configuration

        Describe configuration options.

        ## Contributing

        Guidelines for contributing.

        ## License

        License information.
        """
    }

    private func proposalTemplate(title: String) -> String {
        """
        # \(title)

        **Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))

        ## Executive Summary

        Brief overview of the proposal.

        ## Problem Statement

        What problem does this solve?

        ## Proposed Solution

        Detailed solution description.

        ## Timeline

        | Phase | Duration | Deliverables |
        |-------|----------|--------------|
        | Phase 1 | 2 weeks | ... |
        | Phase 2 | 2 weeks | ... |

        ## Resources Required

        - Resource 1
        - Resource 2

        ## Risks and Mitigations

        | Risk | Impact | Mitigation |
        |------|--------|------------|
        | Risk 1 | High | ... |

        ## Success Metrics

        How will success be measured?

        ## Next Steps

        Immediate actions required.
        """
    }

    private func reportTemplate(title: String) -> String {
        """
        # \(title)

        **Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))

        ## Summary

        Key findings and highlights.

        ## Metrics

        | Metric | Value | Change |
        |--------|-------|--------|
        | ... | ... | ... |

        ## Analysis

        Detailed analysis of the data.

        ## Recommendations

        1. Recommendation 1
        2. Recommendation 2

        ## Appendix

        Supporting data and references.
        """
    }

    private func meetingNotesTemplate(title: String) -> String {
        """
        # \(title)

        **Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))

        ## Attendees

        - [ ] Name 1
        - [ ] Name 2

        ## Agenda

        1. Topic 1
        2. Topic 2

        ## Discussion

        ### Topic 1

        Notes...

        ### Topic 2

        Notes...

        ## Action Items

        | Item | Owner | Due Date |
        |------|-------|----------|
        | ... | ... | ... |

        ## Next Meeting

        Date and topics for next meeting.
        """
    }
}
