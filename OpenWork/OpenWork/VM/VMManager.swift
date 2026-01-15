import Foundation
import Virtualization
import SwiftUI

/// Manages the Linux VM lifecycle using Apple's Virtualization.framework
@MainActor
class VMManager: ObservableObject {
    @Published var state: VMState = .stopped
    @Published var consoleOutput: String = ""
    @Published var isReady: Bool = false
    @Published var error: String?

    private var virtualMachine: VZVirtualMachine?
    private var consoleIO: VMConsoleIO?
    private var sharedFolders: [URL] = []

    /// Mapping from host paths to VM mount points
    private var pathMappings: [URL: String] = [:]

    /// Whether to keep VM warm between tasks
    var keepWarm: Bool = true

    /// Auto-start VM when needed
    var autoStart: Bool = true

    /// Idle timeout before stopping warm VM (seconds)
    var warmIdleTimeout: TimeInterval = 300 // 5 minutes

    /// Last activity timestamp
    private var lastActivityTime: Date = Date()

    /// Idle monitor task
    private var idleMonitorTask: Task<Void, Never>?

    /// Pending commands count (for graceful shutdown)
    private var pendingCommandCount: Int = 0

    enum VMState: String {
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case paused = "Paused"
        case error = "Error"
    }

    // MARK: - VM Configuration

    /// Path to the Linux kernel
    private var kernelPath: URL? {
        Bundle.main.url(forResource: "vmlinuz", withExtension: nil, subdirectory: "linux")
    }

    /// Path to the initial ramdisk
    private var initrdPath: URL? {
        Bundle.main.url(forResource: "initrd", withExtension: "img", subdirectory: "linux")
    }

    /// Path to the root filesystem
    private var rootfsPath: URL? {
        Bundle.main.url(forResource: "rootfs", withExtension: "img", subdirectory: "linux")
    }

    /// Creates the VM configuration
    private func createConfiguration() throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()

        // Boot loader
        guard let kernelURL = kernelPath else {
            throw VMError.missingKernel
        }

        // Verify kernel file exists
        guard FileManager.default.fileExists(atPath: kernelURL.path) else {
            throw VMError.configurationFailed("Kernel file not found at: \(kernelURL.path)")
        }

        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.commandLine = "console=hvc0 root=/dev/vda rw"

        if let initrdURL = initrdPath,
           FileManager.default.fileExists(atPath: initrdURL.path) {
            bootLoader.initialRamdiskURL = initrdURL
        }

        config.bootLoader = bootLoader

        // CPU and Memory
        config.cpuCount = min(4, ProcessInfo.processInfo.processorCount)
        config.memorySize = 2 * 1024 * 1024 * 1024 // 2GB

        // Root filesystem disk - only add if file exists and is valid
        if let rootfsURL = rootfsPath,
           FileManager.default.fileExists(atPath: rootfsURL.path) {
            do {
                let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: rootfsURL, readOnly: false)
                let disk = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
                config.storageDevices = [disk]
            } catch {
                // Log the error but continue without storage - VM will boot to initrd
                print("[VMManager] Warning: Could not attach disk image: \(error.localizedDescription)")
                print("[VMManager] VM will boot without persistent storage")
            }
        }

        // Network (NAT)
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkDevice]

        // Console for I/O with file handle attachment
        let consoleDevice = VZVirtioConsoleDeviceConfiguration()
        let serialPort = VZVirtioConsolePortConfiguration()
        serialPort.name = "console"
        serialPort.isConsole = true

        // Create pipes for bidirectional communication
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        let serialAttachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: stdinPipe.fileHandleForReading,
            fileHandleForWriting: stdoutPipe.fileHandleForWriting
        )
        serialPort.attachment = serialAttachment
        consoleDevice.ports[0] = serialPort
        config.consoleDevices = [consoleDevice]

        // Store pipes for later use in console I/O
        self.consoleIO = VMConsoleIO(
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading
        )

        // Shared folders (VirtioFS)
        var fsDevices: [VZVirtioFileSystemDeviceConfiguration] = []
        for (index, folder) in sharedFolders.enumerated() {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let sharedDir = VZSharedDirectory(url: folder, readOnly: false)
            let share = VZSingleDirectoryShare(directory: sharedDir)
            let fsDevice = VZVirtioFileSystemDeviceConfiguration(tag: "share\(index)")
            fsDevice.share = share
            fsDevices.append(fsDevice)
        }
        config.directorySharingDevices = fsDevices

        // Entropy device (for /dev/random)
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        // Validate configuration
        do {
            try config.validate()
        } catch {
            throw VMError.configurationFailed("VM configuration invalid: \(error.localizedDescription)")
        }

        return config
    }

    // MARK: - VM Lifecycle

    /// Starts the VM
    func start() async throws {
        guard state == .stopped else { return }

        state = .starting
        error = nil

        do {
            let config = try createConfiguration()
            virtualMachine = VZVirtualMachine(configuration: config)

            // Set up console connection
            if virtualMachine?.consoleDevices.first != nil {
                // Start reading console output in background
                await consoleIO?.startReading()
            }

            try await virtualMachine?.start()

            // Wait for VM to be ready (shell prompt)
            try await waitForVMReady()

            state = .running
            isReady = true
            recordActivity()
            startIdleMonitor()

        } catch {
            state = .error
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Stops the VM
    func stop() async throws {
        guard state == .running || state == .paused else { return }

        try await virtualMachine?.stop()
        await consoleIO?.stopReading()
        virtualMachine = nil
        consoleIO = nil
        state = .stopped
        isReady = false
        stopIdleMonitor()
    }

    /// Gracefully stops the VM, waiting for pending commands
    func gracefulStop(timeout: TimeInterval = 30) async throws {
        guard state == .running else { return }

        // Wait for pending commands to complete
        let deadline = Date().addingTimeInterval(timeout)
        while pendingCommandCount > 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        try await stop()
    }

    /// Pauses the VM
    func pause() async throws {
        guard state == .running else { return }
        try await virtualMachine?.pause()
        state = .paused
    }

    /// Resumes the VM
    func resume() async throws {
        guard state == .paused else { return }
        try await virtualMachine?.resume()
        state = .running
        recordActivity()
    }

    /// Ensures VM is running, starting it if necessary (auto-start)
    func ensureRunning() async throws {
        switch state {
        case .running:
            recordActivity()
            return
        case .paused:
            try await resume()
        case .stopped, .error:
            if autoStart {
                try await start()
            } else {
                throw VMError.notRunning
            }
        case .starting:
            // Wait for startup to complete
            while state == .starting {
                try await Task.sleep(for: .milliseconds(100))
            }
            if state != .running {
                throw VMError.executionFailed("VM failed to start")
            }
        }
    }

    // MARK: - Idle Monitoring

    /// Records activity to reset idle timer
    private func recordActivity() {
        lastActivityTime = Date()
    }

    /// Starts the idle monitor for warm VM shutdown
    private func startIdleMonitor() {
        guard keepWarm else { return }

        stopIdleMonitor()

        idleMonitorTask = Task {
            while !Task.isCancelled && state == .running {
                try? await Task.sleep(for: .seconds(30))

                let idleTime = Date().timeIntervalSince(lastActivityTime)
                if idleTime >= warmIdleTimeout && pendingCommandCount == 0 {
                    // Idle timeout reached, stop VM
                    try? await stop()
                    break
                }
            }
        }
    }

    /// Stops the idle monitor
    private func stopIdleMonitor() {
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
    }

    // MARK: - Shared Folders

    /// Adds a shared folder to the VM
    func addSharedFolder(_ url: URL) {
        sharedFolders.append(url)
    }

    /// Removes a shared folder
    func removeSharedFolder(_ url: URL) {
        sharedFolders.removeAll { $0 == url }
    }

    /// Gets the mount command for a shared folder
    func mountCommand(for index: Int, at mountPoint: String) -> String {
        "mount -t virtiofs share\(index) \(mountPoint)"
    }

    /// Translates a host path to a VM path
    func translateToVMPath(_ hostPath: String) -> String? {
        for (index, folder) in sharedFolders.enumerated() {
            if hostPath.hasPrefix(folder.path) {
                let relativePath = String(hostPath.dropFirst(folder.path.count))
                let vmPath = "/mnt/share\(index)" + relativePath
                return vmPath
            }
        }
        return nil
    }

    /// Translates a VM path back to a host path
    func translateToHostPath(_ vmPath: String) -> String? {
        for (index, folder) in sharedFolders.enumerated() {
            let prefix = "/mnt/share\(index)"
            if vmPath.hasPrefix(prefix) {
                let relativePath = String(vmPath.dropFirst(prefix.count))
                return folder.path + relativePath
            }
        }
        return nil
    }

    // MARK: - Command Execution

    /// Waits for the VM to be ready (shell prompt available)
    private func waitForVMReady(timeout: TimeInterval = 60) async throws {
        guard let consoleIO = consoleIO else {
            throw VMError.executionFailed("Console not initialized")
        }

        let startTime = Date()

        // Wait for login prompt or shell prompt
        while Date().timeIntervalSince(startTime) < timeout {
            // Send a newline and check for response
            try await Task.sleep(for: .seconds(2))

            // Try to execute a simple command to verify readiness
            do {
                let result = try await executeRaw(command: "echo ready", timeout: 10)
                if result.output.contains("ready") {
                    // Mount shared folders
                    try await mountSharedFolders()
                    return
                }
            } catch {
                // VM not ready yet, continue waiting
                continue
            }
        }

        throw VMError.commandTimeout
    }

    /// Mounts all shared folders in the VM
    private func mountSharedFolders() async throws {
        for (index, _) in sharedFolders.enumerated() {
            let mountPoint = "/mnt/share\(index)"

            // Create mount point and mount
            _ = try? await executeRaw(command: "mkdir -p \(mountPoint)", timeout: 5)
            _ = try? await executeRaw(command: mountCommand(for: index, at: mountPoint), timeout: 10)
        }
    }

    /// Executes a command in the VM and returns the output
    func execute(command: String, timeout: TimeInterval = 120, workingDirectory: String? = nil) async throws -> CommandResult {
        guard state == .running else {
            throw VMError.notRunning
        }

        guard let consoleIO = consoleIO else {
            throw VMError.executionFailed("Console not initialized")
        }

        // Track pending command and record activity
        pendingCommandCount += 1
        recordActivity()
        defer {
            pendingCommandCount -= 1
            recordActivity()
        }

        // Build the full command with working directory if specified
        var fullCommand = command
        if let workDir = workingDirectory {
            // Translate host path to VM path if needed
            let vmWorkDir = translateToVMPath(workDir) ?? workDir
            fullCommand = "cd \(vmWorkDir.shellEscaped) && \(command)"
        }

        return try await consoleIO.execute(command: fullCommand, timeout: timeout)
    }

    /// Low-level command execution (for internal use, doesn't track pending commands)
    private func executeRaw(command: String, timeout: TimeInterval) async throws -> CommandResult {
        guard let consoleIO = consoleIO else {
            throw VMError.executionFailed("Console not initialized")
        }
        return try await consoleIO.execute(command: command, timeout: timeout)
    }

    /// Health check - verify VM is responsive
    func healthCheck() async -> Bool {
        guard state == .running else { return false }

        do {
            let result = try await execute(command: "echo ok", timeout: 5)
            return result.output.contains("ok") && result.exitCode == 0
        } catch {
            return false
        }
    }
}

/// Result of a command execution
struct CommandResult {
    let output: String
    let exitCode: Int
    let duration: TimeInterval

    var succeeded: Bool { exitCode == 0 }
}

/// Console I/O handler for VM command execution
actor VMConsoleIO {
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private var outputBuffer: String = ""
    private var isReading: Bool = false
    private var readTask: Task<Void, Never>?

    /// Unique marker for detecting command completion
    private static let completionMarker = "___CMD_DONE___"

    init(stdinHandle: FileHandle, stdoutHandle: FileHandle) {
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
    }

    /// Starts background reading of console output
    func startReading() {
        guard !isReading else { return }
        isReading = true

        readTask = Task {
            await readLoop()
        }
    }

    /// Stops reading console output
    func stopReading() {
        isReading = false
        readTask?.cancel()
        readTask = nil
    }

    /// Background read loop
    private func readLoop() async {
        while isReading && !Task.isCancelled {
            do {
                if let data = try stdoutHandle.availableData.isEmpty ? nil : stdoutHandle.availableData,
                   let text = String(data: data, encoding: .utf8) {
                    outputBuffer += text
                }
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                break
            }
        }
    }

    /// Executes a command and returns the result
    func execute(command: String, timeout: TimeInterval) async throws -> CommandResult {
        let startTime = Date()
        let commandId = UUID().uuidString.prefix(8)
        let marker = "\(Self.completionMarker)_\(commandId)"

        // Clear buffer before command
        outputBuffer = ""

        // Wrap command to capture exit code
        // Format: (command); echo "MARKER_$?"
        let wrappedCommand = "(\(command)); echo \"\(marker)_$?\"\n"

        // Send command to VM
        guard let commandData = wrappedCommand.data(using: .utf8) else {
            throw VMError.executionFailed("Failed to encode command")
        }

        try stdinHandle.write(contentsOf: commandData)

        // Wait for completion marker with exit code
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // Check for completion marker in output
            if let markerRange = outputBuffer.range(of: "\(marker)_") {
                // Extract exit code after marker
                let afterMarker = outputBuffer[markerRange.upperBound...]
                if let newlineIndex = afterMarker.firstIndex(of: "\n") ?? afterMarker.firstIndex(of: "\r") {
                    let exitCodeStr = String(afterMarker[..<newlineIndex]).trimmingCharacters(in: .whitespaces)
                    let exitCode = Int(exitCodeStr) ?? -1

                    // Extract output (everything before the marker line)
                    var output = String(outputBuffer[..<markerRange.lowerBound])

                    // Clean up output - remove the command echo and trailing whitespace
                    output = cleanOutput(output, command: command)

                    let duration = Date().timeIntervalSince(startTime)
                    return CommandResult(output: output, exitCode: exitCode, duration: duration)
                }
            }

            try await Task.sleep(for: .milliseconds(50))

            // Read more data if available
            if let data = try? stdoutHandle.availableData, !data.isEmpty,
               let text = String(data: data, encoding: .utf8) {
                outputBuffer += text
            }
        }

        throw VMError.commandTimeout
    }

    /// Cleans up command output
    private func cleanOutput(_ output: String, command: String) -> String {
        var lines = output.components(separatedBy: .newlines)

        // Remove empty lines at start and end
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }

        // Remove the echoed command if present
        if let firstLine = lines.first,
           firstLine.contains(command.prefix(20)) {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n")
    }
}

enum VMError: LocalizedError {
    case missingKernel
    case missingRootfs
    case notRunning
    case commandTimeout
    case executionFailed(String)
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingKernel:
            return "Linux kernel not found in bundle"
        case .missingRootfs:
            return "Root filesystem not found in bundle"
        case .notRunning:
            return "VM is not running"
        case .commandTimeout:
            return "Command execution timed out"
        case .executionFailed(let msg):
            return "Execution failed: \(msg)"
        case .configurationFailed(let msg):
            return "VM configuration failed: \(msg)"
        }
    }
}

// MARK: - String Extensions for Shell

extension String {
    /// Escapes a string for safe use in shell commands
    var shellEscaped: String {
        // If the string contains no special characters, return as-is
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_.-"))
        if self.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return self
        }

        // Otherwise, wrap in single quotes and escape any single quotes
        let escaped = self.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
