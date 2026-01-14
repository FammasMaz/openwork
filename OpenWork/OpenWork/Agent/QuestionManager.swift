import Foundation
import SwiftUI

/// Represents a question the agent wants to ask the user
struct AgentQuestion: Identifiable {
    let id: UUID
    let header: String
    let question: String
    let options: [QuestionOption]
    let allowMultiple: Bool
    let timestamp: Date
    
    init(
        id: UUID = UUID(),
        header: String,
        question: String,
        options: [QuestionOption],
        allowMultiple: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.allowMultiple = allowMultiple
        self.timestamp = timestamp
    }
}

/// An option in a question
struct QuestionOption: Identifiable, Codable {
    let id: UUID
    let label: String
    let description: String
    
    init(id: UUID = UUID(), label: String, description: String = "") {
        self.id = id
        self.label = label
        self.description = description
    }
}

/// The user's answer to a question
struct QuestionAnswer {
    let questionId: UUID
    let selectedLabels: [String]
    let customText: String?
    
    var isOther: Bool {
        selectedLabels.contains("Other")
    }
    
    var displayAnswer: String {
        if isOther, let custom = customText {
            return custom
        }
        return selectedLabels.joined(separator: ", ")
    }
}

/// Manages the question-answer workflow between agent and user
@MainActor
class QuestionManager: ObservableObject {
    @Published var pendingQuestion: AgentQuestion?
    @Published var isShowingQuestion: Bool = false
    @Published var questionHistory: [(AgentQuestion, QuestionAnswer)] = []
    
    private var continuation: CheckedContinuation<QuestionAnswer, Never>?
    
    /// Ask a question and wait for the user's answer
    func askQuestion(
        header: String,
        question: String,
        options: [QuestionOption],
        allowMultiple: Bool = false
    ) async -> QuestionAnswer {
        let agentQuestion = AgentQuestion(
            header: header,
            question: question,
            options: options,
            allowMultiple: allowMultiple
        )
        
        pendingQuestion = agentQuestion
        isShowingQuestion = true
        
        // Suspend until user answers
        let answer = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        
        // Record in history
        questionHistory.append((agentQuestion, answer))
        
        return answer
    }
    
    /// Submit an answer to the current question
    func submitAnswer(selectedLabels: [String], customText: String? = nil) {
        guard let question = pendingQuestion,
              let continuation = continuation else { return }
        
        let answer = QuestionAnswer(
            questionId: question.id,
            selectedLabels: selectedLabels,
            customText: customText
        )
        
        pendingQuestion = nil
        isShowingQuestion = false
        self.continuation = nil
        
        continuation.resume(returning: answer)
    }
    
    /// Cancel/skip the current question
    func skipQuestion() {
        guard let question = pendingQuestion,
              let continuation = continuation else { return }
        
        let answer = QuestionAnswer(
            questionId: question.id,
            selectedLabels: ["Skipped"],
            customText: nil
        )
        
        pendingQuestion = nil
        isShowingQuestion = false
        self.continuation = nil
        
        continuation.resume(returning: answer)
    }
}
