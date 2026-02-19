import Foundation
import GRDB

/// SQLite storage backend using GRDB.
///
/// Provides persistent storage for sessions, memories, knowledge tracking,
/// and learning records. Uses FTS5 for full-text search on memories.
public actor GRDBStorage: StorageBackend {
    private let dbWriter: any DatabaseWriter

    public init(path: String? = nil) throws {
        let dbPath: String
        if let path {
            dbPath = path
        } else {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw SBBenderError.storageError("Application Support directory not accessible")
            }
            let dir = appSupport.appendingPathComponent("com.sbbender", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("sbbender.sqlite").path
        }

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbWriter = try DatabasePool(path: dbPath, configuration: config)
        try migrate()
    }

    /// For testing with an in-memory database.
    public init(inMemory: Bool) throws {
        dbWriter = try DatabaseQueue()
        try migrate()
    }

    // MARK: - Migration

    private nonisolated func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "sessions", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentID", .text).notNull()
                t.column("messages", .blob).notNull()
                t.column("state", .blob).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            try db.create(table: "memories", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("userID", .text).notNull().indexed()
                t.column("content", .text).notNull()
                t.column("category", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            try db.create(table: "knowledge", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("contentHash", .text).notNull().indexed()
                t.column("source", .text).notNull()
                t.column("insertedAt", .double).notNull()
            }

            try db.create(table: "learnings", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("userID", .text).notNull().indexed()
                t.column("store", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }

            // FTS5 for full-text search on memories
            try db.create(virtualTable: "memories_fts", ifNotExists: true, using: FTS5()) { t in
                t.synchronize(withTable: "memories")
                t.tokenizer = .porter()
                t.column("content")
            }
        }

        migrator.registerMigration("v2_session_title") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "title", .text).defaults(to: "New Chat")
            }
        }

        migrator.registerMigration("v3_knowledge_chunks") { db in
            try db.create(table: "document_chunks", ifNotExists: true) { t in
                t.primaryKey("id", .text).notNull()
                t.column("agentID", .text).notNull().indexed()
                t.column("content", .text).notNull()
                t.column("sourceID", .text).notNull()
                t.column("sourceTitle", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("metadataJSON", .text).notNull().defaults(to: "{}")
            }

            try db.create(table: "hnsw_graphs", ifNotExists: true) { t in
                t.primaryKey("agentID", .text).notNull()
                t.column("offsets", .blob).notNull()
                t.column("neighbors", .blob).notNull()
                t.column("nodeCount", .integer).notNull()
                t.column("updatedAt", .double).notNull()
            }
        }

        try migrator.migrate(dbWriter)
        Log.storage.info("Database migration completed")
    }

    // MARK: - Sessions

    public func getSession(id: String) async throws -> Session? {
        try await dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return try Self.decodeSession(from: row)
        }
    }

    public func upsertSession(_ session: Session) async throws {
        let encoder = JSONEncoder()
        let messagesData = try encoder.encode(session.messages)
        let stateData = try encoder.encode(session.state)

        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions (id, agentID, title, messages, state, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    messages = excluded.messages,
                    state = excluded.state,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    session.id,
                    session.agentID,
                    session.title,
                    messagesData,
                    stateData,
                    session.createdAt.timeIntervalSinceReferenceDate,
                    session.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func deleteSession(id: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [id])
        }
    }

    public func listSessions(agentID: String?) async throws -> [Session] {
        try await dbWriter.read { db in
            let sql: String
            let arguments: StatementArguments
            if let agentID {
                sql = "SELECT * FROM sessions WHERE agentID = ? ORDER BY updatedAt DESC"
                arguments = [agentID]
            } else {
                sql = "SELECT * FROM sessions ORDER BY updatedAt DESC"
                arguments = []
            }

            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                do {
                    return try Self.decodeSession(from: row)
                } catch {
                    Log.storage.error("Failed to decode session: \(error.localizedDescription)")
                    return nil
                }
            }
        }
    }

    // MARK: - Memories

    public func getMemories(userID: String) async throws -> [UserMemory] {
        try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM memories WHERE userID = ? ORDER BY updatedAt DESC",
                arguments: [userID]
            ).map { row in
                UserMemory(
                    id: row["id"],
                    userID: row["userID"],
                    content: row["content"],
                    category: row["category"],
                    createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"]),
                    updatedAt: Date(timeIntervalSinceReferenceDate: row["updatedAt"])
                )
            }
        }
    }

    public func upsertMemory(_ memory: UserMemory) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO memories (id, userID, content, category, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    content = excluded.content,
                    category = excluded.category,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    memory.id,
                    memory.userID,
                    memory.content,
                    memory.category,
                    memory.createdAt.timeIntervalSinceReferenceDate,
                    memory.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    public func deleteMemory(id: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM memories WHERE id = ?", arguments: [id])
        }
    }

    /// Full-text search on memories using FTS5.
    public func searchMemories(query: String, userID: String) async throws -> [UserMemory] {
        let sanitized = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        guard !sanitized.isEmpty else { return [] }

        return try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT memories.* FROM memories
                JOIN memories_fts ON memories.rowid = memories_fts.rowid
                WHERE memories_fts MATCH ? AND memories.userID = ?
                ORDER BY bm25(memories_fts) LIMIT 20
                """,
                arguments: [sanitized, userID]
            ).map { row in
                UserMemory(
                    id: row["id"],
                    userID: row["userID"],
                    content: row["content"],
                    category: row["category"],
                    createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"]),
                    updatedAt: Date(timeIntervalSinceReferenceDate: row["updatedAt"])
                )
            }
        }
    }

    // MARK: - Knowledge

    public func getKnowledgeEntries() async throws -> [KnowledgeEntry] {
        try await dbWriter.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM knowledge ORDER BY insertedAt DESC").map { row in
                KnowledgeEntry(
                    id: row["id"],
                    contentHash: row["contentHash"],
                    source: row["source"],
                    insertedAt: Date(timeIntervalSinceReferenceDate: row["insertedAt"])
                )
            }
        }
    }

    public func upsertKnowledgeEntry(_ entry: KnowledgeEntry) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO knowledge (id, contentHash, source, insertedAt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    contentHash = excluded.contentHash,
                    source = excluded.source
                """,
                arguments: [
                    entry.id,
                    entry.contentHash,
                    entry.source,
                    entry.insertedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    // MARK: - Learnings

    public func getLearnings(userID: String, store: String) async throws -> [LearningRecord] {
        try await dbWriter.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM learnings WHERE userID = ? AND store = ? ORDER BY updatedAt DESC",
                arguments: [userID, store]
            ).map { row in
                LearningRecord(
                    id: row["id"],
                    userID: row["userID"],
                    store: row["store"],
                    key: row["key"],
                    value: row["value"],
                    createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"]),
                    updatedAt: Date(timeIntervalSinceReferenceDate: row["updatedAt"])
                )
            }
        }
    }

    public func upsertLearning(_ record: LearningRecord) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO learnings (id, userID, store, key, value, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    value = excluded.value,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    record.id,
                    record.userID,
                    record.store,
                    record.key,
                    record.value,
                    record.createdAt.timeIntervalSinceReferenceDate,
                    record.updatedAt.timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    // MARK: - Helpers

    /// Serialize [Int] to Data using zero-copy buffer.
    private static func serializeIntArray(_ array: [Int]) -> Data {
        array.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Deserialize Data back to [Int].
    private static func deserializeIntArray(_ data: Data) -> [Int] {
        guard data.count % MemoryLayout<Int>.stride == 0 else {
            Log.storage.error("HNSW blob size \(data.count) is not a multiple of Int stride; returning empty")
            return []
        }
        let count = data.count / MemoryLayout<Int>.stride
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return [] }
            let bound = base.assumingMemoryBound(to: Int.self)
            return Array(UnsafeBufferPointer(start: bound, count: count))
        }
    }

    // MARK: - Document Chunks & HNSW Graph

    func saveDocumentChunks(_ chunks: [DocumentChunk], agentID: String) async throws {
        try await dbWriter.write { db in
            // Clear existing chunks for this agent
            try db.execute(sql: "DELETE FROM document_chunks WHERE agentID = ?", arguments: [agentID])

            let encoder = JSONEncoder()
            for chunk in chunks {
                let metadataJSON = String(data: try encoder.encode(chunk.metadata), encoding: .utf8) ?? "{}"
                try db.execute(
                    sql: """
                    INSERT INTO document_chunks (id, agentID, content, sourceID, sourceTitle, chunkIndex, metadataJSON)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id,
                        agentID,
                        chunk.content,
                        chunk.sourceID,
                        chunk.sourceTitle,
                        chunk.chunkIndex,
                        metadataJSON,
                    ]
                )
            }
        }
    }

    func loadDocumentChunks(agentID: String) async throws -> [DocumentChunk] {
        try await dbWriter.read { db in
            let decoder = JSONDecoder()
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM document_chunks WHERE agentID = ? ORDER BY chunkIndex",
                arguments: [agentID]
            ).map { row in
                let metadataJSON: String = row["metadataJSON"]
                let metadata = (try? decoder.decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]
                return DocumentChunk(
                    id: row["id"],
                    content: row["content"],
                    sourceID: row["sourceID"],
                    sourceTitle: row["sourceTitle"],
                    chunkIndex: row["chunkIndex"],
                    metadata: metadata
                )
            }
        }
    }

    func saveHNSWGraph(agentID: String, offsets: [Int], neighbors: [Int], nodeCount: Int) async throws {
        let offsetsData = Self.serializeIntArray(offsets)
        let neighborsData = Self.serializeIntArray(neighbors)

        try await dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO hnsw_graphs (agentID, offsets, neighbors, nodeCount, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(agentID) DO UPDATE SET
                    offsets = excluded.offsets,
                    neighbors = excluded.neighbors,
                    nodeCount = excluded.nodeCount,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    agentID,
                    offsetsData,
                    neighborsData,
                    nodeCount,
                    Date().timeIntervalSinceReferenceDate,
                ]
            )
        }
    }

    func loadHNSWGraph(agentID: String) async throws -> (offsets: [Int], neighbors: [Int], nodeCount: Int)? {
        try await dbWriter.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM hnsw_graphs WHERE agentID = ?",
                arguments: [agentID]
            ) else { return nil }

            let offsetsData: Data = row["offsets"]
            let neighborsData: Data = row["neighbors"]
            let nodeCount: Int = row["nodeCount"]

            return (
                offsets: Self.deserializeIntArray(offsetsData),
                neighbors: Self.deserializeIntArray(neighborsData),
                nodeCount: nodeCount
            )
        }
    }

    func deleteKnowledgeIndex(agentID: String) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM document_chunks WHERE agentID = ?", arguments: [agentID])
            try db.execute(sql: "DELETE FROM hnsw_graphs WHERE agentID = ?", arguments: [agentID])
        }
    }

    private static func decodeSession(from row: Row) throws -> Session {
        let decoder = JSONDecoder()
        let messagesData: Data = row["messages"]
        let stateData: Data = row["state"]

        let messages = try decoder.decode([Message].self, from: messagesData)
        let state = try decoder.decode([String: String].self, from: stateData)

        return Session(
            id: row["id"],
            agentID: row["agentID"],
            title: (row["title"] as String?) ?? "New Chat",
            messages: messages,
            state: state,
            createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"]),
            updatedAt: Date(timeIntervalSinceReferenceDate: row["updatedAt"])
        )
    }
}

// MARK: - KnowledgeIndexPersistence Conformance

extension GRDBStorage: KnowledgeIndexPersistence {
    public func saveChunks(_ chunks: [DocumentChunk], agentID: String) async throws {
        try await saveDocumentChunks(chunks, agentID: agentID)
    }

    public func loadChunks(agentID: String) async throws -> [DocumentChunk] {
        try await loadDocumentChunks(agentID: agentID)
    }

    public func saveGraph(agentID: String, offsets: [Int], neighbors: [Int], nodeCount: Int) async throws {
        try await saveHNSWGraph(agentID: agentID, offsets: offsets, neighbors: neighbors, nodeCount: nodeCount)
    }

    public func loadGraph(agentID: String) async throws -> (offsets: [Int], neighbors: [Int], nodeCount: Int)? {
        try await loadHNSWGraph(agentID: agentID)
    }

    public func deleteIndex(agentID: String) async throws {
        try await deleteKnowledgeIndex(agentID: agentID)
    }
}
