import SwiftUI

// MARK: - MLX Model Picker

struct MLXModelPickerView: View {
    @Binding var modelID: String
    @Binding var searchQuery: String
    let registry: ModelRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Local models
            let localModels = registry.mlxLocalModels
            if !localModels.isEmpty {
                HStack {
                    Text("Downloaded models (\(localModels.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        registry.loadMLXLocal()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Rescan local models")
                    .accessibilityLabel("Rescan local models")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(localModels, id: \.self) { model in
                            localModelChip(model)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.blue)
                        Text("No AI models on this Mac yet")
                            .font(.caption.weight(.medium))
                    }
                    Text("Search below to find and select a model, or use the Settings page to download one first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        registry.loadMLXLocal()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.04)))
            }

            // HuggingFace search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for AI models...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        Task { await registry.searchMLXHub(query: searchQuery) }
                    }
                if registry.mlxSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Search results
            let results = registry.mlxSearchResults
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(results) { result in
                            searchResultRow(result, isLocal: localModels.contains(result.modelId))
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            // Current selection
            HStack {
                Text("Selected:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(friendlyModelName(modelID))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .help(modelID)
        }
        .onAppear { registry.loadMLXLocal() }
    }

    private func localModelChip(_ model: String) -> some View {
        let selected = modelID == model
        return Button { modelID = model } label: {
            Text(model.components(separatedBy: "/").last ?? model)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                )
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .overlay(
                    Capsule().stroke(selected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(model)
    }

    private func searchResultRow(_ result: HFModelInfo, isLocal: Bool) -> some View {
        let selected = modelID == result.modelId
        return Button { modelID = result.modelId } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayName)
                        .font(.caption.weight(.medium))
                    Text(result.modelId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLocal {
                    Text("Downloaded")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if let dl = result.downloads, dl > 0 {
                    Text(formatDownloads(dl))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDownloads(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func friendlyModelName(_ id: String) -> String {
        // "mlx-community/Qwen3-4B-4bit" → "Qwen3 4B"
        let name = id.components(separatedBy: "/").last ?? id
        return name
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-8bit", with: "")
            .replacingOccurrences(of: "-bf16", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Ollama Model Picker

struct OllamaModelPickerView: View {
    @Binding var modelID: String
    let registry: ModelRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !registry.ollamaAvailable {

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Ollama not running. Start it to see installed models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await registry.loadOllamaModels() }
                    }
                    .font(.caption)
                }
            }

            let models = registry.ollamaModels
            if !models.isEmpty {
                Text("Installed models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(models) { model in
                            ollamaModelRow(model)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            // Manual entry fallback
            HStack {
                Text("Or type model name:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. qwen3:4b", text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .task {
            if registry.ollamaModels.isEmpty {
                await registry.loadOllamaModels()
            }
        }
    }

    private func ollamaModelRow(_ model: OllamaModelInfo) -> some View {
        let selected = modelID == model.name
        return Button { modelID = model.name } label: {
            HStack {
                Text(model.name)
                    .font(.caption.weight(.medium))
                if let details = model.details {
                    if let ps = details.parameterSize {
                        Text(ps)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let ql = details.quantizationLevel {
                        Text(ql)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !model.sizeLabel.isEmpty {
                    Text(model.sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}
