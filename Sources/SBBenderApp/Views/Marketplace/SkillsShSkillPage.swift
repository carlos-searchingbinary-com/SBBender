import SwiftUI
import SBBender

struct SkillsShSkillPage: View {
    @Environment(AppState.self) private var appState
    @State private var content: SkillsShContent?
    @State private var files: [SkillsShFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var selectedFile: SkillsShFile?
    @State private var fileContent: String?
    @State private var isLoadingFile = false
    @State private var showRawSource = false

    private var entry: SkillsShEntry? {
        appState.browsingSkillsShEntry
    }

    var body: some View {
        Group {
            if let entry {
                skillContent(entry)
            } else {
                ContentUnavailableView(
                    "No Skill Selected",
                    systemImage: "doc.text",
                    description: Text("Select a skill from the marketplace to view its details.")
                )
            }
        }
        .navigationTitle(entry?.name ?? "Skill")
        .toolbar { toolbarContent }
    }

    // MARK: - Main Content

    private func skillContent(_ entry: SkillsShEntry) -> some View {
        HSplitView {
            // Main panel
            mainPanel(entry)
                .frame(minWidth: 500)

            // File browser panel
            if !files.isEmpty {
                fileBrowserPanel(entry)
                    .frame(minWidth: 280, maxWidth: 400)
            }
        }
        .task(id: entry.id) {
            await loadSkill(entry)
        }
    }

    private func mainPanel(_ entry: SkillsShEntry) -> some View {
        VStack(spacing: 0) {
            // Header
            skillHeader(entry)
            Divider()

            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Fetching skill from \(entry.source)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadSkill(entry) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                Spacer()
            } else if let content {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Description
                        if !content.description.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(content.description)
                                    .font(.body)
                            }
                        }

                        Divider()

                        // Instructions
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Instructions")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    showRawSource.toggle()
                                } label: {
                                    Label(
                                        showRawSource ? "Formatted" : "Raw Source",
                                        systemImage: showRawSource ? "doc.richtext" : "curlybraces"
                                    )
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }

                            if showRawSource {
                                // Raw SKILL.md source
                                Text(content.rawContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                // Rendered markdown
                                MarkdownView(content: content.instructions)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // File list summary
                        if !files.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Files")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(files.count) file\(files.count == 1 ? "" : "s") in this skill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            // Bottom action bar
            actionBar(entry)
        }
    }

    // MARK: - Header

    private func skillHeader(_ entry: SkillsShEntry) -> some View {
        HStack(spacing: 14) {
            // Skill icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.blue.gradient.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(content?.name ?? entry.name)
                    .font(.headline)
                HStack(spacing: 10) {
                    Label(entry.source, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.installs > 0 {
                        Label("\(entry.installs) installs", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            // GitHub link
            if let url = URL(string: "https://github.com/\(entry.source)") {
                Link(destination: url) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Action Bar

    private func actionBar(_ entry: SkillsShEntry) -> some View {
        HStack {
            // Back to marketplace
            Button {
                appState.selectedSidebarItem = .marketplace
            } label: {
                Label("Back to Marketplace", systemImage: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Spacer()

            if let url = entry.webURL {
                Link(destination: url) {
                    Label("View on skills.sh", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isInstalled {
                Button("Uninstall", role: .destructive) {
                    Task {
                        let client = appState.skillsShClient
                        try? await client.uninstall(name: entry.name)
                        isInstalled = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if isInstalling {
                ProgressView()
                    .controlSize(.small)
                Text("Installing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Install Skill") {
                    Task { await installSkill(entry) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - File Browser Panel

    private func fileBrowserPanel(_ entry: SkillsShEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Text("\(files.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(12)

            Divider()

            // File list
            List(files, selection: $selectedFile) { file in
                HStack(spacing: 8) {
                    Image(systemName: iconForFile(file.name))
                        .font(.caption)
                        .foregroundStyle(colorForFile(file.name))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Text(formatFileSize(file.size))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tag(file)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFile = file
                    Task { await loadFileContent(file) }
                }
            }
            .listStyle(.sidebar)

            // File content preview
            if let selectedFile {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: iconForFile(selectedFile.name))
                            .foregroundStyle(colorForFile(selectedFile.name))
                        Text(selectedFile.name)
                            .font(.caption.bold())
                        Spacer()
                        if isLoadingFile {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                    .padding(8)

                    if let fileContent {
                        ScrollView {
                            Text(fileContent)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 300)
                    }
                }
                .background(.ultraThinMaterial)
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                if let content {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content.rawContent, forType: .string)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Copy SKILL.md to Clipboard")
            .disabled(content == nil)
        }
    }

    // MARK: - Actions

    private func loadSkill(_ entry: SkillsShEntry) async {
        isLoading = true
        errorMessage = nil
        content = nil
        files = []
        selectedFile = nil
        fileContent = nil

        // Check if installed
        do {
            let client = appState.skillsShClient
            let installed = try await client.listInstalled()
            isInstalled = installed.contains(where: { $0.name == entry.name })
        } catch {}

        do {
            let client = appState.skillsShClient
            let fetched = try await client.fetchSkill(entry)
            content = fetched

            // Try to list files
            do {
                files = try await client.fetchSkillFiles(entry: entry, content: fetched)
            } catch {
                // Non-fatal — just no file browser
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func installSkill(_ entry: SkillsShEntry) async {
        isInstalling = true
        do {
            let client = appState.skillsShClient
            _ = try await client.install(entry)
            isInstalled = true
        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }
        isInstalling = false
    }

    private func loadFileContent(_ file: SkillsShFile) async {
        guard let url = file.downloadURL else { return }
        isLoadingFile = true
        do {
            let client = appState.skillsShClient
            fileContent = try await client.fetchFileContent(downloadURL: url)
        } catch {
            fileContent = "Failed to load: \(error.localizedDescription)"
        }
        isLoadingFile = false
    }

    // MARK: - Helpers

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.richtext"
        case "js", "mjs", "ts": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash": return "terminal"
        case "json": return "curlybraces.square"
        case "yaml", "yml": return "list.bullet.indent"
        case "txt": return "doc.text"
        default:
            if name == "Dockerfile" || name == "Makefile" { return "terminal" }
            return "doc"
        }
    }

    private func colorForFile(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return .blue
        case "js", "mjs", "ts": return .yellow
        case "py": return .green
        case "sh", "bash": return .orange
        case "json", "yaml", "yml": return .purple
        default: return .secondary
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
