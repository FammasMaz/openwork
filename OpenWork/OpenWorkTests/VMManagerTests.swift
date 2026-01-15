import XCTest
@testable import OpenWork

@MainActor
final class VMManagerTests: XCTestCase {

    var vmManager: VMManager!

    override func setUp() async throws {
        vmManager = VMManager()
    }

    override func tearDown() async throws {
        if vmManager.state == .running {
            try? await vmManager.stop()
        }
        vmManager = nil
    }

    // MARK: - State Tests

    func testInitialState() {
        XCTAssertEqual(vmManager.state, .stopped)
        XCTAssertFalse(vmManager.isReady)
        XCTAssertNil(vmManager.error)
    }

    func testStateTransitions() {
        XCTAssertEqual(vmManager.state.rawValue, "Stopped")

        // Verify all state raw values
        XCTAssertEqual(VMManager.VMState.stopped.rawValue, "Stopped")
        XCTAssertEqual(VMManager.VMState.starting.rawValue, "Starting")
        XCTAssertEqual(VMManager.VMState.running.rawValue, "Running")
        XCTAssertEqual(VMManager.VMState.paused.rawValue, "Paused")
        XCTAssertEqual(VMManager.VMState.error.rawValue, "Error")
    }

    // MARK: - Path Translation Tests

    func testTranslateToVMPath() {
        let hostPath = URL(fileURLWithPath: "/Users/test/project")
        vmManager.addSharedFolder(hostPath)

        // Test exact path
        let vmPath = vmManager.translateToVMPath("/Users/test/project")
        XCTAssertEqual(vmPath, "/mnt/share0")

        // Test subpath
        let subPath = vmManager.translateToVMPath("/Users/test/project/src/main.swift")
        XCTAssertEqual(subPath, "/mnt/share0/src/main.swift")

        // Test non-shared path returns nil
        let outsidePath = vmManager.translateToVMPath("/Users/other/file.txt")
        XCTAssertNil(outsidePath)
    }

    func testTranslateToHostPath() {
        let hostPath = URL(fileURLWithPath: "/Users/test/project")
        vmManager.addSharedFolder(hostPath)

        // Test exact mount point
        let hostResult = vmManager.translateToHostPath("/mnt/share0")
        XCTAssertEqual(hostResult, "/Users/test/project")

        // Test subpath
        let subResult = vmManager.translateToHostPath("/mnt/share0/src/file.swift")
        XCTAssertEqual(subResult, "/Users/test/project/src/file.swift")

        // Test non-mount path returns nil
        let otherPath = vmManager.translateToHostPath("/home/user/file.txt")
        XCTAssertNil(otherPath)
    }

    func testMultipleSharedFolders() {
        let folder1 = URL(fileURLWithPath: "/Users/test/project1")
        let folder2 = URL(fileURLWithPath: "/Users/test/project2")

        vmManager.addSharedFolder(folder1)
        vmManager.addSharedFolder(folder2)

        XCTAssertEqual(vmManager.translateToVMPath("/Users/test/project1/file.txt"), "/mnt/share0/file.txt")
        XCTAssertEqual(vmManager.translateToVMPath("/Users/test/project2/file.txt"), "/mnt/share1/file.txt")
    }

    // MARK: - Shared Folder Tests

    func testAddSharedFolder() {
        let folder = URL(fileURLWithPath: "/Users/test/project")
        vmManager.addSharedFolder(folder)

        let vmPath = vmManager.translateToVMPath("/Users/test/project/test.txt")
        XCTAssertNotNil(vmPath)
    }

    func testRemoveSharedFolder() {
        let folder = URL(fileURLWithPath: "/Users/test/project")
        vmManager.addSharedFolder(folder)
        vmManager.removeSharedFolder(folder)

        let vmPath = vmManager.translateToVMPath("/Users/test/project/test.txt")
        XCTAssertNil(vmPath)
    }

    func testMountCommand() {
        let command = vmManager.mountCommand(for: 0, at: "/mnt/share0")
        XCTAssertEqual(command, "mount -t virtiofs share0 /mnt/share0")
    }

    // MARK: - Configuration Tests

    func testDefaultSettings() {
        XCTAssertTrue(vmManager.keepWarm)
        XCTAssertTrue(vmManager.autoStart)
        XCTAssertEqual(vmManager.warmIdleTimeout, 300)
    }

    // MARK: - Error Cases

    func testExecuteWhenNotRunning() async {
        do {
            _ = try await vmManager.execute(command: "ls")
            XCTFail("Should throw error when VM not running")
        } catch {
            XCTAssertTrue(error is VMError)
            if case VMError.notRunning = error {
                // Expected
            } else {
                XCTFail("Expected notRunning error")
            }
        }
    }

    // MARK: - Health Check Tests

    func testHealthCheckWhenStopped() async {
        let healthy = await vmManager.healthCheck()
        XCTAssertFalse(healthy)
    }
}

// MARK: - String Extension Tests

final class StringShellEscapeTests: XCTestCase {

    func testSimpleString() {
        let simple = "hello"
        XCTAssertEqual(simple.shellEscaped, "hello")
    }

    func testPathString() {
        let path = "/Users/test/project/file.txt"
        XCTAssertEqual(path.shellEscaped, "/Users/test/project/file.txt")
    }

    func testStringWithSpaces() {
        let spaced = "hello world"
        XCTAssertTrue(spaced.shellEscaped.hasPrefix("'"))
        XCTAssertTrue(spaced.shellEscaped.hasSuffix("'"))
    }

    func testStringWithQuotes() {
        let quoted = "it's a test"
        let escaped = quoted.shellEscaped
        XCTAssertTrue(escaped.contains("'\"'\"'"))
    }

    func testStringWithSpecialChars() {
        let special = "file@name#1"
        XCTAssertTrue(special.shellEscaped.hasPrefix("'"))
    }
}

// MARK: - CommandResult Tests

final class CommandResultTests: XCTestCase {

    func testSucceededWithZeroExitCode() {
        let result = CommandResult(output: "success", exitCode: 0, duration: 1.0)
        XCTAssertTrue(result.succeeded)
    }

    func testFailedWithNonZeroExitCode() {
        let result = CommandResult(output: "error", exitCode: 1, duration: 1.0)
        XCTAssertFalse(result.succeeded)
    }

    func testNegativeExitCode() {
        let result = CommandResult(output: "killed", exitCode: -1, duration: 0.5)
        XCTAssertFalse(result.succeeded)
    }
}

// MARK: - VMError Tests

final class VMErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertEqual(VMError.missingKernel.errorDescription, "Linux kernel not found in bundle")
        XCTAssertEqual(VMError.missingRootfs.errorDescription, "Root filesystem not found in bundle")
        XCTAssertEqual(VMError.notRunning.errorDescription, "VM is not running")
        XCTAssertEqual(VMError.commandTimeout.errorDescription, "Command execution timed out")
        XCTAssertEqual(VMError.executionFailed("test").errorDescription, "Execution failed: test")
    }
}
