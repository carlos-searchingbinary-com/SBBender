import SwiftUI
import SBBender
import UniformTypeIdentifiers

struct MarketplaceView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MarketplaceViewModel()
    @State private var showLocalPicker = false
    @State private var isDropTargeted = false
    @State private var showSkillBuilder = false

    var body: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { viewModel.errorMessage = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }

            // Container runtime status banner
            containerRuntimeBanner

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Registry search
                    registrySearchSection

                    // Search results
                    if !viewModel.searchResults.isEmpty {
                        registryResultsSection
                    }

                    Divider()

                    // Drop zone for SKILL.md / .zip
                    dropZoneSection

                    // Parsed manifest preview
                    if let manifest = viewModel.parsedManifest {
                        manifestPreview(manifest)
                    }

                    Divider()

                    // Create your own
                    createSkillSection

                    Divider()

                    // Installed skills.sh skills
                    if !viewModel.installedSkillsShNames.isEmpty {
                        installedSkillsShSection
                    }

                    // Installed containerized skills
                    if !viewModel.installedSlugs.isEmpty {
                        installedSkillsSection
                    }

                }
                .padding(20)
            }
        }
        .navigationTitle("Skill Library")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSkillBuilder = true
                } label: {
                    Label("Create Skill", systemImage: "plus.circle")
                }
                .help("Create a new skill from scratch")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showLocalPicker = true
                } label: {
                    Label("Install from Folder", systemImage: "folder.badge.plus")
                }
                .help("Install a skill from a local directory with SKILL.md")
            }
        }
        .fileImporter(
            isPresented: $showLocalPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await viewModel.installLocal(url: url, appState: appState) }
            }
        }
        .sheet(isPresented: $showSkillBuilder) {
            SkillBuilderSheet {
                Task { await viewModel.loadInstalled(appState: appState) }
            }
        }
        .sheet(item: $viewModel.selectedSkill) { skill in
            SkillDetailSheet(skill: skill, viewModel: viewModel, appState: appState)
        }
        .onChange(of: viewModel.selectedSkillsShEntry) { _, entry in
            if let entry {
                appState.browsingSkillsShEntry = entry
                appState.selectedSidebarItem = .skillDetail(entry.id)
                viewModel.selectedSkillsShEntry = nil
            }
        }
        .task {
            await viewModel.loadInstalled(appState: appState)
        }
    }

    // MARK: - Container Runtime Banner

    @ViewBuilder
    private var containerRuntimeBanner: some View {
        let status = appState.containerRuntimeStatus
        switch status {
        case .ready, .notSupported:
            EmptyView()
        case .kernelMissing:
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.trianglebadge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Container Runtime Not Available")
                        .font(.caption.weight(.medium))
                    Text(status.guidanceMessage ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("How to Install", destination: URL(string: "https://github.com/apple/container")!)
                    .font(.caption)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
        case .initFailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Container Runtime Error")
                        .font(.caption.weight(.medium))
                    Text(status.guidanceMessage ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(Color.red.opacity(0.1))
        }
    }

    // MARK: - Registry Search

    private var registrySearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse skills.sh")
                .font(.headline)
            Text("Search community agent skills from skills.sh")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search skills...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { viewModel.search(appState: appState) }
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        viewModel.search(appState: appState)
                    }
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var registryResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.searchResults.count) result\(viewModel.searchResults.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(viewModel.searchResults) { entry in
                registryResultRow(entry)
            }
        }
    }

    @State private var hoveredSkillID: String?

    private func registryResultRow(_ entry: SkillsShEntry) -> some View {
        let isInstalled = viewModel.installedSkillsShNames.contains(entry.name)
        let isInstalling = viewModel.installingSlugs.contains(entry.name)
        let isHovered = hoveredSkillID == entry.id

        return HStack(spacing: 12) {
            // Skill icon
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.blue.opacity(0.8))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Label(entry.source, systemImage: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if entry.installs > 0 {
                        Label("\(entry.installs) installs", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("Click to preview instructions")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else if isInstalling {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Install") {
                    Task { await viewModel.installFromRegistry(entry: entry, appState: appState) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hoveredSkillID = $0 ? entry.id : nil }
        .onTapGesture {
            viewModel.selectedSkillsShEntry = entry
        }
    }

    // MARK: - Drop Zone

    private var dropZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Skill Package")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8]),
                        antialiased: true
                    )
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary.opacity(0.5))
                    .frame(height: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.05) : .clear)
                    )

                if viewModel.isParsingDrop {
                    ProgressView("Parsing skill package...")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("Drop a folder with SKILL.md or a .zip archive")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Compatible with skills.sh / OpenClaw format")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
                return true
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString) else { return }
            Task { @MainActor in
                await viewModel.parseDroppedItem(url: url, appState: appState)
            }
        }
    }

    // MARK: - Manifest Preview

    @ViewBuilder
    private func manifestPreview(_ manifest: SkillManifest) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(manifest.name)
                            .font(.headline)
                        Text(manifest.slug)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v\(manifest.version)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.15)))
                }

                Text(manifest.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let env = manifest.primaryEnv {
                    HStack {
                        Text("Environment:")
                            .font(.caption.weight(.medium))
                        Text(env)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !manifest.requirements.bins.isEmpty {
                    HStack {
                        Text("Requires:")
                            .font(.caption.weight(.medium))
                        Text(manifest.requirements.bins.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Install") {
                        Task {
                            await viewModel.installLocal(
                                url: manifest.localPath,
                                appState: appState
                            )
                            viewModel.parsedManifest = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Dismiss") {
                        viewModel.parsedManifest = nil
                    }
                    .controlSize(.small)
                }
            }
        } label: {
            Label("Parsed Skill Package", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: - Installed skills.sh Skills

    private var installedSkillsShSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Skills")
                .font(.headline)

            Text("\(viewModel.installedSkillsShNames.count) skill\(viewModel.installedSkillsShNames.count == 1 ? "" : "s") from skills.sh")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(viewModel.installedSkillsShNames.sorted()), id: \.self) { name in
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                    Text(name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Uninstall", role: .destructive) {
                        Task { await viewModel.uninstallSkillsSh(name: name, appState: appState) }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Create Skill

    private var createSkillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Your Own")
                .font(.headline)

            Button {
                showSkillBuilder = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Skill")
                            .font(.body.weight(.medium))
                        Text("Write custom instructions for your agents")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Installed Skills

    private var installedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Containerized Skills")
                .font(.headline)

            Text("\(viewModel.installedSlugs.count) skill\(viewModel.installedSlugs.count == 1 ? "" : "s") installed (macOS 26+ containers)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(viewModel.installedSlugs.sorted()), id: \.self) { slug in
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.orange)
                    Text(slug)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Uninstall", role: .destructive) {
                        let entry = SkillListEntry(
                            slug: slug,
                            name: slug,
                            description: "",
                            version: "",
                            author: "",
                            downloads: 0
                        )
                        Task { await viewModel.uninstall(skill: entry, appState: appState) }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

}
