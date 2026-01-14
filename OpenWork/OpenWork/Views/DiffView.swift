import SwiftUI

/// View for displaying file diffs
struct DiffView: View {
    let originalContent: String
    let modifiedContent: String
    let filePath: String
    
    private var diffResult: DiffResult {
        DiffEngine.diff(original: originalContent, modified: modifiedContent)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                    .fontWeight(.medium)
                Spacer()
                Text(DiffEngine.summary(original: originalContent, modified: modifiedContent))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Diff content
            if diffResult.isIdentical {
                Text("No changes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diffResult.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line)
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

/// View for a single diff line
struct DiffLineView: View {
    let line: DiffLine
    
    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(lineNumberText)
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)
            
            // Prefix (+, -, space)
            Text(prefix)
                .frame(width: 20)
                .foregroundColor(prefixColor)
            
            // Content
            Text(line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }
    
    private var lineNumberText: String {
        if line.lineNumber < 0 {
            return ""
        }
        return "\(line.lineNumber)"
    }
    
    private var prefix: String {
        switch line {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }
    
    private var prefixColor: Color {
        switch line {
        case .context: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }
    
    private var backgroundColor: Color {
        switch line {
        case .context: return .clear
        case .added: return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        }
    }
}

/// Compact diff preview for approval dialogs
struct DiffPreview: View {
    let filePath: String
    let newContent: String?
    
    @State private var originalContent: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = error {
                Text(error)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let newContent = newContent {
                DiffView(
                    originalContent: originalContent,
                    modifiedContent: newContent,
                    filePath: filePath
                )
                .frame(maxHeight: 300)
            }
        }
        .task {
            await loadOriginalContent()
        }
    }
    
    private func loadOriginalContent() async {
        let url = URL(fileURLWithPath: filePath)
        
        do {
            if FileManager.default.fileExists(atPath: filePath) {
                originalContent = try String(contentsOf: url, encoding: .utf8)
            } else {
                originalContent = ""
                error = "New file"
            }
        } catch {
            self.error = "Could not read original file"
            originalContent = ""
        }
        
        isLoading = false
    }
}

#Preview {
    VStack {
        DiffView(
            originalContent: """
            line 1
            line 2
            line 3
            line 4
            """,
            modifiedContent: """
            line 1
            line 2 modified
            line 3
            new line
            line 4
            """,
            filePath: "/path/to/file.txt"
        )
        .frame(height: 200)
        .padding()
    }
}
