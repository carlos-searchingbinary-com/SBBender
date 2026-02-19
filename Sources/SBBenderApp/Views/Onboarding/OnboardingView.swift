import SwiftUI
import SBBender

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step: OnboardingStep = .welcome
    @State private var selectedTemplateIDs: Set<String> = []

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
        VStack(spacing: 20) {
            Text("Pick Starter Assistants")
                .font(.title2.bold())

            Text("Choose one or more pre-configured assistants to get started.\nYou can create more later.")
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
                    Text("\(template.skillIDs.count) capabilities")
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


    private func friendlySize(_ size: String) -> String {
        let s = size.lowercased().replacingOccurrences(of: "b", with: "")
        guard let num = Float(s) else { return size }
        if num <= 4 { return "Small" }
        if num <= 8 { return "Medium" }
        return "Large"
    }

    private func friendlyQuantization(_ q: String) -> String {
        if q.lowercased().contains("4bit") || q.lowercased().contains("4-bit") { return "Efficient" }
        if q.lowercased().contains("8bit") || q.lowercased().contains("8-bit") { return "High Quality" }
        return q
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
