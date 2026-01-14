import SwiftUI

/// View for displaying agent questions to the user
struct QuestionSheet: View {
    @ObservedObject var questionManager: QuestionManager
    
    @State private var selectedOptions: Set<String> = []
    @State private var customText: String = ""
    @State private var showCustomInput: Bool = false
    
    var body: some View {
        if let question = questionManager.pendingQuestion {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(question.header)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Question from Agent")
                            .font(.headline)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Question text
                Text(question.question)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Options
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(question.options) { option in
                        OptionRow(
                            option: option,
                            isSelected: selectedOptions.contains(option.label),
                            allowMultiple: question.allowMultiple,
                            onToggle: {
                                toggleOption(option.label, allowMultiple: question.allowMultiple)
                            }
                        )
                    }
                }
                
                // Custom input for "Other"
                if showCustomInput {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your response:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Type your answer...", text: $customText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Divider()
                
                // Actions
                HStack {
                    Button("Skip") {
                        questionManager.skipQuestion()
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("Submit") {
                        submitAnswer()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedOptions.isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(24)
            .frame(minWidth: 450, maxWidth: 550)
            .onAppear {
                selectedOptions = []
                customText = ""
                showCustomInput = false
            }
        }
    }
    
    private func toggleOption(_ label: String, allowMultiple: Bool) {
        if allowMultiple {
            if selectedOptions.contains(label) {
                selectedOptions.remove(label)
            } else {
                selectedOptions.insert(label)
            }
        } else {
            selectedOptions = [label]
        }
        
        // Show custom input if "Other" is selected
        showCustomInput = selectedOptions.contains("Other")
    }
    
    private func submitAnswer() {
        let custom = showCustomInput && !customText.isEmpty ? customText : nil
        questionManager.submitAnswer(
            selectedLabels: Array(selectedOptions),
            customText: custom
        )
    }
}

/// Row for a single option
struct OptionRow: View {
    let option: QuestionOption
    let isSelected: Bool
    let allowMultiple: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: selectionIcon)
                    .foregroundColor(isSelected ? .blue : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .fontWeight(isSelected ? .medium : .regular)
                    
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var selectionIcon: String {
        if allowMultiple {
            return isSelected ? "checkmark.square.fill" : "square"
        } else {
            return isSelected ? "largecircle.fill.circle" : "circle"
        }
    }
}

/// Overlay modifier for showing question sheets
struct QuestionOverlay: ViewModifier {
    @ObservedObject var questionManager: QuestionManager
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $questionManager.isShowingQuestion) {
                QuestionSheet(questionManager: questionManager)
            }
    }
}

extension View {
    func questionOverlay(_ manager: QuestionManager) -> some View {
        modifier(QuestionOverlay(questionManager: manager))
    }
}

#Preview {
    let manager = QuestionManager()
    
    return VStack {
        Button("Ask Question") {
            Task {
                _ = await manager.askQuestion(
                    header: "Framework",
                    question: "Which UI framework would you like to use for this project?",
                    options: [
                        QuestionOption(label: "SwiftUI", description: "Modern declarative UI framework"),
                        QuestionOption(label: "UIKit", description: "Traditional imperative framework"),
                        QuestionOption(label: "AppKit", description: "macOS native framework")
                    ]
                )
            }
        }
    }
    .questionOverlay(manager)
    .frame(width: 300, height: 200)
}
