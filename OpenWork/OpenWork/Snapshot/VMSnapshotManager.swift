import Foundation

/// Manages VM snapshots for state rollback
@MainActor
class VMSnapshotManager: ObservableObject {
    @Published var snapshots: [VMSnapshot] = []
    @Published var isCreatingSnapshot: Bool = false
    
    private let persistence = SnapshotPersistence()
    private let maxSnapshots = 10
    
    init() {
        loadSnapshots()
    }
    
    // MARK: - Snapshot Operations
    
    /// Create a snapshot of the current VM state
    func createSnapshot(name: String, vmManager: VMManager) async throws -> VMSnapshot {
        isCreatingSnapshot = true
        defer { isCreatingSnapshot = false }
        
        // Pause VM before snapshot
        if vmManager.state == .running {
            try await vmManager.pause()
        }
        
        let snapshot = VMSnapshot(
            name: name,
            vmState: vmManager.state,
            workingDirectory: nil,  // Could capture working directory state
            createdAt: Date()
        )
        
        // For now, we're just recording metadata
        // Full VM state snapshotting would require deeper integration with VZVirtualMachine
        // and filesystem-level snapshot mechanisms
        
        // Resume VM
        try await vmManager.resume()
        
        // Add to list
        snapshots.insert(snapshot, at: 0)
        
        // Trim old snapshots
        if snapshots.count > maxSnapshots {
            let removed = snapshots.removeLast()
            // Clean up snapshot files if any
            try? removeSnapshotFiles(removed)
        }
        
        persistence.saveSnapshots(snapshots)
        
        return snapshot
    }
    
    /// Restore VM to a snapshot state
    func restoreSnapshot(_ snapshot: VMSnapshot, vmManager: VMManager) async throws {
        // Stop current VM
        if vmManager.state == .running {
            try await vmManager.stop()
        }
        
        // In a full implementation, this would:
        // 1. Restore the rootfs overlay from snapshot
        // 2. Restore VM configuration
        // 3. Restart VM with saved state
        
        // For now, just restart the VM
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
        try? removeSnapshotFiles(snapshot)
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
            try? removeSnapshotFiles(snapshot)
        }
        snapshots.removeAll()
        persistence.clearSnapshots()
    }
    
    // MARK: - File Management
    
    private func removeSnapshotFiles(_ snapshot: VMSnapshot) throws {
        // In a full implementation, this would delete the snapshot files
        // For now, just a placeholder
    }
    
    private func loadSnapshots() {
        snapshots = persistence.loadSnapshots()
    }
}

/// Represents a saved VM snapshot
struct VMSnapshot: Identifiable, Codable {
    let id: UUID
    var name: String
    let vmState: VMState
    let workingDirectory: URL?
    let createdAt: Date
    var lastAccessedAt: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        vmState: VMState,
        workingDirectory: URL? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.vmState = vmState
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
    
    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// VM state enum (simplified version matching VMManager)
enum VMState: String, Codable {
    case stopped
    case starting
    case running
    case paused
    case stopping
    case error
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
