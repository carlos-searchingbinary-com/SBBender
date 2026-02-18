import SwiftUI
import SBBender

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step: OnboardingStep = .welcome
    @State private var recommendedModels: [ModelEntry] = []
    @State private var selectedModelID: String?
    @State private var selectedTemplateIDs: Set<String> = []

    var onComplete: () -> Void

    private enum OnboardingStep: Int, CaseIterable {
        case welcome
        case model
        case templates
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicators
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            // Content
            switch step {
            case .welcome:
                welcomeStep
            case .model:
                modelStep
            case .templates:
                templatesStep
            }

            Spacer()

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
        }
        .frame(minWidth: 600, minHeight: 500)
        .task { await loadRecommendedModels() }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                HStack(spacing: 6) {
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    if s.rawValue <= step.rawValue {
                        Text(stepLabel(s))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(s == step ? .primary : .secondary)
                    }
                }
            }
        }
    }

    private func stepLabel(_ s: OnboardingStep) -> String {
        switch s {
        case .welcome: "Welcome"
        case .model: "Model"
        case .templates: "Agents"
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            Text("Welcome to SBBender")
                .font(.largeTitle.bold())

            Text("Build AI agents that run on your Mac using local models.\nNo cloud, no API keys, full privacy.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            // Hardware info card
            hardwareCard
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var hardwareCard: some View {
        let hw = appState.hardwareInfo
        return HStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(hw.chipName)
                    .font(.subheadline.weight(.medium))
                Text("\(hw.totalRAMGB) GB Unified Memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(hw.modelTier.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.blue.opacity(0.1)))
                .foregroundStyle(.blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .frame(maxWidth: 440)
    }

    // MARK: - Model Step

    private var modelStep: some View {
        VStack(spacing: 20) {
            Text("Choose a Model")
                .font(.title2.bold())

            Text("Select a local AI model optimized for your Mac.\nThe recommended model is pre-selected based on your hardware.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recommendedModels, id: \.id) { model in
                        modelCard(model)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
        .padding(.top, 12)
    }

    private func modelCard(_ model: ModelEntry) -> some View {
        let isSelected = selectedModelID == model.id
        let isDownloaded = appState.modelRegistry.isMLXModelDownloaded(model.id)
        let downloadState = appState.modelRegistry.mlxDownloadState[model.id] ?? .idle

        return Button {
            selectedModelID = model.id
        } label: {
            HStack(spacing: 14) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.subheadline.weight(.semibold))

                        if model.recommendedTier == appState.hardwareInfo.modelTier {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }

                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // Tags
                    HStack(spacing: 4) {
                        Text(model.parameterSize)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.blue.opacity(0.08)))
                            .foregroundStyle(.blue)

                        Text(model.quantization)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.purple.opacity(0.08)))
                            .foregroundStyle(.purple)

                        Text("~\(model.ramRequired) GB")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.orange.opacity(0.08)))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // Download state
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)
                } else {
                    switch downloadState {
                    case .idle:
                        if isSelected {
                            Button("Download") {
                                Task { await appState.modelRegistry.downloadMLXModel(id: model.id) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    case .downloading:
                        ProgressView()
                            .controlSize(.small)
                    case .completed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .error(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .help(msg)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Templates Step

    private var templatesStep: some View {
        VStack(spacing: 20) {
            Text("Pick Starter Agents")
                .font(.title2.bold())

            Text("Choose one or more pre-configured agents to get started.\nYou can create more agents later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(appState.agentTemplates) { template in
                        templateCard(template)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
        .padding(.top, 12)
    }

    private func templateCard(_ template: AgentTemplate) -> some View {
        let isSelected = selectedTemplateIDs.contains(template.id)

        return Button {
            if isSelected {
                selectedTemplateIDs.remove(template.id)
            } else {
                selectedTemplateIDs.insert(template.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.emoji)
                        .font(.title)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text(template.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Skill count
                if !template.skillIDs.isEmpty {
                    Text("\(template.skillIDs.count) skills")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.08)))
                        .foregroundStyle(.blue)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if step == .templates {
                Button("Get Started") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Continue") {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .templates }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Actions

    private func loadRecommendedModels() async {
        do {
            let models = try await appState.curatedRegistry.featuredModels(for: appState.hardwareInfo)
            recommendedModels = models
            // Pre-select the model matching user's tier
            let tier = appState.hardwareInfo.modelTier
            if let best = models.first(where: { $0.recommendedTier == tier }) {
                selectedModelID = best.id
            } else if let first = models.first {
                selectedModelID = first.id
            }
        } catch {
            // Fallback: suggest Qwen3-4B
            selectedModelID = "mlx-community/Qwen3-4B-4bit"
        }
    }

    private func completeOnboarding() {
        // Create agents from selected templates
        for template in appState.agentTemplates where selectedTemplateIDs.contains(template.id) {
            let config = AgentConfig(
                name: template.name,
                emoji: template.emoji,
                gradientHex: template.gradientHex,
                instructions: template.instructions,
                providerType: "mlx",
                modelID: selectedModelID ?? "mlx-community/Qwen3-4B-4bit",
                enabledSkillIDs: template.skillIDs,
                knowledgeEnabled: template.knowledgeEnabled,
                learningEnabled: template.learningEnabled,
                temperature: template.temperature,
                enableThinking: template.enableThinking
            )
            appState.saveAgent(config)
        }

        // If no templates selected, create a default general agent
        if selectedTemplateIDs.isEmpty {
            let config = AgentConfig(
                name: "Assistant",
                emoji: "🤖",
                instructions: "You are a helpful assistant.",
                providerType: "mlx",
                modelID: selectedModelID ?? "mlx-community/Qwen3-4B-4bit",
                enabledSkillIDs: ["shell", "web-fetch", "language-detection", "sentiment"],
                enableThinking: true
            )
            appState.saveAgent(config)
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}
