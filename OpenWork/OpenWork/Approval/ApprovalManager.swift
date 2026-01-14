import Foundation
import SwiftUI

/// Manages the approval workflow for tool executions
@MainActor
class ApprovalManager: ObservableObject {
    @Published var pendingApprovals: [ApprovalRequest] = []
    @Published var approvalHistory: [ApprovalHistoryEntry] = []
    @Published var isShowingApproval: Bool = false
    @Published var currentApproval: ApprovalRequest?
    
    private var continuations: [UUID: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private let policy: ApprovalPolicy
    
    init(policy: ApprovalPolicy = ApprovalPolicy()) {
        self.policy = policy
    }
    
    /// Request approval for a tool execution. Suspends until user approves or denies.
    func requestApproval(
        tool: any Tool,
        args: [String: Any],
        workingDirectory: URL
    ) async -> ApprovalDecision {
        // Check if auto-approved by policy
        if let autoDecision = policy.evaluate(
            toolID: tool.id,
            args: args,
            workingDirectory: workingDirectory
        ) {
            recordHistory(
                toolID: tool.id,
                toolName: tool.name,
                decision: autoDecision,
                wasAutoApproved: true
            )
            return autoDecision
        }
        
        // Create pending request
        let request = ApprovalRequest(
            id: UUID(),
            toolID: tool.id,
            toolName: tool.name,
            category: tool.category,
            args: args,
            workingDirectory: workingDirectory,
            timestamp: Date()
        )
        
        pendingApprovals.append(request)
        currentApproval = request
        isShowingApproval = true
        
        // Suspend until user makes a decision
        let decision = await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
        }
        
        // Record in history
        recordHistory(
            toolID: tool.id,
            toolName: tool.name,
            decision: decision,
            wasAutoApproved: false
        )
        
        return decision
    }
    
    /// Approve the current request
    func approve(_ id: UUID, remember: Bool = false) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        
        // Find and remove from pending
        if let request = pendingApprovals.first(where: { $0.id == id }) {
            pendingApprovals.removeAll { $0.id == id }
            
            // Add auto-approve rule if requested
            if remember {
                policy.addRule(from: request)
            }
        }
        
        // Clear current if this was it
        if currentApproval?.id == id {
            currentApproval = nil
            isShowingApproval = false
        }
        
        // Show next pending if any
        if let next = pendingApprovals.first {
            currentApproval = next
            isShowingApproval = true
        }
        
        continuation.resume(returning: .approved(remember: remember))
    }
    
    /// Deny the current request
    func deny(_ id: UUID, reason: String? = nil) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        
        pendingApprovals.removeAll { $0.id == id }
        
        // Clear current if this was it
        if currentApproval?.id == id {
            currentApproval = nil
            isShowingApproval = false
        }
        
        // Show next pending if any
        if let next = pendingApprovals.first {
            currentApproval = next
            isShowingApproval = true
        }
        
        continuation.resume(returning: .denied(reason: reason))
    }
    
    /// Approve all pending requests
    func approveAll() {
        for request in pendingApprovals {
            if let continuation = continuations.removeValue(forKey: request.id) {
                recordHistory(
                    toolID: request.toolID,
                    toolName: request.toolName,
                    decision: .approved(remember: false),
                    wasAutoApproved: false
                )
                continuation.resume(returning: .approved(remember: false))
            }
        }
        pendingApprovals.removeAll()
        currentApproval = nil
        isShowingApproval = false
    }
    
    /// Deny all pending requests
    func denyAll() {
        for request in pendingApprovals {
            if let continuation = continuations.removeValue(forKey: request.id) {
                recordHistory(
                    toolID: request.toolID,
                    toolName: request.toolName,
                    decision: .denied(reason: "Denied all"),
                    wasAutoApproved: false
                )
                continuation.resume(returning: .denied(reason: "Denied all"))
            }
        }
        pendingApprovals.removeAll()
        currentApproval = nil
        isShowingApproval = false
    }
    
    /// Get the approval policy for rule management
    var approvalPolicy: ApprovalPolicy {
        policy
    }
    
    // MARK: - History
    
    private func recordHistory(toolID: String, toolName: String, decision: ApprovalDecision, wasAutoApproved: Bool) {
        let entry = ApprovalHistoryEntry(
            id: UUID(),
            toolID: toolID,
            toolName: toolName,
            wasApproved: decision.isApproved,
            wasAutoApproved: wasAutoApproved,
            timestamp: Date()
        )
        
        approvalHistory.insert(entry, at: 0)
        
        // Keep only last 100 entries
        if approvalHistory.count > 100 {
            approvalHistory = Array(approvalHistory.prefix(100))
        }
    }
}

/// Entry in the approval history
struct ApprovalHistoryEntry: Identifiable {
    let id: UUID
    let toolID: String
    let toolName: String
    let wasApproved: Bool
    let wasAutoApproved: Bool
    let timestamp: Date
}
