import SwiftUI
import SBBender

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var recommendedModels: [ModelEntry] = []
    @State private var loadingRecommended = false
    @State private var mlxSearchQuery = ""

    // Cloud provider keys
    @State private var anthropicKey: String = KeychainService.anthropicKey
    @State private var openaiKey: String = KeychainService.openaiKey
    @State private var groqKey: String = KeychainService.groqKey
    @State private var deepinfraKey: String = KeychainService.deepinfraKey
    @State private var ollamaURL: String = KeychainService.ollamaURL
    @State private var keySaveMessage: String?

    // HuggingFace search
    @State private var showHFSearch = false

    private var hasLocalModels: Bool {
        !appState.modelRegistry.mlxLocalModels.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hardwareCard
                    .padding(.horizontal)
                    .padding(.top, 12)

                if hasLocalModels {
                    normalStateContent
                } else {
                    emptyStateContent
                }
            }
        }
        .task {
            await loadRecommendedModels()
        }
    }

    // MARK: - Hardware Card

    private var hardwareCard: some View {
        let hw = appState.hardwareInfo
        return HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(hw.chipName)
                    .font(.headline)
                HStack(spacing: 10) {
                    Text("\(hw.totalRAMGB) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("GPU \(String(format: "%.0f", hw.gpuMemoryGB)) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            tierBadge(hw.modelTier)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty State (no local models)

    private var emptyStateContent: some View {
        VStack(spacing: 20) {
            // Hero
            VStack(spacing: 8) {
                Text("Get started")
                    .font(.title2.weight(.semibold))
                Text("Download a model to run AI locally on your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            // Featured picks
            if loadingRecommended {
                ProgressView()
                    .padding(40)
            } else {
                let featured = recommendedModels.filter { $0.featured && $0.provider == "mlx" }.prefix(3)
                VStack(spacing: 10) {
                    ForEach(Array(featured)) { model in
                        modelCard(model, prominent: true)
                    }
                }
                .padding(.horizontal)
            }

            Divider()
                .padding(.horizontal)

            // Ollama + Cloud below
            ollamaSection
                .padding(.horizontal)
            cloudProvidersSection
                .padding(.horizontal)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Normal State (has local models)

    private var normalStateContent: some View {
        VStack(spacing: 16) {
            // Downloaded models
            settingsSection("Downloaded Models") {
                ForEach(appState.modelRegistry.mlxLocalModels, id: \.self) { model in
                    downloadedModelRow(model)
                }
            }

            // More models for your Mac
            settingsSection("More Models for Your Mac") {
                if loadingRecommended {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading recommendations...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    let notDownloaded = recommendedModels.filter {
                        $0.provider == "mlx" && !appState.modelRegistry.isMLXModelDownloaded($0.id)
                    }
                    if notDownloaded.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                            Text("All recommended models downloaded!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(notDownloaded) { model in
                            modelCard(model, prominent: false)
                        }
                    }
                }
            }

            // HuggingFace search (power user)
            settingsSection("Search HuggingFace") {
                DisclosureGroup("Find more MLX models", isExpanded: $showHFSearch) {
                    VStack(spacing: 8) {
                        HStack {
                            TextField("Search MLX models...", text: $mlxSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    Task { await appState.modelRegistry.searchMLXHub(query: mlxSearchQuery) }
                                }
                            if appState.modelRegistry.mlxSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        ForEach(appState.modelRegistry.mlxSearchResults) { result in
                            hfSearchResultRow(result)
                        }
                    }
                }
            }

            Divider()
                .padding(.horizontal)

            ollamaSection
                .padding(.horizontal)
            cloudProvidersSection
                .padding(.horizontal)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Model Card

    private func modelCard(_ model: ModelEntry, prominent: Bool) -> some View {
        let isDownloaded = appState.modelRegistry.isMLXModelDownloaded(model.id)
        let downloadState = appState.modelRegistry.mlxDownloadState[model.id] ?? .idle

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(prominent ? .body.weight(.semibold) : .body.weight(.medium))
                    if model.featured {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(model.parameterSize)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.blue.opacity(0.12)))
                        .foregroundStyle(.blue)
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(model.category)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(model.ramRequired) GB RAM")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isDownloaded || downloadState == .completed {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if downloadState == .downloading {
                ProgressView()
                    .controlSize(.small)
            } else if case .error(let msg) = downloadState {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("Failed")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                .help(msg)
            } else {
                Button("Download") {
                    Task { await appState.modelRegistry.downloadMLXModel(id: model.id) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(prominent ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(prominent ? Color.accentColor.opacity(0.04) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(prominent ? Color.accentColor.opacity(0.15) : .clear, lineWidth: 1)
        )
    }

    // MARK: - Downloaded Model Row

    private func downloadedModelRow(_ modelID: String) -> some View {
        let shortName = modelID.components(separatedBy: "/").last ?? modelID
        return HStack {
            Image(systemName: "cpu")
                .foregroundStyle(.green)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortName)
                    .font(.body.weight(.medium))
                Text(modelID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    // MARK: - HF Search Result Row

    private func hfSearchResultRow(_ result: HFModelInfo) -> some View {
        let isDownloaded = appState.modelRegistry.isMLXModelDownloaded(result.modelId)
        let downloadState = appState.modelRegistry.mlxDownloadState[result.modelId] ?? .idle

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.body.weight(.medium))
                Text(result.modelId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let dl = result.downloads, dl > 0 {
                Text(formatDownloads(dl))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if isDownloaded || downloadState == .completed {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if downloadState == .downloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Download") {
                    Task { await appState.modelRegistry.downloadMLXModel(id: result.modelId) }
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: - Ollama Section

    private var ollamaSection: some View {
        settingsSection("Ollama") {
            HStack(spacing: 8) {
                Image(systemName: appState.modelRegistry.ollamaAvailable ? "circle.fill" : "circle")
                    .foregroundStyle(appState.modelRegistry.ollamaAvailable ? .green : .red)
                    .font(.caption2)
                Text(appState.modelRegistry.ollamaAvailable ? "Connected" : "Not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") {
                    Task { await appState.modelRegistry.loadOllamaModels() }
                }
                .controlSize(.mini)
            }

            HStack {
                Text("Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("http://localhost:11434", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: ollamaURL) { _, newValue in
                        KeychainService.ollamaURL = newValue
                    }
            }

            let models = appState.modelRegistry.ollamaModels
            if !models.isEmpty {
                ForEach(models) { model in
                    HStack {
                        Text(model.name)
                            .font(.caption.weight(.medium))
                        if let details = model.details, let ps = details.parameterSize {
                            Text(ps)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !model.sizeLabel.isEmpty {
                            Text(model.sizeLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cloud Providers

    private var cloudProvidersSection: some View {
        settingsSection("Cloud Providers") {
            providerKeyRow(
                name: "Anthropic", icon: "cloud",
                key: $anthropicKey,
                onSave: {
                    KeychainService.anthropicKey = anthropicKey
                    keySaveMessage = "Anthropic key saved"
                    Task { await appState.modelRegistry.loadAnthropicModels(apiKey: anthropicKey) }
                },
                modelCount: appState.modelRegistry.anthropicModels.count
            )
            providerKeyRow(
                name: "OpenAI", icon: "cloud.fill",
                key: $openaiKey,
                onSave: {
                    KeychainService.openaiKey = openaiKey
                    keySaveMessage = "OpenAI key saved"
                    Task { await appState.modelRegistry.loadOpenAIModels(apiKey: openaiKey) }
                },
                modelCount: appState.modelRegistry.openaiModels.count
            )
            providerKeyRow(
                name: "Groq", icon: "bolt.fill",
                key: $groqKey,
                onSave: {
                    KeychainService.groqKey = groqKey
                    keySaveMessage = "Groq key saved"
                    Task { await appState.modelRegistry.loadGroqModels(apiKey: groqKey) }
                },
                modelCount: appState.modelRegistry.groqModels.count
            )
            providerKeyRow(
                name: "DeepInfra", icon: "cloud.bolt",
                key: $deepinfraKey,
                onSave: {
                    KeychainService.deepinfraKey = deepinfraKey
                    keySaveMessage = "DeepInfra key saved"
                    Task { await appState.modelRegistry.loadDeepInfraModels(apiKey: deepinfraKey) }
                },
                modelCount: appState.modelRegistry.deepinfraModels.count
            )

            if let msg = keySaveMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.caption)
                }
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    keySaveMessage = nil
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 6) {
                content()
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func providerKeyRow(
        name: String,
        icon: String,
        key: Binding<String>,
        onSave: @escaping () -> Void,
        modelCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(name, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
                if modelCount > 0 {
                    Text("\(modelCount) models")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 6) {
                SecureField("API Key", text: key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button("Save") { onSave() }
                    .controlSize(.mini)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }

    private func tierBadge(_ tier: ModelTier) -> some View {
        Text(tier.displayName)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tierColor(tier).opacity(0.15)))
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

    private func loadRecommendedModels() async {
        loadingRecommended = true
        do {
            recommendedModels = try await appState.curatedRegistry.recommendedModels(for: appState.hardwareInfo)
        } catch {
            recommendedModels = []
        }
        loadingRecommended = false
    }

    private func formatDownloads(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
