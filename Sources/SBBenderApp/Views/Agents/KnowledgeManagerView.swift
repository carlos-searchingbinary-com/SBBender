import SwiftUI
import SBBender

struct KnowledgeManagerView: View {
    @Environment(AppState.self) private var appState

    let agentConfig: AgentConfig

    @State private var knowledgeFiles: [KnowledgeFileEntry] = []
    @State private var isIngesting = false
    @State private var ingestionPhase: IngestionProgress.Phase?
    @State private var currentFileName: String = ""
    @State private var searchQuery: String = ""
    @State private var searchResults: [DocumentChunk] = []
    @State private var isSearching = false
    @State private var totalChunks: Int = 0
    @State private var indexBuilt = false
    @State private var processingFileIndex: Int = -1
    @State private var totalFilesToProcess: Int = 0

    private var indexer: DocumentIndexer {
        appState.getOrCreateKnowledgeIndexer(for: agentConfig)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Knowledge Base")
                        .font(.title2.bold())
                    Text("\(knowledgeFiles.count) documents, \(totalChunks) sections\(indexBuilt ? ", searchable" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isIngesting {
                    ingestionProgressView
                }
            }
            .padding()

            Divider()

            HSplitView {
                // Left: Drop zone + file list
                VStack(spacing: 16) {
                    FileDropZone { urls in
                        Task { await ingestFiles(urls) }
                    }
                    .padding(.horizontal)

                    HStack {
                        Button("Browse Files") { browseFiles() }
                        Button("Browse Folder") { browseFolder() }
                        Spacer()
                        Button("Rebuild Index") {
                            Task { await rebuildIndex() }
                        }
                        .disabled(isIngesting || totalChunks == 0)

                        Button("Clear All", role: .destructive) {
                            Task { await clearAll() }
                        }
                        .disabled(isIngesting || knowledgeFiles.isEmpty)
                    }
                    .padding(.horizontal)

                    // File list
                    List {
                        ForEach(knowledgeFiles) { file in
                            HStack {
                                Image(systemName: iconForFileType(file.fileType))
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(file.fileName)
                                        .font(.body)
                                    Text("\(file.chunkCount) sections")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .onDelete { indices in
                            Task { await deleteFiles(at: indices) }
                        }
                    }
                }
                .frame(minWidth: 300)

                // Right: Search tester (advanced only)
                if appState.showAdvancedFeatures {
                    VStack(spacing: 12) {
                        Text("Search Test")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            TextField("Query...", text: $searchQuery)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await search() } }

                            Button("Search") { Task { await search() } }
                                .disabled(searchQuery.isEmpty || isSearching || !indexBuilt)
                        }

                        if isSearching {
                            ProgressView("Searching...")
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(searchResults) { chunk in
                                        GroupBox {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(chunk.sourceTitle)
                                                        .font(.caption.bold())
                                                    Spacer()
                                                    Text("Section \(chunk.chunkIndex)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(.blue.opacity(0.1)))
                                                }
                                                Text(chunk.content.prefix(300))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(minWidth: 300)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await loadState() }
    }

    // MARK: - Progress View

    @ViewBuilder
    private var ingestionProgressView: some View {
        HStack(spacing: 8) {
            switch ingestionPhase {
            case .chunking:
                ProgressView()
                    .controlSize(.small)
                Text("Reading \(currentFileName)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .embedding(let current, let total):
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: Double(current), total: Double(max(total, 1)))
                        .frame(width: 120)
                    Text("Analyzing \(current) of \(total)...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .buildingIndex:
                ProgressView()
                    .controlSize(.small)
                Text("Making searchable...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .done, .none:
                EmptyView()
            }

            if totalFilesToProcess > 1 {
                Text("(\(processingFileIndex + 1)/\(totalFilesToProcess))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func loadState() async {
        if let files = try? await appState.persistence?.loadKnowledgeFiles(agentID: agentConfig.id) {
            knowledgeFiles = files
        }
        totalChunks = await indexer.chunkCount
        indexBuilt = await indexer.indexBuilt
    }

    private func ingestFiles(_ urls: [URL]) async {
        isIngesting = true
        totalFilesToProcess = urls.count
        let loader = DocumentLoader()

        // Wire progress callback
        await indexer.setOnProgress { [self] progress in
            Task { @MainActor in
                self.ingestionPhase = progress.phase
                if !progress.fileName.isEmpty {
                    self.currentFileName = progress.fileName
                }
            }
        }

        for (fileIndex, url) in urls.enumerated() {
            processingFileIndex = fileIndex
            currentFileName = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            do {
                if isDir {
                    ingestionPhase = .chunking
                    let docs = try loader.loadDirectory(at: url.path)
                    for doc in docs {
                        try await indexer.ingest(content: doc.content, title: doc.title, metadata: doc.metadata)
                    }
                    let chunkCount = await indexer.chunkCount
                    let entry = KnowledgeFileEntry(
                        agentID: agentConfig.id,
                        fileName: url.lastPathComponent,
                        filePath: url.path,
                        fileType: "folder",
                        chunkCount: docs.count
                    )
                    try? await appState.persistence?.saveKnowledgeFile(entry)
                    knowledgeFiles.insert(entry, at: 0)
                    totalChunks = chunkCount
                } else {
                    let ext = url.pathExtension.lowercased()

                    var docs: [(content: String, title: String, metadata: [String: String])] = []

                    switch ext {
                    case "pdf":
                        #if canImport(PDFKit)
                        docs = try loader.loadPDF(at: url.path)
                        #endif
                    case "pptx":
                        docs = try loader.loadPPTX(at: url.path)
                    default:
                        let result = try loader.loadText(at: url.path)
                        docs = [(content: result.content, title: result.title, metadata: [:])]
                    }

                    for doc in docs {
                        try await indexer.ingest(content: doc.content, title: doc.title, metadata: doc.metadata)
                    }

                    let chunkCount = await indexer.chunkCount
                    let entry = KnowledgeFileEntry(
                        agentID: agentConfig.id,
                        fileName: url.lastPathComponent,
                        filePath: url.path,
                        fileType: ext,
                        chunkCount: docs.count
                    )
                    try? await appState.persistence?.saveKnowledgeFile(entry)
                    knowledgeFiles.insert(entry, at: 0)
                    totalChunks = chunkCount
                }
            } catch {
                ingestionPhase = nil
                currentFileName = "Error: \(error.localizedDescription)"
            }
        }

        // Auto-build index after ingestion
        await rebuildIndex()
        isIngesting = false
        ingestionPhase = nil
        currentFileName = ""
        totalFilesToProcess = 0
    }

    private func rebuildIndex() async {
        isIngesting = true
        ingestionPhase = .buildingIndex
        do {
            try await indexer.buildIndex()
            indexBuilt = await indexer.indexBuilt
        } catch {
            currentFileName = "Index error: \(error.localizedDescription)"
        }
        isIngesting = false
        ingestionPhase = nil
    }

    private func search() async {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        do {
            searchResults = try await indexer.hybridSearch(query: searchQuery, limit: 5)
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    private func deleteFiles(at indices: IndexSet) async {
        for index in indices {
            let file = knowledgeFiles[index]
            try? await appState.persistence?.deleteKnowledgeFile(id: file.id)
        }
        knowledgeFiles.remove(atOffsets: indices)
        // Reset indexer since documents changed
        appState.resetKnowledgeIndexer(for: agentConfig.id)
        indexBuilt = false
    }

    private func clearAll() async {
        try? await appState.persistence?.deleteKnowledgeFiles(agentID: agentConfig.id)
        knowledgeFiles.removeAll()
        appState.resetKnowledgeIndexer(for: agentConfig.id)
        totalChunks = 0
        indexBuilt = false
        searchResults = []
    }

    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .pdf, .data]
        if panel.runModal() == .OK {
            Task { await ingestFiles(panel.urls) }
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK {
            Task { await ingestFiles(panel.urls) }
        }
    }

    private func iconForFileType(_ type: String) -> String {
        switch type {
        case "pdf": return "doc.richtext"
        case "md": return "doc.text"
        case "txt": return "doc.plaintext"
        case "pptx": return "doc.text.image"
        case "folder": return "folder.fill"
        default: return "doc"
        }
    }
}
