import SwiftUI
import SBBender

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var mlxSearchQuery = ""
    @State private var showRecommended = false
    @State private var recommendedModels: [ModelEntry] = []
    @State private var loadingRecommended = false

    // Cloud provider keys
    @State private var anthropicKey: String = KeychainService.anthropicKey
    @State private var openaiKey: String = KeychainService.openaiKey
    @State private var groqKey: String = KeychainService.groqKey
    @State private var deepinfraKey: String = KeychainService.deepinfraKey
    @State private var keySaveMessage: String?

    var body: some View {
        Form {
            hardwareSection
            mlxSection
            ollamaSection
            cloudProvidersSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Hardware Info Card

    @ViewBuilder
    private var hardwareSection: some View {
        Section {
            let hw = appState.hardwareInfo
            HStack(spacing: 16) {
                Image(systemName: "memorychip")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hw.chipName)
                        .font(.headline)
                    HStack(spacing: 12) {
                        Label("\(hw.totalRAMGB) GB RAM", systemImage: "memorychip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(String(format: "%.0f GB GPU", hw.gpuMemoryGB), systemImage: "gpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                tierBadge(hw.modelTier)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Your Hardware")
        } footer: {
            Text("Model recommendations are based on your Mac's specifications.")
        }
    }

    // MARK: - MLX Local Models

    @ViewBuilder
    private var mlxSection: some View {
        Section("Local Models (MLX)") {
            let localModels = appState.modelRegistry.mlxLocalModels
            if localModels.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No local MLX models found in ~/.cache/huggingface/hub/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(localModels, id: \.self) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.components(separatedBy: "/").last ?? model)
                                .font(.body.weight(.medium))
                            Text(model)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }

            // Browse recommended
            DisclosureGroup("Browse Recommended", isExpanded: $showRecommended) {
                if loadingRecommended {
                    ProgressView("Loading recommendations...")
                        .font(.caption)
                } else if recommendedModels.isEmpty {
                    Text("No recommendations available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recommendedModels) { model in
                        recommendedModelRow(model)
                    }
                }
            }
            .onChange(of: showRecommended) { _, expanded in
                if expanded && recommendedModels.isEmpty {
                    loadRecommendedModels()
                }
            }

            // Search HuggingFace
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search HuggingFace for MLX models...", text: $mlxSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await appState.modelRegistry.searchMLXHub(query: mlxSearchQuery) }
                    }
                if appState.modelRegistry.mlxSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            let results = appState.modelRegistry.mlxSearchResults
            if !results.isEmpty {
                ForEach(results) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.displayName)
                                .font(.body.weight(.medium))
                            Text(result.modelId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let dl = result.downloads, dl > 0 {
                            Text(formatDownloads(dl))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if appState.modelRegistry.mlxLocalModels.contains(result.modelId) {
                            Text("Downloaded")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ollama

    @ViewBuilder
    private var ollamaSection: some View {
        Section("Ollama Models") {
            HStack {
                Image(systemName: appState.modelRegistry.ollamaAvailable ? "circle.fill" : "circle")
                    .foregroundStyle(appState.modelRegistry.ollamaAvailable ? .green : .red)
                    .font(.caption)
                Text(appState.modelRegistry.ollamaAvailable ? "Connected" : "Not running")
                    .font(.caption)
                Spacer()
                Button("Refresh") {
                    Task { await appState.modelRegistry.loadOllamaModels() }
                }
                .controlSize(.small)
            }

            let models = appState.modelRegistry.ollamaModels
            if !models.isEmpty {
                ForEach(models) { model in
                    HStack {
                        Text(model.name)
                            .font(.body.weight(.medium))
                        if let details = model.details {
                            if let ps = details.parameterSize {
                                Text(ps)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !model.sizeLabel.isEmpty {
                            Text(model.sizeLabel)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cloud Providers

    @ViewBuilder
    private var cloudProvidersSection: some View {
        Section("Cloud Providers") {
            providerKeyRow(
                name: "Anthropic",
                icon: "cloud",
                key: $anthropicKey,
                onSave: {
                    KeychainService.anthropicKey = anthropicKey
                    keySaveMessage = "Anthropic key saved"
                    Task { await appState.modelRegistry.loadAnthropicModels(apiKey: anthropicKey) }
                },
                models: appState.modelRegistry.anthropicModels
            )

            providerKeyRow(
                name: "OpenAI",
                icon: "cloud.fill",
                key: $openaiKey,
                onSave: {
                    KeychainService.openaiKey = openaiKey
                    keySaveMessage = "OpenAI key saved"
                    Task { await appState.modelRegistry.loadOpenAIModels(apiKey: openaiKey) }
                },
                models: appState.modelRegistry.openaiModels
            )

            providerKeyRow(
                name: "Groq",
                icon: "bolt.fill",
                key: $groqKey,
                onSave: {
                    KeychainService.groqKey = groqKey
                    keySaveMessage = "Groq key saved"
                    Task { await appState.modelRegistry.loadGroqModels(apiKey: groqKey) }
                },
                models: appState.modelRegistry.groqModels
            )

            providerKeyRow(
                name: "DeepInfra",
                icon: "cloud.bolt",
                key: $deepinfraKey,
                onSave: {
                    KeychainService.deepinfraKey = deepinfraKey
                    keySaveMessage = "DeepInfra key saved"
                    Task { await appState.modelRegistry.loadDeepInfraModels(apiKey: deepinfraKey) }
                },
                models: appState.modelRegistry.deepinfraModels
            )

            if let msg = keySaveMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.caption)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        keySaveMessage = nil
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func providerKeyRow(
        name: String,
        icon: String,
        key: Binding<String>,
        onSave: @escaping () -> Void,
        models: [String]
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(name, systemImage: icon)
                    .font(.headline)
                HStack {
                    SecureField("API Key", text: key)
                        .font(.system(.body, design: .monospaced))
                    Button("Save") { onSave() }
                        .controlSize(.small)
                }
                if !models.isEmpty {
                    Text("\(models.count) models available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter API key to load available models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recommendedModelRow(_ model: ModelEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name)
                        .font(.body.weight(.medium))
                    if model.featured {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(model.parameterSize)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.1)))
                    Text(model.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.purple.opacity(0.1)))
                    Text("\(model.ramRequired) GB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            tierBadge(model.recommendedTier)
        }
        .padding(.vertical, 4)
    }

    private func tierBadge(_ tier: ModelTier) -> some View {
        Text(tier.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(tierColor(tier).opacity(0.15))
            )
            .foregroundStyle(tierColor(tier))
    }

    private func tierColor(_ tier: ModelTier) -> Color {
        switch tier {
        case .small: .green
        case .medium: .blue
        case .large: .purple
        case .xlarge: .orange
        }
    }

    // MARK: - Actions

    private func loadRecommendedModels() {
        loadingRecommended = true
        Task {
            do {
                recommendedModels = try await appState.curatedRegistry.recommendedModels(for: appState.hardwareInfo)
            } catch {
                // Fallback: empty list, no crash
                recommendedModels = []
            }
            loadingRecommended = false
        }
    }

    private func formatDownloads(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
