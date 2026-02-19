import SwiftUI

struct ToolBuilderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingConfig: ToolConfig?
    let agentID: String?

    @State private var name: String = ""
    @State private var toolDescription: String = ""
    @State private var parameters: [ToolParamConfig] = []
    @State private var executionType: String = "shell"
    @State private var executionBody: String = ""
    @State private var requiresConfirmation: Bool = false
    @State private var showPreview: Bool = false

    var isEditing: Bool { existingConfig != nil }

    private let executionTypes = [
        ("shell", "terminal", "Shell"),
        ("http", "network", "HTTP"),
        ("applescript", "applescript", "AppleScript"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(isEditing ? "Edit Action" : "New Action")
                        .font(.title2.bold())
                    if !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Definition") {
                    TextField("Action Name", text: $name)
                    TextField("Description", text: $toolDescription)
                }

                Section("Parameters") {
                    JSONSchemaEditor(parameters: $parameters)
                }

                Section("Execution") {
                    Picker("Type", selection: $executionType) {
                        ForEach(executionTypes, id: \.0) { type in
                            Label(type.2, systemImage: type.1).tag(type.0)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $executionBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)

                    Text("Use ${paramName} for argument interpolation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Options") {
                    Toggle("Requires user confirmation before execution", isOn: $requiresConfirmation)
                }

                if appState.showAdvancedFeatures {
                    Section("JSON Schema Preview") {
                        Text(JSONSchemaEditor.previewJSON(from: parameters))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 550, minHeight: 550)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        guard let c = existingConfig else { return }
        name = c.name
        toolDescription = c.toolDescription
        parameters = c.parameters
        executionType = c.executionType
        executionBody = c.executionBody
        requiresConfirmation = c.requiresConfirmation
    }

    private func save() {
        var config = existingConfig ?? ToolConfig(agentID: agentID)
        config.name = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        config.toolDescription = toolDescription
        config.parameters = parameters
        config.executionType = executionType
        config.executionBody = executionBody
        config.requiresConfirmation = requiresConfirmation
        config.updatedAt = Date()

        appState.saveToolConfig(config)
        dismiss()
    }
}
