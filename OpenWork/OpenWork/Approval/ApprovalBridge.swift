import Foundation
import Network

/// HTTP bridge for external permission requests (e.g., from MCP servers)
/// Listens on a local port and bridges requests to ApprovalManager
@MainActor
class ApprovalBridge: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var requestCount: Int = 0

    private var listener: NWListener?
    private let port: UInt16
    private let approvalManager: ApprovalManager
    private let toolRegistry: ToolRegistry

    /// Pending HTTP requests waiting for approval decisions
    private var pendingRequests: [String: PendingPermissionRequest] = [:]

    /// Timeout for permission requests (5 minutes)
    private let requestTimeout: TimeInterval = 300

    init(approvalManager: ApprovalManager, toolRegistry: ToolRegistry, port: UInt16 = 9226) {
        self.approvalManager = approvalManager
        self.toolRegistry = toolRegistry
        self.port = port
    }

    // MARK: - Server Lifecycle

    /// Starts the HTTP bridge server
    func start() throws {
        guard !isRunning else { return }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    /// Stops the HTTP bridge server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false

        // Cancel all pending requests
        for (_, pending) in pendingRequests {
            pending.continuation?.resume(returning: PermissionResponse(
                approved: false,
                error: "Server stopped"
            ))
        }
        pendingRequests.removeAll()
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            Task { @MainActor in
                await self.processRequest(data: data, connection: connection)
            }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) async {
        // Parse HTTP request
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request"])
            return
        }

        // Extract path and body from HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request"])
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid request line"])
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Find body (after empty line)
        var bodyString = ""
        if let emptyLineIndex = lines.firstIndex(of: "") {
            bodyString = lines.dropFirst(emptyLineIndex + 1).joined(separator: "\r\n")
        }

        // Route request
        switch (method, path) {
        case ("POST", "/permission"):
            await handlePermissionRequest(body: bodyString, connection: connection)
        case ("GET", "/health"):
            sendResponse(connection: connection, statusCode: 200, body: ["status": "ok"])
        case ("GET", "/pending"):
            let pending = pendingRequests.map { ($0.key, $0.value.toolId) }
            sendResponse(connection: connection, statusCode: 200, body: [
                "pending": pending.map { ["id": $0.0, "tool": $0.1] }
            ])
        default:
            sendResponse(connection: connection, statusCode: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Permission Request Handling

    private func handlePermissionRequest(body: String, connection: NWConnection) async {
        requestCount += 1

        // Parse JSON body
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Invalid JSON body"])
            return
        }

        // Extract required fields
        guard let toolId = json["tool_id"] as? String else {
            sendResponse(connection: connection, statusCode: 400, body: ["error": "Missing tool_id"])
            return
        }

        let args = json["args"] as? [String: Any] ?? [:]
        let workingDir = (json["working_directory"] as? String).flatMap { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser

        // Find the tool
        guard let tool = toolRegistry.tool(forID: toolId) else {
            sendResponse(connection: connection, statusCode: 404, body: ["error": "Tool not found: \(toolId)"])
            return
        }

        let requestId = UUID().uuidString

        // Create pending request with timeout
        let pending = PendingPermissionRequest(
            id: requestId,
            toolId: toolId,
            args: args,
            connection: connection,
            createdAt: Date()
        )
        pendingRequests[requestId] = pending

        // Set up timeout
        Task {
            try? await Task.sleep(for: .seconds(requestTimeout))
            await MainActor.run {
                if let pending = self.pendingRequests.removeValue(forKey: requestId) {
                    self.sendResponse(
                        connection: pending.connection,
                        statusCode: 408,
                        body: ["error": "Request timed out", "approved": false]
                    )
                }
            }
        }

        // Request approval from ApprovalManager
        let decision = await approvalManager.requestApproval(
            tool: tool,
            args: args,
            workingDirectory: workingDir
        )

        // Remove from pending and send response
        pendingRequests.removeValue(forKey: requestId)

        let response = PermissionResponse(
            approved: decision.isApproved,
            remember: decision.shouldRemember,
            reason: decision.denialReason
        )

        sendResponse(connection: connection, statusCode: 200, body: response.toDict())
    }

    // MARK: - HTTP Response

    private func sendResponse(connection: NWConnection, statusCode: Int, body: [String: Any]) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 408: statusText = "Request Timeout"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let bodyData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        \(bodyString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Supporting Types

private struct PendingPermissionRequest {
    let id: String
    let toolId: String
    let args: [String: Any]
    let connection: NWConnection
    let createdAt: Date
    var continuation: CheckedContinuation<PermissionResponse, Never>?
}

private struct PermissionResponse {
    let approved: Bool
    var remember: Bool = false
    var reason: String?
    var error: String?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["approved": approved]
        if remember { dict["remember"] = true }
        if let reason = reason { dict["reason"] = reason }
        if let error = error { dict["error"] = error }
        return dict
    }
}

// MARK: - ApprovalDecision Extensions

extension ApprovalDecision {
    var shouldRemember: Bool {
        switch self {
        case .approved(let remember): return remember
        case .denied: return false
        }
    }

    var denialReason: String? {
        switch self {
        case .approved: return nil
        case .denied(let reason): return reason
        }
    }
}
