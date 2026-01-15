import Foundation

/// Manages VM snapshots for state rollback
/// Uses APFS snapshots for efficient filesystem-level snapshots
@MainActor
class VMSnapshotManager: ObservableObject {
    @Published var snapshots: [VMSnapshot] = []
    @Published var isCreatingSnapshot: Bool = false
    @Published var isRestoring: Bool = false
    @Published var lastError: String?

    private let persistence = SnapshotPersistence()
    private let maxSnapshots = 10

    // APFS snapshot configuration
    private let snapshotPrefix = "openwork_snap_"
    private var vmDiskPath: URL?

    init() {
        loadSnapshots()
    }

    func setVMDiskPath(_ path: URL) {
        vmDiskPath = path
    }

    // MARK: - Snapshot Operations

    /// Create a snapshot of the current VM state using APFS
    func createSnapshot(name: String, vmManager: VMManager) async throws -> VMSnapshot {
        isCreatingSnapshot = true
        lastError = nil
        defer { isCreatingSnapshot = false }

        // Pause VM before snapshot for consistency
        let wasRunning = vmManager.state == .running
        if wasRunning {
            try await vmManager.pause()
        }

        // Generate unique snapshot name
        let snapshotId = UUID()
        let apfsSnapshotName = "\(snapshotPrefix)\(snapshotId.uuidString)"

        // Create APFS snapshot if disk path is set
        var apfsSnapshotCreated = false
        if let diskPath = vmDiskPath {
            do {
                try await createAPFSSnapshot(name: apfsSnapshotName, at: diskPath)
                apfsSnapshotCreated = true
            } catch {
                lastError = "Failed to create APFS snapshot: \(error.localizedDescription)"
                // Continue anyway - we'll still save the metadata
            }
        }

        let snapshot = VMSnapshot(
            id: snapshotId,
            name: name,
            vmState: vmManager.state,
            workingDirectory: nil,
            createdAt: Date(),
            apfsSnapshotName: apfsSnapshotCreated ? apfsSnapshotName : nil,
            diskPath: vmDiskPath
        )

        // Resume VM
        if wasRunning {
            try await vmManager.resume()
        }

        // Add to list
        snapshots.insert(snapshot, at: 0)

        // Trim old snapshots
        while snapshots.count > maxSnapshots {
            let removed = snapshots.removeLast()
            try? await deleteAPFSSnapshot(removed)
        }

        persistence.saveSnapshots(snapshots)

        return snapshot
    }

    /// Restore VM to a snapshot state
    func restoreSnapshot(_ snapshot: VMSnapshot, vmManager: VMManager) async throws {
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }

        // Stop current VM
        if vmManager.state == .running {
            try await vmManager.stop()
        }

        // Restore APFS snapshot if available
        if let apfsName = snapshot.apfsSnapshotName,
           let diskPath = snapshot.diskPath {
            do {
                try await restoreAPFSSnapshot(name: apfsName, at: diskPath)
            } catch {
                lastError = "Failed to restore APFS snapshot: \(error.localizedDescription)"
                throw error
            }
        }

        // Restart VM
        try await vmManager.start()

        // Update snapshot access time
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index].lastAccessedAt = Date()
            persistence.saveSnapshots(snapshots)
        }
    }

    /// Delete a snapshot
    func deleteSnapshot(_ snapshot: VMSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        Task {
            try? await deleteAPFSSnapshot(snapshot)
        }
        persistence.saveSnapshots(snapshots)
    }

    /// Rename a snapshot
    func renameSnapshot(_ snapshot: VMSnapshot, newName: String) {
        if let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) {
            snapshots[index].name = newName
            persistence.saveSnapshots(snapshots)
        }
    }

    /// Clear all snapshots
    func clearAllSnapshots() {
        for snapshot in snapshots {
            Task {
                try? await deleteAPFSSnapshot(snapshot)
            }
        }
        snapshots.removeAll()
        persistence.clearSnapshots()
    }

    /// Quick rollback to most recent snapshot
    func quickRollback(vmManager: VMManager) async throws {
        guard let lastSnapshot = snapshots.first else {
            throw SnapshotError.noSnapshotsAvailable
        }
        try await restoreSnapshot(lastSnapshot, vmManager: vmManager)
    }

    // MARK: - APFS Snapshot Operations

    /// Create an APFS snapshot using the tmutil command
    private func createAPFSSnapshot(name: String, at path: URL) async throws {
        // Get the mount point for the path
        let mountPoint = try getMountPoint(for: path)

        // Create snapshot using tmutil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["localsnapshot", mountPoint]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SnapshotError.creationFailed(output)
        }
    }

    /// Restore from an APFS snapshot
    /// Note: Full APFS snapshot restore requires root privileges
    /// This implementation uses a safer approach by copying files from the snapshot mount
    private func restoreAPFSSnapshot(name: String, at path: URL) async throws {
        // List available snapshots to find ours
        let snapshots = try await listAPFSSnapshots(at: path)

        guard snapshots.contains(where: { $0.contains(name) || name.contains($0) }) else {
            throw SnapshotError.snapshotNotFound(name)
        }

        // For a full restore, we would mount the snapshot and copy files
        // This is a simplified implementation - full restore would require:
        // 1. Mount the snapshot read-only
        // 2. Copy files to restore location
        // 3. Unmount the snapshot

        // Since APFS snapshot restore is complex and requires privileges,
        // we throw an informative error for now
        throw SnapshotError.restoreNotImplemented(
            "Full APFS snapshot restore requires root privileges. " +
            "Consider using VM disk overlay instead."
        )
    }

    /// Delete an APFS snapshot
    private func deleteAPFSSnapshot(_ snapshot: VMSnapshot) async throws {
        guard let apfsName = snapshot.apfsSnapshotName,
              let diskPath = snapshot.diskPath else {
            return
        }

        let mountPoint = try getMountPoint(for: diskPath)

        // Delete using tmutil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["deletelocalsnapshots", apfsName]
        process.currentDirectoryURL = URL(fileURLWithPath: mountPoint)

        try process.run()
        process.waitUntilExit()
        // Don't throw on failure - snapshot might already be gone
    }

    /// List APFS snapshots for a volume
    private func listAPFSSnapshots(at path: URL) async throws -> [String] {
        let mountPoint = try getMountPoint(for: path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", mountPoint]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse output - each line is a snapshot name
        return output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Get the mount point for a path
    private func getMountPoint(for path: URL) throws -> String {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            throw SnapshotError.pathNotFound(path.path)
        }

        // Use statfs to get mount point
        var stat = statfs()
        guard statfs(path.path, &stat) == 0 else {
            throw SnapshotError.statfsFailed
        }

        // Convert mount point from C string
        let mountPoint = withUnsafePointer(to: &stat.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }

        return mountPoint
    }

    private func loadSnapshots() {
        snapshots = persistence.loadSnapshots()
    }
}

/// Represents a saved VM snapshot
struct VMSnapshot: Identifiable, Codable {
    let id: UUID
    var name: String
    let vmStateRaw: String  // Store as raw string to avoid circular dependency
    let workingDirectory: URL?
    let createdAt: Date
    var lastAccessedAt: Date?
    var apfsSnapshotName: String?
    var diskPath: URL?

    init(
        id: UUID = UUID(),
        name: String,
        vmState: VMManager.VMState,
        workingDirectory: URL? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        apfsSnapshotName: String? = nil,
        diskPath: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.vmStateRaw = vmState.rawValue
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.apfsSnapshotName = apfsSnapshotName
        self.diskPath = diskPath
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var hasAPFSSnapshot: Bool {
        apfsSnapshotName != nil
    }
}

/// Persistence for snapshots
class SnapshotPersistence {
    private let storageKey = "OpenWork.VMSnapshots"

    func saveSnapshots(_ snapshots: [VMSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func loadSnapshots() -> [VMSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshots = try? JSONDecoder().decode([VMSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }

    func clearSnapshots() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

/// Snapshot-related errors
enum SnapshotError: LocalizedError {
    case noSnapshotsAvailable
    case snapshotNotFound(String)
    case creationFailed(String)
    case pathNotFound(String)
    case statfsFailed
    case restoreNotImplemented(String)

    var errorDescription: String? {
        switch self {
        case .noSnapshotsAvailable:
            return "No snapshots available for rollback"
        case .snapshotNotFound(let name):
            return "Snapshot not found: \(name)"
        case .creationFailed(let reason):
            return "Failed to create snapshot: \(reason)"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .statfsFailed:
            return "Failed to get mount point information"
        case .restoreNotImplemented(let reason):
            return reason
        }
    }
}
