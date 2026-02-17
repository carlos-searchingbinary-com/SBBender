import SwiftUI
import SBBender

struct MCPConnectionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingConfig: MCPServerConfig?

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var argumentsText: String = ""
    @State private var envPairs: [(key: String, value: String)] = []
    @State private var enabled: Bool = true
    @State private var testStatus: TestStatus = .idle
    @State private var discoveredTools: [String] = []

    enum TestStatus: Equatable {
        case idle
        case connecting
        case connected(Int)
        case failed(String)

        static func == (lhs: TestStatus, rhs: TestStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.connecting, .connecting): return true
            case (.connected(let a), .connected(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var isEditing: Bool { existingConfig != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(isEditing ? "Edit MCP Server" : "New MCP Server")
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
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || command.isEmpty)
            }
            .padding()

            Divider()

            Form {
                Section("Connection") {
                    TextField("Server Name", text: $name)
                    TextField("Command (e.g. npx)", text: $command)
                        .font(.system(.body, design: .monospaced))
                    TextField("Arguments (space-separated)", text: $argumentsText)
                        .font(.system(.body, design: .monospaced))
                    Toggle("Enabled", isOn: $enabled)
                }

                Section("Environment Variables") {
                    ForEach(envPairs.indices, id: \.self) { index in
                        HStack {
                            TextField("Key", text: Binding(
                                get: { envPairs[index].key },
                                set: { envPairs[index].key = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .font(.system(.body, design: .monospaced))

                            Text("=")
                                .foregroundStyle(.secondary)

                            TextField("Value", text: Binding(
                                get: { envPairs[index].value },
                                set: { envPairs[index].value = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                            Button {
                                envPairs.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        envPairs.append((key: "", value: ""))
                    } label: {
                        Label("Add Variable", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                Section("Test") {
                    HStack {
                        Button("Test Connection") {
                            Task { await testConnection() }
                        }
                        .disabled(command.isEmpty || testStatus == .connecting)

                        Spacer()

                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .connecting:
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting...")
                                .foregroundStyle(.secondary)
                        case .connected(let count):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected (\(count) tools)")
                        case .failed(let msg):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(msg)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }

                    if !discoveredTools.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Discovered Tools:")
                                .font(.caption.bold())
                            ForEach(discoveredTools, id: \.self) { tool in
                                Label(tool, systemImage: "wrench")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        guard let c = existingConfig else { return }
        name = c.name
        command = c.command
        argumentsText = c.arguments.joined(separator: " ")
        envPairs = c.environment.map { (key: $0.key, value: $0.value) }
        enabled = c.enabled
    }

    private func save() {
        let args = argumentsText
            .split(separator: " ")
            .map(String.init)

        let env = Dictionary(uniqueKeysWithValues:
            envPairs.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }
        )

        var config = existingConfig ?? MCPServerConfig()
        config.name = name
        config.command = command
        config.arguments = args
        config.environment = env
        config.enabled = enabled
        config.updatedAt = Date()

        appState.saveMCPServerConfig(config)
        dismiss()
    }

    private func testConnection() async {
        testStatus = .connecting
        discoveredTools = []

        let args = argumentsText
            .split(separator: " ")
            .map(String.init)

        let env = Dictionary(uniqueKeysWithValues:
            envPairs.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }
        )

        let manager = MCPManager()
        do {
            try await manager.connect(
                name: name.isEmpty ? "test" : name,
                command: command,
                args: args,
                environment: env.isEmpty ? nil : env
            )
            let tools = await manager.allTools()
            discoveredTools = tools.map(\.name)
            testStatus = .connected(tools.count)
            await manager.disconnectAll()
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }
}
