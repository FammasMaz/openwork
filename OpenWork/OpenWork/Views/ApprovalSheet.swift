import SwiftUI

/// Modal sheet for approving or denying tool executions
struct ApprovalSheet: View {
    @EnvironmentObject var approvalManager: ApprovalManager
    let request: ApprovalRequest
    
    @State private var rememberChoice: Bool = false
    @State private var denyReason: String = ""
    @State private var showDenyReason: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerView
            
            Divider()
            
            // Details
            detailsView
            
            // Diff preview for file operations
            if request.toolID == "write" || request.toolID == "edit" {
                diffPreviewView
            }
            
            // Command preview for bash
            if request.toolID == "bash", let command = request.command {
                commandPreviewView(command: command)
            }
            
            Divider()
            
            // Remember choice toggle
            Toggle("Remember this choice for similar actions", isOn: $rememberChoice)
                .font(.callout)
            
            // Action buttons
            actionButtons
        }
        .padding(24)
        .frame(minWidth: 500, maxWidth: 600)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: iconForCategory)
                .font(.system(size: 32))
                .foregroundColor(colorForCategory)
                .frame(width: 48, height: 48)
                .background(colorForCategory.opacity(0.15))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Approval Required")
                    .font(.headline)
                Text(request.actionDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Category badge
            Text(request.category.rawValue.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorForCategory.opacity(0.2))
                .foregroundColor(colorForCategory)
                .cornerRadius(4)
        }
    }
    
    // MARK: - Details
    
    private var detailsView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Tool", value: request.toolName)
                
                if let filePath = request.filePath {
                    detailRow(label: "File", value: filePath)
                }
                
                if request.toolID == "bash", let command = request.command {
                    detailRow(label: "Command", value: String(command.prefix(100)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Action Details")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .font(.callout)
    }
    
    // MARK: - Diff Preview
    
    @ViewBuilder
    private var diffPreviewView: some View {
        if let filePath = request.filePath {
            GroupBox {
                DiffPreview(filePath: filePath, newContent: request.newContent)
            } label: {
                Text("Changes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Command Preview
    
    private func commandPreviewView(command: String) -> some View {
        GroupBox {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 100)
        } label: {
            Text("Command")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Deny button
            Button(action: {
                if showDenyReason && !denyReason.isEmpty {
                    approvalManager.deny(request.id, reason: denyReason)
                } else {
                    approvalManager.deny(request.id, reason: nil)
                }
            }) {
                Text("Deny")
                    .frame(minWidth: 80)
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            // Pending count
            if approvalManager.pendingApprovals.count > 1 {
                Text("\(approvalManager.pendingApprovals.count) pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Approve All") {
                    approvalManager.approveAll()
                }
            }
            
            // Approve button
            Button(action: {
                approvalManager.approve(request.id, remember: rememberChoice)
            }) {
                Text("Approve")
                    .frame(minWidth: 80)
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Helpers
    
    private var iconForCategory: String {
        switch request.category {
        case .read:
            return "doc.text"
        case .write:
            return "pencil"
        case .execute:
            return "terminal"
        case .network:
            return "network"
        case .system:
            return "gearshape"
        case .mcp:
            return "puzzlepiece.extension"
        }
    }

    private var colorForCategory: Color {
        switch request.category {
        case .read:
            return .blue
        case .write:
            return .orange
        case .execute:
            return .red
        case .network:
            return .purple
        case .system:
            return .gray
        case .mcp:
            return .teal
        }
    }
}

/// Overlay modifier for showing approval sheets
struct ApprovalOverlay: ViewModifier {
    @ObservedObject var approvalManager: ApprovalManager
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $approvalManager.isShowingApproval) {
                if let request = approvalManager.currentApproval {
                    ApprovalSheet(request: request)
                        .environmentObject(approvalManager)
                }
            }
    }
}

extension View {
    func approvalOverlay(_ manager: ApprovalManager) -> some View {
        modifier(ApprovalOverlay(approvalManager: manager))
    }
}

#Preview {
    ApprovalSheet(
        request: ApprovalRequest(
            id: UUID(),
            toolID: "write",
            toolName: "Write File",
            category: .write,
            args: [
                "file_path": "/path/to/file.txt",
                "content": "New file content"
            ],
            workingDirectory: URL(fileURLWithPath: "/Users/test"),
            timestamp: Date()
        )
    )
    .environmentObject(ApprovalManager())
}
