import Foundation
import SwiftUI

/// Central authority for managing folder permissions and path validation
@MainActor
class PermissionManager: ObservableObject {
    @Published var allowedFolders: [FolderPermission] = []
    @Published var activeAccessURLs: Set<URL> = []
    
    private let bookmarkStore = SecurityBookmarks()
    private let storageKey = "OpenWork.FolderPermissions"
    
    init() {
        loadPersistedFolders()
    }
    
    // MARK: - Path Validation
    
    /// Check if a path is within allowed folders
    func isPathAllowed(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return allowedFolders.contains { folder in
            guard folder.isActive else { return false }
            let folderPath = folder.url.standardizedFileURL.path
            return url.path.hasPrefix(folderPath)
        }
    }
    
    /// Check if a path is allowed for writing
    func isWriteAllowed(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return allowedFolders.contains { folder in
            guard folder.isActive && !folder.isReadOnly else { return false }
            let folderPath = folder.url.standardizedFileURL.path
            return url.path.hasPrefix(folderPath)
        }
    }
    
    /// Get the permission for a path if it exists
    func permission(for path: String) -> FolderPermission? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return allowedFolders.first { folder in
            guard folder.isActive else { return false }
            let folderPath = folder.url.standardizedFileURL.path
            return url.path.hasPrefix(folderPath)
        }
    }
    
    // MARK: - Folder Management
    
    /// Add a new allowed folder from a user-selected URL
    func addFolder(_ url: URL, readOnly: Bool = false) throws {
        // Start access to create bookmark
        guard url.startAccessingSecurityScopedResource() else {
            throw PermissionError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Create security-scoped bookmark
        let bookmark: Data
        if readOnly {
            bookmark = try bookmarkStore.createBookmark(for: url)
        } else {
            bookmark = try bookmarkStore.createReadWriteBookmark(for: url)
        }
        
        // Check if already exists
        if allowedFolders.contains(where: { $0.url.path == url.path }) {
            // Update existing
            if let index = allowedFolders.firstIndex(where: { $0.url.path == url.path }) {
                allowedFolders[index] = FolderPermission(
                    id: allowedFolders[index].id,
                    url: url,
                    bookmark: bookmark,
                    isReadOnly: readOnly,
                    isActive: true,
                    addedAt: allowedFolders[index].addedAt
                )
            }
        } else {
            // Add new
            let permission = FolderPermission(
                url: url,
                bookmark: bookmark,
                isReadOnly: readOnly
            )
            allowedFolders.append(permission)
        }
        
        savePersistedFolders()
    }
    
    /// Remove a folder permission
    func removeFolder(_ permission: FolderPermission) {
        // Stop access if active
        if activeAccessURLs.contains(permission.url) {
            bookmarkStore.stopAccessing(permission.url)
            activeAccessURLs.remove(permission.url)
        }
        
        allowedFolders.removeAll { $0.id == permission.id }
        savePersistedFolders()
    }
    
    /// Toggle a folder's active state
    func toggleFolder(_ permission: FolderPermission) {
        guard let index = allowedFolders.firstIndex(where: { $0.id == permission.id }) else { return }
        
        var updated = allowedFolders[index]
        updated.isActive.toggle()
        
        // If deactivating, stop access
        if !updated.isActive && activeAccessURLs.contains(updated.url) {
            bookmarkStore.stopAccessing(updated.url)
            activeAccessURLs.remove(updated.url)
        }
        
        allowedFolders[index] = updated
        savePersistedFolders()
    }
    
    /// Toggle read-only state
    func setReadOnly(_ permission: FolderPermission, readOnly: Bool) {
        guard let index = allowedFolders.firstIndex(where: { $0.id == permission.id }) else { return }
        
        var updated = allowedFolders[index]
        updated.isReadOnly = readOnly
        allowedFolders[index] = updated
        savePersistedFolders()
    }
    
    // MARK: - Access Management
    
    /// Start accessing all active folders (call on app launch)
    func startAccessingAllFolders() {
        for permission in allowedFolders where permission.isActive {
            do {
                let url = try bookmarkStore.resolveBookmark(permission.bookmark)
                if bookmarkStore.startAccessing(url) {
                    activeAccessURLs.insert(url)
                }
            } catch {
                print("[PermissionManager] Failed to access folder: \(permission.displayPath)")
            }
        }
    }
    
    /// Stop accessing all folders (call on app termination)
    func stopAccessingAllFolders() {
        for url in activeAccessURLs {
            bookmarkStore.stopAccessing(url)
        }
        activeAccessURLs.removeAll()
    }
    
    /// Access a specific folder for a scoped operation
    func accessFolder(_ permission: FolderPermission) throws -> URL {
        let url = try bookmarkStore.resolveBookmark(permission.bookmark)
        if bookmarkStore.startAccessing(url) {
            activeAccessURLs.insert(url)
            return url
        }
        throw PermissionError.accessDenied
    }
    
    // MARK: - Persistence
    
    private func loadPersistedFolders() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FolderPermission].self, from: data) else {
            return
        }
        allowedFolders = decoded
    }
    
    private func savePersistedFolders() {
        guard let data = try? JSONEncoder().encode(allowedFolders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
