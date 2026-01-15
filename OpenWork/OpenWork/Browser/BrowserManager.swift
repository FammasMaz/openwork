import Foundation

/// Manages browser automation via Playwright server
@MainActor
class BrowserManager: ObservableObject {
    static let shared = BrowserManager()

    @Published var isServerRunning: Bool = false
    @Published var serverError: String?
    @Published var activeBrowsers: [BrowserSession] = []

    private var serverProcess: Process?
    private var serverPort: Int = 3000
    private var playwrightBridge: PlaywrightBridge?

    private init() {}

    // MARK: - Server Lifecycle

    /// Starts the Playwright server
    func startServer() async throws {
        guard !isServerRunning else { return }

        // Check if npx is available
        let npxPath = try await findExecutable("npx")

        serverProcess = Process()
        serverProcess?.executableURL = URL(fileURLWithPath: npxPath)
        serverProcess?.arguments = ["playwright-core", "run-server", "--port", "\(serverPort)"]

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        serverProcess?.standardOutput = outputPipe
        serverProcess?.standardError = errorPipe

        do {
            try serverProcess?.run()

            // Wait for server to be ready
            try await waitForServer(port: serverPort, timeout: 30)

            // Create bridge connection
            playwrightBridge = PlaywrightBridge(port: serverPort)
            try await playwrightBridge?.connect()

            isServerRunning = true
            serverError = nil
        } catch {
            serverError = "Failed to start Playwright server: \(error.localizedDescription)"
            throw BrowserError.serverStartFailed(error.localizedDescription)
        }
    }

    /// Stops the Playwright server
    func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        playwrightBridge?.disconnect()
        playwrightBridge = nil
        isServerRunning = false
        activeBrowsers.removeAll()
    }

    // MARK: - Browser Operations

    /// Launches a new browser instance
    func launchBrowser(headless: Bool = true) async throws -> BrowserSession {
        guard isServerRunning, let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }

        let session = try await bridge.launchBrowser(headless: headless)
        activeBrowsers.append(session)
        return session
    }

    /// Closes a browser session
    func closeBrowser(_ session: BrowserSession) async throws {
        guard let bridge = playwrightBridge else { return }
        try await bridge.closeBrowser(session)
        activeBrowsers.removeAll { $0.id == session.id }
    }

    /// Navigates to a URL
    func navigate(session: BrowserSession, url: String) async throws {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        try await bridge.navigate(session: session, url: url)
    }

    /// Takes a screenshot
    func screenshot(session: BrowserSession, fullPage: Bool = false) async throws -> Data {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        return try await bridge.screenshot(session: session, fullPage: fullPage)
    }

    /// Clicks an element
    func click(session: BrowserSession, selector: String) async throws {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        try await bridge.click(session: session, selector: selector)
    }

    /// Types text into an element
    func type(session: BrowserSession, selector: String, text: String) async throws {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        try await bridge.type(session: session, selector: selector, text: text)
    }

    /// Gets the page content
    func getContent(session: BrowserSession) async throws -> String {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        return try await bridge.getContent(session: session)
    }

    /// Evaluates JavaScript in the page
    func evaluate(session: BrowserSession, script: String) async throws -> String {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        return try await bridge.evaluate(session: session, script: script)
    }

    /// Waits for a selector
    func waitForSelector(session: BrowserSession, selector: String, timeout: Int = 30000) async throws {
        guard let bridge = playwrightBridge else {
            throw BrowserError.serverNotRunning
        }
        try await bridge.waitForSelector(session: session, selector: selector, timeout: timeout)
    }

    // MARK: - Helpers

    private func findExecutable(_ name: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw BrowserError.executableNotFound(name)
        }

        return path
    }

    private func waitForServer(port: Int, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await isPortOpen(port: port) {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        throw BrowserError.serverTimeout
    }

    private func isPortOpen(port: Int) async -> Bool {
        let url = URL(string: "http://localhost:\(port)/json")!
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Browser Session

struct BrowserSession: Identifiable {
    let id: String
    let browserId: String
    let contextId: String
    let pageId: String
    var currentURL: String?
    let createdAt: Date

    init(browserId: String, contextId: String, pageId: String) {
        self.id = UUID().uuidString
        self.browserId = browserId
        self.contextId = contextId
        self.pageId = pageId
        self.currentURL = nil
        self.createdAt = Date()
    }
}

// MARK: - Errors

enum BrowserError: LocalizedError {
    case serverNotRunning
    case serverStartFailed(String)
    case serverTimeout
    case executableNotFound(String)
    case navigationFailed(String)
    case elementNotFound(String)
    case evaluationFailed(String)
    case screenshotFailed(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Browser server is not running"
        case .serverStartFailed(let reason):
            return "Failed to start browser server: \(reason)"
        case .serverTimeout:
            return "Browser server failed to start within timeout"
        case .executableNotFound(let name):
            return "Executable not found: \(name)"
        case .navigationFailed(let url):
            return "Failed to navigate to: \(url)"
        case .elementNotFound(let selector):
            return "Element not found: \(selector)"
        case .evaluationFailed(let reason):
            return "JavaScript evaluation failed: \(reason)"
        case .screenshotFailed(let reason):
            return "Screenshot failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}
