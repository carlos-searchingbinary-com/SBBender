import SwiftUI
import SBBender

struct SkillBuilderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""
    @State private var selectedToolIDs: Set<String> = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    var onCreated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Skill")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Basics") {
                    TextField("Name", text: $name, prompt: Text("e.g. code-reviewer"))
                    TextField("Description", text: $description, prompt: Text("What this skill does"))
                }

                Section("Instructions") {
                    TextEditor(text: $instructions)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(alignment: .topLeading) {
                            if instructions.isEmpty {
                                Text("Markdown instructions for the agent...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Allowed Tools (optional)") {
                    Text("If set, the agent can only use these tools when this skill is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(appState.nativeSkills, id: \.id) { tool in
                        Toggle(tool.name, isOn: Binding(
                            get: { selectedToolIDs.contains(tool.id) },
                            set: { selected in
                                if selected { selectedToolIDs.insert(tool.id) }
                                else { selectedToolIDs.remove(tool.id) }
                            }
                        ))
                        .font(.body)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    Task { await createSkill() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || instructions.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 550)
    }

    private func createSkill() async {
        isCreating = true
        errorMessage = nil

        let client = appState.skillsShClient
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let tools: [String]? = selectedToolIDs.isEmpty ? nil : Array(selectedToolIDs)

        do {
            _ = try await client.createLocal(
                name: trimmedName,
                description: trimmedDesc,
                instructions: instructions,
                allowedTools: tools
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
