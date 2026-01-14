import Foundation

/// Represents a folder that the user has granted access to
struct FolderPermission: Identifiable, Codable {
    let id: UUID
    let url: URL
    let bookmark: Data
    var isReadOnly: Bool
    var isActive: Bool
    let addedAt: Date
    
    init(
        id: UUID = UUID(),
        url: URL,
        bookmark: Data,
        isReadOnly: Bool = false,
        isActive: Bool = true,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.bookmark = bookmark
        self.isReadOnly = isReadOnly
        self.isActive = isActive
        self.addedAt = addedAt
    }
    
    /// Display name (folder name)
    var displayName: String {
        url.lastPathComponent
    }
    
    /// Display path with home directory replaced by ~
    var displayPath: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Errors related to folder permissions
enum PermissionError: LocalizedError {
    case accessDenied
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case pathNotAllowed(String)
    case folderNotFound
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access denied to this folder"
        case .bookmarkCreationFailed:
            return "Failed to create security-scoped bookmark"
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        case .pathNotAllowed(let path):
            return "Path not in allowed folders: \(path)"
        case .folderNotFound:
            return "Folder not found"
        }
    }
}
