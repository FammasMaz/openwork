import Foundation

/// Browser automation tool for agent use
struct BrowserTool: Tool {
    let id = "browser"
    let name = "Browser"
    let description = "Automate web browser interactions - navigate, click, type, screenshot, and extract content from web pages"
    let category: ToolCategory = .network
    let requiresApproval: Bool = true

    var inputSchema: JSONSchema {
        JSONSchema(
            type: "object",
            properties: [
                "action": PropertySchema(
                    type: "string",
                    description: "The browser action to perform: launch, navigate, click, type, screenshot, content, evaluate, wait, close",
                    enumValues: ["launch", "navigate", "click", "type", "screenshot", "content", "evaluate", "wait", "close"]
                ),
                "url": PropertySchema(
                    type: "string",
                    description: "URL to navigate to (for navigate action)"
                ),
                "selector": PropertySchema(
                    type: "string",
                    description: "CSS selector for element interactions (click, type, wait actions)"
                ),
                "text": PropertySchema(
                    type: "string",
                    description: "Text to type (for type action)"
                ),
                "script": PropertySchema(
                    type: "string",
                    description: "JavaScript to evaluate (for evaluate action)"
                ),
                "headless": PropertySchema(
                    type: "boolean",
                    description: "Run browser in headless mode (default: true)"
                ),
                "fullPage": PropertySchema(
                    type: "boolean",
                    description: "Capture full page screenshot (default: false)"
                ),
                "timeout": PropertySchema(
                    type: "number",
                    description: "Timeout in milliseconds for wait operations (default: 30000)"
                )
            ],
            required: ["action"]
        )
    }

    // Track active session
    private static var activeSession: BrowserSession?

    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let action = args["action"] as? String else {
            return ToolResult.error("'action' parameter is required", title: "Browser Error")
        }

        let browserManager = await BrowserManager.shared

        switch action.lowercased() {
        case "launch":
            return try await launchBrowser(manager: browserManager, args: args)

        case "navigate":
            return try await navigateTo(manager: browserManager, args: args)

        case "click":
            return try await clickElement(manager: browserManager, args: args)

        case "type":
            return try await typeText(manager: browserManager, args: args)

        case "screenshot":
            return try await takeScreenshot(manager: browserManager, args: args)

        case "content":
            return try await getPageContent(manager: browserManager)

        case "evaluate":
            return try await evaluateScript(manager: browserManager, args: args)

        case "wait":
            return try await waitForElement(manager: browserManager, args: args)

        case "close":
            return try await closeBrowser(manager: browserManager)

        default:
            return ToolResult.error(
                "Unknown action: \(action). Valid actions: launch, navigate, click, type, screenshot, content, evaluate, wait, close",
                title: "Browser Error"
            )
        }
    }

    // MARK: - Actions

    private func launchBrowser(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        // Start server if not running
        if await !manager.isServerRunning {
            do {
                try await manager.startServer()
            } catch {
                return ToolResult.error(
                    "Failed to start browser server: \(error.localizedDescription)\n\nMake sure Playwright is installed: npm install -g playwright-core",
                    title: "Browser Launch Failed"
                )
            }
        }

        let headless = args["headless"] as? Bool ?? true

        do {
            let session = try await manager.launchBrowser(headless: headless)
            BrowserTool.activeSession = session
            return ToolResult.success(
                "Browser launched successfully (headless: \(headless))\nSession ID: \(session.id)",
                title: "Browser Launched",
                didChange: true
            )
        } catch {
            return ToolResult.error("Failed to launch browser: \(error.localizedDescription)", title: "Browser Launch Failed")
        }
    }

    private func navigateTo(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        guard let url = args["url"] as? String else {
            return ToolResult.error("'url' parameter is required for navigate action", title: "Browser Error")
        }

        do {
            try await manager.navigate(session: session, url: url)
            return ToolResult.success("Navigated to: \(url)", title: "Navigation Complete", didChange: true)
        } catch {
            return ToolResult.error("Navigation failed: \(error.localizedDescription)", title: "Navigation Failed")
        }
    }

    private func clickElement(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        guard let selector = args["selector"] as? String else {
            return ToolResult.error("'selector' parameter is required for click action", title: "Browser Error")
        }

        do {
            try await manager.click(session: session, selector: selector)
            return ToolResult.success("Clicked element: \(selector)", title: "Click Complete", didChange: true)
        } catch {
            return ToolResult.error("Click failed: \(error.localizedDescription)", title: "Click Failed")
        }
    }

    private func typeText(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        guard let selector = args["selector"] as? String else {
            return ToolResult.error("'selector' parameter is required for type action", title: "Browser Error")
        }

        guard let text = args["text"] as? String else {
            return ToolResult.error("'text' parameter is required for type action", title: "Browser Error")
        }

        do {
            try await manager.type(session: session, selector: selector, text: text)
            return ToolResult.success("Typed text into: \(selector)", title: "Type Complete", didChange: true)
        } catch {
            return ToolResult.error("Type failed: \(error.localizedDescription)", title: "Type Failed")
        }
    }

    private func takeScreenshot(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        let fullPage = args["fullPage"] as? Bool ?? false

        do {
            let data = try await manager.screenshot(session: session, fullPage: fullPage)

            // Save screenshot to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "screenshot_\(UUID().uuidString).png"
            let fileURL = tempDir.appendingPathComponent(filename)
            try data.write(to: fileURL)

            return ToolResult(
                title: "Screenshot Captured",
                output: "Screenshot saved to: \(fileURL.path)\nSize: \(data.count) bytes",
                attachments: [fileURL],
                didChange: true
            )
        } catch {
            return ToolResult.error("Screenshot failed: \(error.localizedDescription)", title: "Screenshot Failed")
        }
    }

    private func getPageContent(manager: BrowserManager) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        do {
            let content = try await manager.getContent(session: session)

            // Truncate if too long
            let (truncatedContent, wasTruncated) = OutputTruncation.truncate(content)

            var output = truncatedContent
            if wasTruncated {
                output += "\n\n[Content truncated - \(content.count) total characters]"
            }

            return ToolResult.success(output, title: "Page Content", didChange: false)
        } catch {
            return ToolResult.error("Failed to get content: \(error.localizedDescription)", title: "Content Error")
        }
    }

    private func evaluateScript(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        guard let script = args["script"] as? String else {
            return ToolResult.error("'script' parameter is required for evaluate action", title: "Browser Error")
        }

        do {
            let result = try await manager.evaluate(session: session, script: script)
            return ToolResult.success(
                result.isEmpty ? "(no return value)" : result,
                title: "Script Evaluated",
                didChange: true
            )
        } catch {
            return ToolResult.error("Evaluation failed: \(error.localizedDescription)", title: "Evaluation Failed")
        }
    }

    private func waitForElement(manager: BrowserManager, args: [String: Any]) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.error("No active browser session. Use 'launch' action first.", title: "Browser Error")
        }

        guard let selector = args["selector"] as? String else {
            return ToolResult.error("'selector' parameter is required for wait action", title: "Browser Error")
        }

        let timeout = args["timeout"] as? Int ?? 30000

        do {
            try await manager.waitForSelector(session: session, selector: selector, timeout: timeout)
            return ToolResult.success("Element found: \(selector)", title: "Wait Complete", didChange: false)
        } catch {
            return ToolResult.error("Wait failed: \(error.localizedDescription)", title: "Wait Failed")
        }
    }

    private func closeBrowser(manager: BrowserManager) async throws -> ToolResult {
        guard let session = BrowserTool.activeSession else {
            return ToolResult.success("No active browser session.", title: "Browser Closed", didChange: false)
        }

        do {
            try await manager.closeBrowser(session)
            BrowserTool.activeSession = nil
            return ToolResult.success("Browser closed successfully", title: "Browser Closed", didChange: true)
        } catch {
            return ToolResult.error("Failed to close browser: \(error.localizedDescription)", title: "Close Failed")
        }
    }
}
