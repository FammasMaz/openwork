import Foundation

/// Bridge to communicate with Playwright server via WebSocket/JSON-RPC
class PlaywrightBridge {
    private let port: Int
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var messageId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    init(port: Int) {
        self.port = port
    }

    // MARK: - Connection

    func connect() async throws {
        let url = URL(string: "ws://localhost:\(port)/")!
        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        Task {
            await receiveMessages()
        }

        // Wait for connection to be established
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session = nil
    }

    private func receiveMessages() async {
        guard let webSocket = webSocket else { return }

        while true {
            do {
                let message = try await webSocket.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                print("[PlaywrightBridge] WebSocket receive error: \(error)")
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle response
        if let id = json["id"] as? Int {
            if let continuation = pendingRequests[id] {
                pendingRequests.removeValue(forKey: id)
                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    continuation.resume(throwing: BrowserError.evaluationFailed(message))
                } else if let result = json["result"] as? [String: Any] {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: [:])
                }
            }
        }
    }

    // MARK: - JSON-RPC Communication

    private func sendCommand(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let webSocket = webSocket else {
            throw BrowserError.connectionFailed("WebSocket not connected")
        }

        messageId += 1
        let id = messageId

        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        let message = URLSessionWebSocketTask.Message.data(data)

        try await webSocket.send(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: BrowserError.evaluationFailed("Request timeout"))
                }
            }
        }
    }

    // MARK: - Browser Operations

    func launchBrowser(headless: Bool) async throws -> BrowserSession {
        // Launch browser via Playwright
        let launchResult = try await sendCommand(method: "Browser.launch", params: [
            "type": "chromium",
            "options": ["headless": headless]
        ])

        guard let browserId = launchResult["browser"] as? [String: Any],
              let browserGuid = browserId["guid"] as? String else {
            throw BrowserError.serverStartFailed("Failed to get browser ID")
        }

        // Create context
        let contextResult = try await sendCommand(method: "Browser.newContext", params: [
            "browser": browserGuid
        ])

        guard let contextId = contextResult["context"] as? [String: Any],
              let contextGuid = contextId["guid"] as? String else {
            throw BrowserError.serverStartFailed("Failed to create context")
        }

        // Create page
        let pageResult = try await sendCommand(method: "BrowserContext.newPage", params: [
            "context": contextGuid
        ])

        guard let pageId = pageResult["page"] as? [String: Any],
              let pageGuid = pageId["guid"] as? String else {
            throw BrowserError.serverStartFailed("Failed to create page")
        }

        return BrowserSession(browserId: browserGuid, contextId: contextGuid, pageId: pageGuid)
    }

    func closeBrowser(_ session: BrowserSession) async throws {
        _ = try await sendCommand(method: "Browser.close", params: [
            "browser": session.browserId
        ])
    }

    func navigate(session: BrowserSession, url: String) async throws {
        let result = try await sendCommand(method: "Page.goto", params: [
            "page": session.pageId,
            "url": url,
            "options": ["waitUntil": "networkidle"]
        ])

        if let error = result["error"] as? String {
            throw BrowserError.navigationFailed(error)
        }
    }

    func screenshot(session: BrowserSession, fullPage: Bool) async throws -> Data {
        let result = try await sendCommand(method: "Page.screenshot", params: [
            "page": session.pageId,
            "options": ["fullPage": fullPage, "type": "png"]
        ])

        guard let base64 = result["binary"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw BrowserError.screenshotFailed("Invalid screenshot data")
        }

        return data
    }

    func click(session: BrowserSession, selector: String) async throws {
        let result = try await sendCommand(method: "Page.click", params: [
            "page": session.pageId,
            "selector": selector
        ])

        if let error = result["error"] as? String {
            throw BrowserError.elementNotFound(error)
        }
    }

    func type(session: BrowserSession, selector: String, text: String) async throws {
        let result = try await sendCommand(method: "Page.fill", params: [
            "page": session.pageId,
            "selector": selector,
            "value": text
        ])

        if let error = result["error"] as? String {
            throw BrowserError.elementNotFound(error)
        }
    }

    func getContent(session: BrowserSession) async throws -> String {
        let result = try await sendCommand(method: "Page.content", params: [
            "page": session.pageId
        ])

        guard let content = result["value"] as? String else {
            return ""
        }

        return content
    }

    func evaluate(session: BrowserSession, script: String) async throws -> String {
        let result = try await sendCommand(method: "Page.evaluate", params: [
            "page": session.pageId,
            "expression": script
        ])

        if let value = result["value"] {
            if let stringValue = value as? String {
                return stringValue
            } else if let data = try? JSONSerialization.data(withJSONObject: value),
                      let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
        }

        return ""
    }

    func waitForSelector(session: BrowserSession, selector: String, timeout: Int) async throws {
        let result = try await sendCommand(method: "Page.waitForSelector", params: [
            "page": session.pageId,
            "selector": selector,
            "options": ["timeout": timeout]
        ])

        if let error = result["error"] as? String {
            throw BrowserError.elementNotFound(error)
        }
    }
}
