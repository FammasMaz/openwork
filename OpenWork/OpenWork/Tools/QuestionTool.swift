import Foundation

/// Tool that allows the agent to ask the user questions during execution
/// Inspired by OpenCode's question-asking feature
class QuestionTool: Tool {
    let id = "question"
    let name = "Ask Question"
    let description = """
        Use this tool when you need to ask the user questions during execution. This allows you to:
        1. Gather user preferences or requirements
        2. Clarify ambiguous instructions
        3. Get decisions on implementation choices as you work
        4. Offer choices to the user about what direction to take.
        
        Users will always be able to select "Other" to provide custom text input.
        """
    
    let inputSchema: JSONSchema = JSONSchema(
        type: "object",
        properties: [
            "questions": PropertySchema(
                type: "array",
                description: "Questions to ask",
                items: PropertySchema(type: "object")
            )
        ],
        required: ["questions"]
    )
    
    let requiresApproval = false
    let category: ToolCategory = .system
    
    private weak var questionManager: QuestionManager?
    
    init(questionManager: QuestionManager?) {
        self.questionManager = questionManager
    }
    
    func execute(args: [String: Any], context: ToolContext) async throws -> ToolResult {
        guard let manager = questionManager else {
            return ToolResult.error("Question manager not available")
        }
        
        guard let questionsArray = args["questions"] as? [[String: Any]] else {
            return ToolResult.error("Missing 'questions' array in arguments")
        }
        
        var allAnswers: [[String: Any]] = []
        
        for questionDict in questionsArray {
            guard let header = questionDict["header"] as? String,
                  let question = questionDict["question"] as? String,
                  let optionsArray = questionDict["options"] as? [[String: Any]] else {
                continue
            }
            
            let allowMultiple = questionDict["multiple"] as? Bool ?? false
            
            // Parse options
            var options: [QuestionOption] = optionsArray.compactMap { optDict in
                guard let label = optDict["label"] as? String else { return nil }
                let description = optDict["description"] as? String ?? ""
                return QuestionOption(label: label, description: description)
            }
            
            // Always add "Other" option
            options.append(QuestionOption(label: "Other", description: "Provide custom input"))
            
            // Ask the question and wait for answer
            let answer = await manager.askQuestion(
                header: String(header.prefix(12)),
                question: question,
                options: options,
                allowMultiple: allowMultiple
            )
            
            allAnswers.append([
                "question": question,
                "answer": answer.selectedLabels,
                "customText": answer.customText as Any
            ])
        }
        
        // Format response for the agent
        var responseText = "User responses:\n"
        for answerDict in allAnswers {
            if let question = answerDict["question"] as? String,
               let answers = answerDict["answer"] as? [String] {
                responseText += "\nQ: \(question)\n"
                responseText += "A: \(answers.joined(separator: ", "))"
                if let custom = answerDict["customText"] as? String, !custom.isEmpty {
                    responseText += " - \(custom)"
                }
                responseText += "\n"
            }
        }
        
        return ToolResult(
            title: "Questions Answered",
            output: responseText,
            metadata: ["answers": allAnswers]
        )
    }
}
