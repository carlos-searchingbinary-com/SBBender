import SwiftUI
import SBBender

struct AgentWizardSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onConfigGenerated: (AgentConfig) -> Void

    @State private var userDescription: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var previewConfig: AgentConfig?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("AI Assistant Wizard")
                        .font(.title2.bold())
                    Text("Describe your ideal assistant and let AI configure it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(spacing: 16) {
                // Description input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should this assistant do?")
                        .font(.headline)
                    TextEditor(text: $userDescription)
                        .font(.body)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Text("Example: \"An assistant that helps me manage my calendar, search the web for meeting prep, and summarize discussions\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Generate button
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGenerating ? "Setting up..." : "Set Up Assistant")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)

                // Error
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Preview
                if let preview = previewConfig {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Assistant Setup")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            previewRow("Name", preview.name)
                            previewRow("Emoji", preview.emoji)
                            previewRow("Capabilities", preview.enabledSkillIDs.map { SkillMetadata.displayName(for: $0) }.joined(separator: ", "))
                            if !preview.attachedSkillIDs.isEmpty {
                                previewRow("Instructions", preview.attachedSkillIDs.joined(separator: ", "))
                            }
                            previewRow("Creativity", friendlyTemperature(preview.temperature))
                            previewRow("Deep Reasoning", preview.enableThinking ? "On" : "Off")
                            previewRow("Knowledge Base", preview.knowledgeEnabled ? "On" : "Off")
                            previewRow("Memory", preview.learningEnabled ? "On" : "Off")

                            Divider()

                            Text("Instructions")
                                .font(.caption.weight(.medium))
                            Text(preview.instructions)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Button("Regenerate") {
                                Task { await generate() }
                            }
                            .disabled(isGenerating)

                            Spacer()

                            Button("Use This Setup") {
                                onConfigGenerated(preview)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    @ViewBuilder
    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 90, alignment: .trailing)
            Text(value.isEmpty ? "-" : value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func friendlyTemperature(_ t: Float) -> String {
        switch t {
        case 0.0...0.2: return "Very precise"
        case 0.2...0.5: return "Focused"
        case 0.5...0.8: return "Balanced"
        case 0.8...1.1: return "Creative"
        default: return "Very creative"
        }
    }

    // MARK: - Generation

    private func generate() async {
        let description = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        previewConfig = nil

        do {
            let config = try await generateConfig(description: description)
            previewConfig = config
        } catch {
            errorMessage = "Generation failed: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    private func generateConfig(description: String) async throws -> AgentConfig {
        // Build the tool catalog (NativeTools) for the prompt
        let toolCatalog = appState.nativeSkills.map { tool in
            "- \(tool.id): \(tool.name) — \(tool.description)"
        }.joined(separator: "\n")

        // Build the installed skills catalog (SKILL.md)
        let installedSkills = (try? await appState.skillsShClient.listInstalled()) ?? []
        let skillCatalog: String
        if installedSkills.isEmpty {
            skillCatalog = "(none installed)"
        } else {
            skillCatalog = installedSkills.map { skill in
                "- \(skill.id): \(skill.name) — \(skill.description)"
            }.joined(separator: "\n")
        }

        let systemPrompt = """
        You are an agent configuration assistant. Given a user's description of what they want an AI agent to do, \
        generate a JSON configuration for the agent.

        Available tools (native capabilities — use their IDs in enabledSkillIDs):
        \(toolCatalog)

        Available instruction skills (SKILL.md — use their IDs in attachedSkillIDs):
        \(skillCatalog)

        Respond with ONLY a JSON object (no markdown, no explanation) with these fields:
        {
          "name": "string (short name)",
          "emoji": "single emoji",
          "instructions": "string (system prompt for the agent)",
          "enabledSkillIDs": ["tool-id-1", "tool-id-2"],
          "attachedSkillIDs": ["skills-sh-skill-name"],
          "temperature": 0.7,
          "topP": 0.9,
          "maxTokens": 2048,
          "enableThinking": false,
          "markdown": true,
          "knowledgeEnabled": false,
          "learningEnabled": false
        }

        Choose tools that match the user's needs. Attach skills whose instructions would help the agent. \
        Set temperature lower (0.3-0.5) for precise/analytical tasks, \
        higher (0.7-0.9) for creative tasks. Enable thinking for complex reasoning tasks. \
        Enable knowledge for research-heavy agents. Enable learning for personalized assistants.
        """

        let messages = [
            Message.system(systemPrompt),
            Message.user(description)
        ]

        // Use whichever provider is available — prefer Anthropic/OpenAI for quality, fall back to MLX
        let provider = pickBestProvider()
        let genConfig = GenerationConfig(maxTokens: 1024, temperature: 0.5)
        let response = try await provider.generate(messages: messages, config: genConfig, tools: [])

        return try await parseConfigJSON(response.message.text)
    }

    private func pickBestProvider() -> any ModelProvider {
        // Prefer cloud providers for config generation quality
        let anthropicKey = KeychainService.anthropicKey
        if !anthropicKey.isEmpty {
            return AnthropicProvider(modelID: "claude-sonnet-4-5-20250929", apiKey: anthropicKey)
        }
        let openaiKey = KeychainService.openaiKey
        if !openaiKey.isEmpty {
            return OpenAIProvider(modelID: "gpt-4.1", apiKey: openaiKey)
        }
        // Fall back to MLX
        return MLXProvider(modelID: "mlx-community/Qwen3-4B-4bit")
    }

    private func parseConfigJSON(_ text: String) async throws -> AgentConfig {
        // Extract JSON from response (handle potential markdown wrapping)
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            // Strip markdown code block
            let lines = jsonText.components(separatedBy: "\n")
            let filtered = lines.drop { $0.hasPrefix("```") }.reversed().drop { $0.hasPrefix("```") }.reversed()
            jsonText = filtered.joined(separator: "\n")
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw WizardError.invalidJSON
        }

        let decoded = try JSONDecoder().decode(WizardResponse.self, from: data)

        // Validate tool IDs against available native tools
        let validToolIDs = Set(appState.nativeSkills.map(\.id))
        let validatedTools = decoded.enabledSkillIDs.filter { validToolIDs.contains($0) }

        // Validate skill IDs against installed SKILL.md skills
        let installedSkills = (try? await appState.skillsShClient.listInstalled()) ?? []
        let validSkillIDs = Set(installedSkills.map(\.id))
        let validatedSkills = (decoded.attachedSkillIDs ?? []).filter { validSkillIDs.contains($0) }

        var config = AgentConfig()
        config.name = decoded.name
        config.emoji = decoded.emoji
        config.instructions = decoded.instructions
        config.enabledSkillIDs = validatedTools
        config.attachedSkillIDs = validatedSkills
        config.knowledgeEnabled = decoded.knowledgeEnabled ?? false
        config.learningEnabled = decoded.learningEnabled ?? false
        config.temperature = decoded.temperature ?? 0.7
        config.topP = decoded.topP ?? 0.9
        config.maxTokens = decoded.maxTokens ?? 2048
        config.enableThinking = decoded.enableThinking ?? false
        config.markdown = decoded.markdown ?? true
        return config
    }
}

private struct WizardResponse: Decodable {
    let name: String
    let emoji: String
    let instructions: String
    let enabledSkillIDs: [String]
    let attachedSkillIDs: [String]?
    let temperature: Float?
    let topP: Float?
    let maxTokens: Int?
    let enableThinking: Bool?
    let markdown: Bool?
    let knowledgeEnabled: Bool?
    let learningEnabled: Bool?
}

private enum WizardError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON: "Failed to parse the generated configuration. Try again."
        }
    }
}
