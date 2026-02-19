import SwiftUI
import SBBender

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step: OnboardingStep = .welcome
    @State private var selectedTemplateIDs: Set<String> = []
    @State private var hoveredTemplateID: String?

    var onComplete: () -> Void

    private enum OnboardingStep: Int, CaseIterable {
        case welcome
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
        case .templates: "Assistants"
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("Your personal AI.")
                    .font(.largeTitle.bold())
                Text("Runs on your Mac.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.secondary)
            }

            Text("Private by default. No subscriptions. Your data never leaves your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                welcomeTile(icon: "doc.text.magnifyingglass", title: "Ask your documents", subtitle: "PDFs, manuals, contracts")
                welcomeTile(icon: "envelope.badge", title: "Write better emails", subtitle: "Draft, reply, improve")
                welcomeTile(icon: "calendar.badge.clock", title: "Plan your day", subtitle: "News, calendar, priorities")
                welcomeTile(icon: "bubble.left.and.bubble.right", title: "Practice any language", subtitle: "Speak, not just study")
            }
            .frame(maxWidth: 480)

            hardwareCard
                .frame(maxWidth: 440)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func welcomeTile(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func tierCapabilityLabel(_ tier: ModelTier) -> String {
        switch tier {
        case .small: return "Runs AI locally"
        case .medium: return "Runs large AI models"
        case .large: return "Runs the largest AI models"
        default: return "Runs the largest AI models"
        }
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

            Text(tierCapabilityLabel(hw.modelTier))
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

    // MARK: - Templates Step

    private var templatesStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("What do you want help with?")
                    .font(.title2.bold())
                Text("Pick as many as you like. You can always add more later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(appState.agentTemplates) { template in
                        templateCard(template)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 8)
    }

    private func templateCard(_ template: AgentTemplate) -> some View {
        let isSelected = selectedTemplateIDs.contains(template.id)
        let isHovered = hoveredTemplateID == template.id
        let gradientColors = template.gradientHex.map { Color(hex: $0) }

        return Button {
            if isSelected {
                selectedTemplateIDs.remove(template.id)
            } else {
                selectedTemplateIDs.insert(template.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    AgentAvatar(emoji: template.emoji, gradientHex: template.gradientHex, size: 48)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let tagline = template.tagline {
                        Text("\u{201C}\(tagline)\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(2)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors.map { $0.opacity(isSelected ? 0.14 : 0.07) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.primary.opacity(isHovered ? 0.15 : 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hoveredTemplateID = $0 ? template.id : nil }
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


    private func completeOnboarding() {
        let tierKey = appState.hardwareInfo.modelTier.rawValue
        let fallbackModelID = "mlx-community/Qwen3-4B-4bit"

        for template in appState.agentTemplates where selectedTemplateIDs.contains(template.id) {
            let modelID = template.recommendedModelsByTier[tierKey] ?? fallbackModelID
            let config = AgentConfig(
                name: template.name,
                emoji: template.emoji,
                gradientHex: template.gradientHex,
                instructions: template.instructions,
                providerType: "mlx",
                modelID: modelID,
                enabledSkillIDs: template.skillIDs,
                knowledgeEnabled: template.knowledgeEnabled,
                learningEnabled: template.learningEnabled,
                temperature: template.temperature,
                enableThinking: template.enableThinking
            )
            appState.saveAgent(config)
        }

        if selectedTemplateIDs.isEmpty {
            let config = AgentConfig(
                name: "Assistant",
                emoji: "🤖",
                instructions: "You are a helpful assistant.",
                providerType: "mlx",
                modelID: fallbackModelID,
                enabledSkillIDs: ["shell", "web-fetch", "language-detection", "sentiment"],
                enableThinking: true
            )
            appState.saveAgent(config)
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}
