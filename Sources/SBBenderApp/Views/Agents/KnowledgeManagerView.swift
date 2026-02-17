import SwiftUI
import SBBender

struct KnowledgeManagerView: View {
    @Environment(AppState.self) private var appState

    let agentConfig: AgentConfig

    @State private var knowledgeFiles: [KnowledgeFileEntry] = []
    @State private var isIngesting = false
    @State private var ingestProgress: String = ""
    @State private var searchQuery: String = ""
    @State private var searchResults: [DocumentChunk] = []
    @State private var isSearching = false
    @State private var totalChunks: Int = 0
    @State private var indexBuilt = false

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
                    Text("\(knowledgeFiles.count) documents, \(totalChunks) chunks\(indexBuilt ? ", index built" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isIngesting {
                    ProgressView()
                        .controlSize(.small)
                    Text(ingestProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                                    Text("\(file.chunkCount) chunks")
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

                // Right: Search tester
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
                                                Text("chunk \(chunk.chunkIndex)")
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
        .frame(minWidth: 700, minHeight: 500)
        .task { await loadState() }
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
        let loader = DocumentLoader()

        for url in urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            do {
                if isDir {
                    ingestProgress = "Loading folder: \(url.lastPathComponent)..."
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
                    ingestProgress = "Loading: \(url.lastPathComponent)..."
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
                ingestProgress = "Error: \(error.localizedDescription)"
            }
        }

        // Auto-build index after ingestion
        await rebuildIndex()
        isIngesting = false
        ingestProgress = ""
    }

    private func rebuildIndex() async {
        isIngesting = true
        ingestProgress = "Building index..."
        do {
            try await indexer.buildIndex()
            indexBuilt = await indexer.indexBuilt
        } catch {
            ingestProgress = "Index error: \(error.localizedDescription)"
        }
        isIngesting = false
        ingestProgress = ""
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
