import SwiftUI

/// Settings view for managing skills
struct SkillsSettingsView: View {
    @StateObject private var skillRegistry = SkillRegistry.shared
    @State private var selectedSkillId: String?
    @State private var searchQuery: String = ""

    var filteredSkills: [any Skill] {
        if searchQuery.isEmpty {
            return skillRegistry.availableSkills
        }
        return skillRegistry.availableSkills.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        HSplitView {
            // Skills list
            VStack(alignment: .leading, spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search skills", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Category grouped list
                List(selection: $selectedSkillId) {
                    ForEach(SkillCategory.allCases, id: \.self) { category in
                        let skillsInCategory = filteredSkills.filter { $0.category == category }
                        if !skillsInCategory.isEmpty {
                            Section(header: Label(category.rawValue, systemImage: category.icon)) {
                                ForEach(skillsInCategory, id: \.id) { skill in
                                    SkillRowView(skill: skill, isActive: skillRegistry.isActive(skill.id))
                                        .tag(skill.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Summary
                HStack {
                    Text("\(skillRegistry.activeSkills.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(skillRegistry.availableSkills.count) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

            // Detail view
            if let skillId = selectedSkillId,
               let skill = skillRegistry.skill(forID: skillId) {
                SkillDetailView(skill: skill)
            } else {
                VStack {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a skill to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Skills extend the agent's capabilities with specialized knowledge and tools")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Row view for a skill in the list
struct SkillRowView: View {
    let skill: any Skill
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: skill.icon)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .fontWeight(isActive ? .medium : .regular)
                Text(skill.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Detail view for a selected skill
struct SkillDetailView: View {
    let skill: any Skill
    @StateObject private var skillRegistry = SkillRegistry.shared
    @State private var showSystemPrompt: Bool = false

    private var isActive: Bool {
        skillRegistry.isActive(skill.id)
    }

    private var configuration: SkillConfiguration? {
        skillRegistry.configurations[skill.id]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: skill.icon)
                                .font(.title)
                                .foregroundColor(.accentColor)
                            Text(skill.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        Text(skill.description)
                            .foregroundColor(.secondary)

                        HStack {
                            Label(skill.category.rawValue, systemImage: skill.category.icon)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)

                            if skill.enabledByDefault {
                                Label("Enabled by default", systemImage: "checkmark")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { isActive },
                        set: { _ in skillRegistry.toggle(id: skill.id) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                // Tools section
                if !skill.tools.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tools")
                            .font(.headline)

                        ForEach(skill.tools, id: \.id) { tool in
                            HStack {
                                Image(systemName: toolIcon(for: tool.category))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text(tool.name)
                                        .fontWeight(.medium)
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }

                // Configuration section
                if !skill.requiredConfiguration.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configuration")
                            .font(.headline)

                        ForEach(skill.requiredConfiguration) { option in
                            ConfigOptionView(option: option, skillId: skill.id)
                        }
                    }
                }

                // System prompt preview
                if !skill.systemPromptAddition.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { showSystemPrompt.toggle() }
                        } label: {
                            HStack {
                                Text("System Prompt Addition")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: showSystemPrompt ? "chevron.up" : "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)

                        if showSystemPrompt {
                            Text(skill.systemPromptAddition)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toolIcon(for category: ToolCategory) -> String {
        switch category {
        case .read: return "doc.text"
        case .write: return "pencil"
        case .execute: return "terminal"
        case .network: return "network"
        case .system: return "gearshape"
        case .mcp: return "puzzlepiece.extension"
        }
    }
}

/// Configuration option input view
struct ConfigOptionView: View {
    let option: SkillConfigOption
    let skillId: String
    @StateObject private var skillRegistry = SkillRegistry.shared
    @State private var value: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(option.name)
                    .fontWeight(.medium)
                if option.required {
                    Text("*")
                        .foregroundColor(.red)
                }
            }

            Text(option.description)
                .font(.caption)
                .foregroundColor(.secondary)

            switch option.type {
            case .text, .url:
                TextField(option.name, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveValue() }
            case .password:
                SecureField(option.name, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveValue() }
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { value == "true" },
                    set: { value = $0 ? "true" : "false"; saveValue() }
                ))
            case .selection(let options):
                Picker("", selection: $value) {
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .onChange(of: value) { _, _ in saveValue() }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .onAppear {
            value = skillRegistry.configValue(skillId: skillId, key: option.id) ?? option.defaultValue ?? ""
        }
    }

    private func saveValue() {
        var settings = skillRegistry.configurations[skillId]?.settings ?? [:]
        settings[option.id] = value
        skillRegistry.updateConfiguration(skillId: skillId, settings: settings)
    }
}

#Preview {
    SkillsSettingsView()
        .frame(width: 700, height: 500)
}
