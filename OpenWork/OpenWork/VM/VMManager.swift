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
    private var consoleConnection: VMConsoleConnection?
    private var sharedFolders: [URL] = []

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

        let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootLoader.commandLine = "console=hvc0 root=/dev/vda rw"

        if let initrdURL = initrdPath {
            bootLoader.initialRamdiskURL = initrdURL
        }

        config.bootLoader = bootLoader

        // CPU and Memory
        config.cpuCount = min(4, ProcessInfo.processInfo.processorCount)
        config.memorySize = 2 * 1024 * 1024 * 1024 // 2GB

        // Root filesystem disk
        if let rootfsURL = rootfsPath {
            let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: rootfsURL, readOnly: false)
            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
            config.storageDevices = [disk]
        }

        // Network (NAT)
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [networkDevice]

        // Console for I/O
        let consoleDevice = VZVirtioConsoleDeviceConfiguration()
        let serialPort = VZVirtioConsolePortConfiguration()
        serialPort.name = "console"
        serialPort.isConsole = true
        consoleDevice.ports[0] = serialPort
        config.consoleDevices = [consoleDevice]

        // Shared folders (VirtioFS)
        var fsDevices: [VZVirtioFileSystemDeviceConfiguration] = []
        for (index, folder) in sharedFolders.enumerated() {
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
        try config.validate()

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
            if let consoleDevice = virtualMachine?.consoleDevices.first {
                // Console handling will be set up here
                // For now, we just note that it exists
            }

            try await virtualMachine?.start()
            state = .running
            isReady = true

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
        virtualMachine = nil
        state = .stopped
        isReady = false
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

    // MARK: - Command Execution

    /// Executes a command in the VM and returns the output
    func execute(command: String, timeout: TimeInterval = 120) async throws -> String {
        guard state == .running else {
            throw VMError.notRunning
        }

        // TODO: Implement actual command execution via console
        // This is a placeholder that will be implemented when we set up
        // proper console I/O handling

        return "Command execution not yet implemented"
    }
}

/// Console connection handler
class VMConsoleConnection {
    // Will handle stdin/stdout to the VM console
}

enum VMError: LocalizedError {
    case missingKernel
    case missingRootfs
    case notRunning
    case commandTimeout
    case executionFailed(String)

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
        }
    }
}
