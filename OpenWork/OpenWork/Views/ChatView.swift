import SwiftUI

/// A single message in the chat
struct ChatMessageItem: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date
    var toolCalls: [ToolCall]?
    var isStreaming: Bool = false
}

/// Chat interface for conversational interactions
struct ChatView: View {
    @State private var messages: [ChatMessageItem] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @EnvironmentObject var providerManager: ProviderManager

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $inputText)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 120)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    messages.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(messages.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                if let provider = providerManager.activeProvider {
                    Text(provider.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        let userMessage = ChatMessageItem(
            role: "user",
            content: text,
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""

        guard let provider = providerManager.activeProvider else {
            messages.append(ChatMessageItem(
                role: "assistant",
                content: "Error: No active provider configured. Please configure a provider in Settings.",
                timestamp: Date()
            ))
            return
        }

        isLoading = true

        Task {
            do {
                let response = try await callLLM(provider: provider, userMessage: text)

                await MainActor.run {
                    let assistantMessage = ChatMessageItem(
                        role: "assistant",
                        content: response,
                        timestamp: Date()
                    )
                    messages.append(assistantMessage)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessageItem(
                        role: "assistant",
                        content: "Error: \(error.localizedDescription)",
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }

    private func callLLM(provider: LLMProviderConfig, userMessage: String) async throws -> String {
        guard let url = provider.chatCompletionsURL else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if !provider.apiKey.isEmpty {
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Build messages array from chat history
        var chatMessages: [[String: String]] = []
        for msg in messages {
            chatMessages.append(["role": msg.role, "content": msg.content])
        }
        chatMessages.append(["role": "user", "content": userMessage])

        var body: [String: Any] = [
            "model": provider.model,
            "messages": chatMessages,
            "stream": false
        ]

        if provider.apiFormat == .openAICompatible {
            body["max_tokens"] = 4096
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "LLM", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Parse response based on API format
        if provider.apiFormat == .ollamaNative {
            // Ollama native format
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        } else {
            // OpenAI format
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }

        return "Unable to parse response"
    }
}

/// Message bubble component
struct MessageBubble: View {
    let message: ChatMessageItem

    var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(isUser ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(12)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(ProviderManager())
}
