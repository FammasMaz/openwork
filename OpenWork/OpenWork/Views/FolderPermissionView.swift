import SwiftUI

/// View for managing folder permissions
struct FolderPermissionView: View {
    @ObservedObject var permissionManager: PermissionManager
    @State private var showFolderPicker = false
    @State private var newFolderReadOnly = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder Access")
                        .font(.headline)
                    Text("Manage which folders the agent can access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showFolderPicker = true }) {
                    Label("Add Folder", systemImage: "plus")
                }
            }
            
            Divider()
            
            // Folder list
            if permissionManager.allowedFolders.isEmpty {
                emptyStateView
            } else {
                folderListView
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No folders added")
                .font(.headline)
            
            Text("Add a folder to allow the agent to access files within it")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Add Folder") {
                showFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Folder List
    
    private var folderListView: some View {
        List {
            ForEach(permissionManager.allowedFolders) { permission in
                FolderPermissionRow(
                    permission: permission,
                    onToggle: { permissionManager.toggleFolder(permission) },
                    onSetReadOnly: { readOnly in
                        permissionManager.setReadOnly(permission, readOnly: readOnly)
                    },
                    onRemove: { permissionManager.removeFolder(permission) }
                )
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 200)
    }
    
    // MARK: - Handlers
    
    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try permissionManager.addFolder(url, readOnly: newFolderReadOnly)
            } catch {
                print("Failed to add folder: \(error)")
            }
        case .failure(let error):
            print("Folder picker error: \(error)")
        }
    }
}

/// Row view for a single folder permission
struct FolderPermissionRow: View {
    let permission: FolderPermission
    let onToggle: () -> Void
    let onSetReadOnly: (Bool) -> Void
    let onRemove: () -> Void
    
    @State private var showConfirmRemove = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder icon
            Image(systemName: permission.isActive ? "folder.fill" : "folder")
                .foregroundColor(permission.isActive ? .blue : .secondary)
                .font(.title2)
            
            // Folder info
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .fontWeight(.medium)
                    .foregroundColor(permission.isActive ? .primary : .secondary)
                
                Text(permission.displayPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Read-only badge
            if permission.isReadOnly {
                Text("Read Only")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }
            
            // Active toggle
            Toggle("", isOn: Binding(
                get: { permission.isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            
            // Menu
            Menu {
                Toggle("Read Only", isOn: Binding(
                    get: { permission.isReadOnly },
                    set: { onSetReadOnly($0) }
                ))
                
                Divider()
                
                Button(role: .destructive) {
                    showConfirmRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Remove folder access?",
            isPresented: $showConfirmRemove
        ) {
            Button("Remove", role: .destructive) {
                onRemove()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent will no longer be able to access files in \(permission.displayName)")
        }
    }
}

#Preview {
    FolderPermissionView(permissionManager: PermissionManager())
        .frame(width: 500, height: 400)
}
