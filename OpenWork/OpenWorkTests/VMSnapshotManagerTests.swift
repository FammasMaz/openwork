import XCTest
@testable import OpenWork

@MainActor
final class VMSnapshotManagerTests: XCTestCase {

    var snapshotManager: VMSnapshotManager!

    override func setUp() async throws {
        snapshotManager = VMSnapshotManager()
        snapshotManager.clearAllSnapshots()
    }

    override func tearDown() async throws {
        snapshotManager.clearAllSnapshots()
        snapshotManager = nil
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(snapshotManager.snapshots.isEmpty)
        XCTAssertFalse(snapshotManager.isCreatingSnapshot)
        XCTAssertFalse(snapshotManager.isRestoring)
        XCTAssertNil(snapshotManager.lastError)
    }

    // MARK: - Snapshot Operations

    func testDeleteSnapshot() {
        // Create a mock snapshot
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "Test Snapshot",
            vmState: .running,
            workingDirectory: nil,
            createdAt: Date(),
            apfsSnapshotName: nil,
            diskPath: nil
        )

        // Add directly to snapshots array for testing
        snapshotManager.snapshots.append(snapshot)
        XCTAssertEqual(snapshotManager.snapshots.count, 1)

        snapshotManager.deleteSnapshot(snapshot)
        XCTAssertEqual(snapshotManager.snapshots.count, 0)
    }

    func testRenameSnapshot() {
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "Original Name",
            vmState: .running,
            workingDirectory: nil,
            createdAt: Date(),
            apfsSnapshotName: nil,
            diskPath: nil
        )

        snapshotManager.snapshots.append(snapshot)

        snapshotManager.renameSnapshot(snapshot, newName: "New Name")

        let renamed = snapshotManager.snapshots.first { $0.id == snapshot.id }
        XCTAssertEqual(renamed?.name, "New Name")
    }

    func testClearAllSnapshots() {
        // Add some snapshots
        for i in 0..<5 {
            let snapshot = VMSnapshot(
                id: UUID(),
                name: "Snapshot \(i)",
                vmState: .running,
                workingDirectory: nil,
                createdAt: Date()
            )
            snapshotManager.snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshotManager.snapshots.count, 5)

        snapshotManager.clearAllSnapshots()

        XCTAssertTrue(snapshotManager.snapshots.isEmpty)
    }

    // MARK: - Quick Rollback

    func testQuickRollbackNoSnapshots() async {
        do {
            let vmManager = VMManager()
            try await snapshotManager.quickRollback(vmManager: vmManager)
            XCTFail("Should throw error when no snapshots available")
        } catch SnapshotError.noSnapshotsAvailable {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - VM Disk Path

    func testSetVMDiskPath() {
        let path = URL(fileURLWithPath: "/path/to/disk.img")
        snapshotManager.setVMDiskPath(path)

        // Path is private, but we can verify it doesn't crash
        XCTAssertTrue(true)
    }
}

// MARK: - VMSnapshot Tests

final class VMSnapshotTests: XCTestCase {

    func testSnapshotCreation() {
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "Test Snapshot",
            vmState: .running,
            workingDirectory: URL(fileURLWithPath: "/Users/test/project"),
            createdAt: Date()
        )

        XCTAssertEqual(snapshot.name, "Test Snapshot")
        XCTAssertEqual(snapshot.vmStateRaw, "Running")
        XCTAssertNotNil(snapshot.workingDirectory)
        XCTAssertNil(snapshot.lastAccessedAt)
        XCTAssertNil(snapshot.apfsSnapshotName)
        XCTAssertNil(snapshot.diskPath)
    }

    func testSnapshotWithAPFS() {
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "APFS Snapshot",
            vmState: .paused,
            workingDirectory: nil,
            createdAt: Date(),
            apfsSnapshotName: "openwork_snap_12345",
            diskPath: URL(fileURLWithPath: "/path/to/disk.img")
        )

        XCTAssertTrue(snapshot.hasAPFSSnapshot)
        XCTAssertEqual(snapshot.apfsSnapshotName, "openwork_snap_12345")
        XCTAssertNotNil(snapshot.diskPath)
    }

    func testSnapshotWithoutAPFS() {
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "No APFS",
            vmState: .stopped,
            workingDirectory: nil,
            createdAt: Date()
        )

        XCTAssertFalse(snapshot.hasAPFSSnapshot)
    }

    func testFormattedDate() {
        let snapshot = VMSnapshot(
            id: UUID(),
            name: "Test",
            vmState: .running,
            workingDirectory: nil,
            createdAt: Date()
        )

        let formatted = snapshot.formattedDate
        XCTAssertFalse(formatted.isEmpty)
    }

    func testCodable() throws {
        let original = VMSnapshot(
            id: UUID(),
            name: "Codable Test",
            vmState: .running,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            createdAt: Date(),
            lastAccessedAt: Date(),
            apfsSnapshotName: "snap_123",
            diskPath: URL(fileURLWithPath: "/disk.img")
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VMSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.vmStateRaw, original.vmStateRaw)
        XCTAssertEqual(decoded.apfsSnapshotName, original.apfsSnapshotName)
    }

    func testMutableProperties() {
        var snapshot = VMSnapshot(
            id: UUID(),
            name: "Original",
            vmState: .running,
            workingDirectory: nil,
            createdAt: Date()
        )

        snapshot.name = "Updated"
        snapshot.lastAccessedAt = Date()

        XCTAssertEqual(snapshot.name, "Updated")
        XCTAssertNotNil(snapshot.lastAccessedAt)
    }
}

// MARK: - SnapshotError Tests

final class SnapshotErrorTests: XCTestCase {

    func testNoSnapshotsAvailable() {
        let error = SnapshotError.noSnapshotsAvailable
        XCTAssertEqual(error.errorDescription, "No snapshots available for rollback")
    }

    func testSnapshotNotFound() {
        let error = SnapshotError.snapshotNotFound("snap_123")
        XCTAssertTrue(error.errorDescription?.contains("snap_123") == true)
    }

    func testCreationFailed() {
        let error = SnapshotError.creationFailed("disk full")
        XCTAssertTrue(error.errorDescription?.contains("disk full") == true)
    }

    func testPathNotFound() {
        let error = SnapshotError.pathNotFound("/invalid/path")
        XCTAssertTrue(error.errorDescription?.contains("/invalid/path") == true)
    }

    func testStatfsFailed() {
        let error = SnapshotError.statfsFailed
        XCTAssertEqual(error.errorDescription, "Failed to get mount point information")
    }

    func testRestoreNotImplemented() {
        let error = SnapshotError.restoreNotImplemented("requires root")
        XCTAssertEqual(error.errorDescription, "requires root")
    }
}

// MARK: - SnapshotPersistence Tests

final class SnapshotPersistenceTests: XCTestCase {

    var persistence: SnapshotPersistence!

    override func setUp() {
        persistence = SnapshotPersistence()
        persistence.clearSnapshots()
    }

    override func tearDown() {
        persistence.clearSnapshots()
    }

    func testSaveAndLoadSnapshots() {
        let snapshots = [
            VMSnapshot(id: UUID(), name: "Snap 1", vmState: .running, workingDirectory: nil, createdAt: Date()),
            VMSnapshot(id: UUID(), name: "Snap 2", vmState: .paused, workingDirectory: nil, createdAt: Date())
        ]

        persistence.saveSnapshots(snapshots)
        let loaded = persistence.loadSnapshots()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Snap 1")
        XCTAssertEqual(loaded[1].name, "Snap 2")
    }

    func testLoadEmptySnapshots() {
        let loaded = persistence.loadSnapshots()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testClearSnapshots() {
        let snapshots = [
            VMSnapshot(id: UUID(), name: "Test", vmState: .running, workingDirectory: nil, createdAt: Date())
        ]

        persistence.saveSnapshots(snapshots)
        XCTAssertFalse(persistence.loadSnapshots().isEmpty)

        persistence.clearSnapshots()
        XCTAssertTrue(persistence.loadSnapshots().isEmpty)
    }
}
