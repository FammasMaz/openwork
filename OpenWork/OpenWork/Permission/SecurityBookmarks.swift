import Foundation

/// Manages security-scoped bookmarks for persistent folder access
class SecurityBookmarks {
    
    /// Create a security-scoped bookmark for a URL
    func createBookmark(for url: URL) throws -> Data {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmark
        } catch {
            throw PermissionError.bookmarkCreationFailed
        }
    }
    
    /// Create a read-write security-scoped bookmark
    func createReadWriteBookmark(for url: URL) throws -> Data {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmark
        } catch {
            throw PermissionError.bookmarkCreationFailed
        }
    }
    
    /// Resolve a security-scoped bookmark to a URL
    func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            // If stale, caller should recreate the bookmark
            if isStale {
                print("[SecurityBookmarks] Warning: Bookmark is stale and should be recreated")
            }
            
            return url
        } catch {
            throw PermissionError.bookmarkResolutionFailed
        }
    }
    
    /// Start accessing a security-scoped resource
    func startAccessing(_ url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    /// Stop accessing a security-scoped resource
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
