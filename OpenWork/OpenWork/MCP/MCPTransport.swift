import Foundation

/// Transport layer for MCP communication
protocol MCPTransport {
    func send(_ message: MCPMessage) async throws
    func receive() async throws -> MCPMessage
    func close()
    var isConnected: Bool { get }
}

/// Standard I/O transport for MCP (spawns subprocess)
class StdioTransport: MCPTransport {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private var buffer = Data()
    private(set) var isConnected: Bool = false
    
    init(command: String, arguments: [String] = [], environment: [String: String]? = nil) throws {
        process = Process()
        
        // Handle command path
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
        } else {
            // Search in PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        
        if !command.hasPrefix("/") {
            // Already set above
        } else {
            process.arguments = arguments
        }
        
        // Set environment
        var env = ProcessInfo.processInfo.environment
        if let customEnv = environment {
            env.merge(customEnv) { _, new in new }
        }
        process.environment = env
        
        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading
        
        // Handle stderr for debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                print("[MCP stderr] \(str)")
            }
        }
        
        try process.run()
        isConnected = true
    }
    
    func send(_ message: MCPMessage) async throws {
        guard isConnected else {
            throw MCPTransportError.notConnected
        }
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        // MCP uses Content-Length headers (LSP-style)
        let header = "Content-Length: \(data.count)\r\n\r\n"
        
        guard let headerData = header.data(using: .utf8) else {
            throw MCPTransportError.encodingError
        }
        
        stdin.write(headerData)
        stdin.write(data)
    }
    
    func receive() async throws -> MCPMessage {
        guard isConnected else {
            throw MCPTransportError.notConnected
        }
        
        // Read Content-Length header
        let contentLength = try await readContentLength()
        
        // Read body
        let body = try await readBytes(count: contentLength)
        
        let decoder = JSONDecoder()
        return try decoder.decode(MCPMessage.self, from: body)
    }
    
    private func readContentLength() async throws -> Int {
        var headerBuffer = Data()
        let endMarker = Data("\r\n\r\n".utf8)
        
        while !headerBuffer.hasSuffix(endMarker) {
            let byte = stdout.readData(ofLength: 1)
            if byte.isEmpty {
                throw MCPTransportError.connectionClosed
            }
            headerBuffer.append(byte)
            
            // Safety limit
            if headerBuffer.count > 1000 {
                throw MCPTransportError.invalidHeader
            }
        }
        
        guard let headerStr = String(data: headerBuffer, encoding: .utf8) else {
            throw MCPTransportError.invalidHeader
        }
        
        // Parse Content-Length
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let valueStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                guard let length = Int(valueStr) else {
                    throw MCPTransportError.invalidHeader
                }
                return length
            }
        }
        
        throw MCPTransportError.missingContentLength
    }
    
    private func readBytes(count: Int) async throws -> Data {
        var result = Data()
        var remaining = count
        
        while remaining > 0 {
            let chunk = stdout.readData(ofLength: remaining)
            if chunk.isEmpty {
                throw MCPTransportError.connectionClosed
            }
            result.append(chunk)
            remaining -= chunk.count
        }
        
        return result
    }
    
    func close() {
        isConnected = false
        stdin.closeFile()
        stdout.closeFile()
        process.terminate()
    }
}

// MARK: - Errors

enum MCPTransportError: LocalizedError {
    case notConnected
    case connectionClosed
    case encodingError
    case invalidHeader
    case missingContentLength
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .connectionClosed:
            return "Connection closed unexpectedly"
        case .encodingError:
            return "Failed to encode message"
        case .invalidHeader:
            return "Invalid message header"
        case .missingContentLength:
            return "Missing Content-Length header"
        case .timeout:
            return "Connection timed out"
        }
    }
}

// MARK: - Data Extension

private extension Data {
    func hasSuffix(_ suffix: Data) -> Bool {
        guard count >= suffix.count else { return false }
        return self.suffix(suffix.count) == suffix
    }
}
