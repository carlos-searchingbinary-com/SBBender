import DuckDB
import Foundation
import os

/// A NativeTool that wraps an in-memory DuckDB database for tabular data analysis.
///
/// Supports loading CSV, Excel (.xlsx), JSON, and Parquet files into named tables,
/// then running SQL queries against them. All data lives in memory — no disk footprint.
///
/// Actions:
/// - `load`: Read a file into a named table. Returns schema + preview.
/// - `query`: Run SQL against loaded tables. Returns formatted results.
/// - `describe`: Show schema for a loaded table.
/// - `tables`: List all loaded tables.
public final class DataAnalysisSkill: @unchecked Sendable, NativeTool {
    public let id = "data-analysis"
    public let name = "analyzeData"
    public let description = """
        Analyze tabular data files (CSV, Excel, JSON, Parquet) using SQL queries. \
        First load a file with action 'load', then query it with action 'query'. \
        Use 'describe' to inspect a table's schema, or 'tables' to list loaded tables.
        """

    /// Maximum rows returned in query results to protect the context window.
    public let maxResultRows: Int

    private let state = OSAllocatedUnfairLock(initialState: DuckDBState())

    public init(maxResultRows: Int = 100) {
        self.maxResultRows = maxResultRows
    }

    public var isAvailable: Bool {
        get async { true }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "action": .string("The action to perform: 'load', 'query', 'describe', or 'tables'"),
                "filePath": .string("Absolute path to the data file (CSV, XLSX, JSON, Parquet). Required for 'load'."),
                "query": .string("SQL query to execute. Required for 'query'. Tables are named after the file stem (e.g. sales.csv becomes 'sales')."),
                "tableName": .string("Custom table name. Optional for 'load' (defaults to filename stem). Required for 'describe'."),
            ],
            required: ["action"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable {
                let action: String
                let filePath: String?
                let query: String?
                let tableName: String?
            }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: NativeToolInput(
                text: args.action,
                parameters: [
                    "filePath": args.filePath,
                    "query": args.query,
                    "tableName": args.tableName,
                ].compactMapValues { $0 }
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let action = input.text, !action.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No action provided. Use 'load', 'query', 'describe', or 'tables'.")
        }

        let start = CFAbsoluteTimeGetCurrent()

        switch action.lowercased() {
        case "load":
            let output = try loadFile(
                filePath: input.parameters["filePath"],
                tableName: input.parameters["tableName"]
            )
            return NativeToolResult(
                output: output,
                structuredData: ["action": "load"],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        case "query":
            let output = try runQuery(sql: input.parameters["query"])
            return NativeToolResult(
                output: output,
                structuredData: ["action": "query"],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        case "describe":
            let output = try describeTable(tableName: input.parameters["tableName"])
            return NativeToolResult(
                output: output,
                structuredData: ["action": "describe"],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        case "tables":
            let output = try listTables()
            return NativeToolResult(
                output: output,
                structuredData: ["action": "tables"],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        default:
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Unknown action '\(action)'. Use 'load', 'query', 'describe', or 'tables'."
            )
        }
    }

    // MARK: - Actions

    private func loadFile(filePath: String?, tableName: String?) throws -> String {
        guard let filePath, !filePath.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "filePath is required for 'load' action")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath) else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "File not found: \(filePath)")
        }

        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = ["csv", "tsv", "xlsx", "xls", "json", "jsonl", "parquet"]
        guard supportedExtensions.contains(ext) else {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Unsupported file type '.\(ext)'. Supported: \(supportedExtensions.joined(separator: ", "))"
            )
        }

        let table = sanitizeTableName(tableName ?? url.deletingPathExtension().lastPathComponent)
        let conn = try getConnection()

        // Build the read function based on extension
        let readFn: String
        switch ext {
        case "csv", "tsv":
            readFn = "read_csv('\(escapePath(filePath))')"
        case "xlsx", "xls":
            guard isExcelExtensionLoaded else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Excel support requires the DuckDB excel extension, which could not be loaded. Try converting the file to CSV first."
                )
            }
            readFn = "read_xlsx('\(escapePath(filePath))')"
        case "json", "jsonl":
            readFn = "read_json('\(escapePath(filePath))')"
        case "parquet":
            readFn = "read_parquet('\(escapePath(filePath))')"
        default:
            readFn = "'\(escapePath(filePath))'"
        }

        // Drop existing table if re-loading
        try conn.execute("DROP TABLE IF EXISTS \"\(table)\"")
        try conn.execute("CREATE TABLE \"\(table)\" AS SELECT * FROM \(readFn)")

        state.withLock { $0.loadedTables.insert(table) }

        // Get schema
        let schemaResult = try conn.query("DESCRIBE \"\(table)\"")
        let schema = formatResultSet(schemaResult)

        // Get row count
        let countResult = try conn.query("SELECT count(*) AS row_count FROM \"\(table)\"")
        let rowCount = formatResultSet(countResult)

        // Get preview (first 10 rows)
        let previewResult = try conn.query("SELECT * FROM \"\(table)\" LIMIT 10")
        let preview = formatResultSet(previewResult)

        return """
            Loaded '\(filePath)' into table '\(table)'.

            Schema:
            \(schema)

            \(rowCount)

            Preview (first 10 rows):
            \(preview)
            """
    }

    private func runQuery(sql: String?) throws -> String {
        guard let sql, !sql.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "query is required for 'query' action")
        }

        let conn = try getConnection()
        let result = try conn.query(sql)

        let totalRows = result.rowCount
        let formatted = formatResultSet(result, maxRows: maxResultRows)

        if totalRows > DBInt(maxResultRows) {
            return "\(formatted)\n\n(\(totalRows) total rows, showing first \(maxResultRows). Add LIMIT to your query for specific ranges.)"
        }
        return formatted
    }

    private func describeTable(tableName: String?) throws -> String {
        guard let tableName, !tableName.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "tableName is required for 'describe' action")
        }

        let conn = try getConnection()
        let sanitized = sanitizeTableName(tableName)

        let schemaResult = try conn.query("DESCRIBE \"\(sanitized)\"")
        let schema = formatResultSet(schemaResult)

        let countResult = try conn.query("SELECT count(*) AS row_count FROM \"\(sanitized)\"")
        let count = formatResultSet(countResult)

        let sampleResult = try conn.query("SELECT * FROM \"\(sanitized)\" LIMIT 5")
        let sample = formatResultSet(sampleResult)

        return """
            Table: \(sanitized)
            \(count)

            Schema:
            \(schema)

            Sample (5 rows):
            \(sample)
            """
    }

    private func listTables() throws -> String {
        let tables = state.withLock { Array($0.loadedTables.sorted()) }
        if tables.isEmpty {
            return "No tables loaded. Use action 'load' with a filePath to load data."
        }

        let conn = try getConnection()
        var lines: [String] = ["Loaded tables:"]
        for table in tables {
            do {
                let result = try conn.query("SELECT count(*) FROM \"\(table)\"")
                let col = result[0].cast(to: Int.self)
                let count = col[col.startIndex] ?? 0
                lines.append("  - \(table) (\(count) rows)")
            } catch {
                lines.append("  - \(table) (error reading)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - DuckDB State

    private struct DuckDBState {
        var database: Database?
        var connection: Connection?
        var loadedTables: Set<String> = []
        var excelExtensionLoaded = false
    }

    private func getConnection() throws -> Connection {
        try state.withLock { state in
            if let conn = state.connection {
                return conn
            }
            let db = try Database(store: .inMemory)
            let conn = try db.connect()
            // Try to install and load the Excel extension for xlsx support.
            // This may fail if offline or extension is unavailable — xlsx won't work but everything else will.
            do {
                try conn.execute("INSTALL excel; LOAD excel;")
                state.excelExtensionLoaded = true
            } catch {
                state.excelExtensionLoaded = false
            }
            state.database = db
            state.connection = conn
            return conn
        }
    }

    private var isExcelExtensionLoaded: Bool {
        state.withLock { $0.excelExtensionLoaded }
    }

    // MARK: - Result Formatting

    private func formatResultSet(_ result: ResultSet, maxRows: Int? = nil) -> String {
        let colCount = Int(result.columnCount)
        let rowCount = Int(result.rowCount)
        guard colCount > 0 else { return "(empty result)" }

        let limit = min(rowCount, maxRows ?? rowCount)

        // Get column names
        var headers: [String] = []
        for c in 0..<colCount {
            headers.append(result.columnName(at: DBInt(c)))
        }

        // Build rows as string arrays.
        // DuckDB's cast(to: String.self) only works for VARCHAR columns, so we
        // need to detect the column type and use the right Swift cast per column.
        var rows: [[String]] = []
        for r in 0..<limit {
            var row: [String] = []
            for c in 0..<colCount {
                row.append(cellString(result: result, column: DBInt(c), row: r))
            }
            rows.append(row)
        }

        // Calculate column widths
        var widths = headers.map(\.count)
        for row in rows {
            for (c, cell) in row.enumerated() {
                widths[c] = max(widths[c], min(cell.count, 40))
            }
        }

        // Format as pipe-delimited table
        func pad(_ s: String, width: Int) -> String {
            let truncated = s.count > 40 ? String(s.prefix(37)) + "..." : s
            return truncated.padding(toLength: max(width, truncated.count), withPad: " ", startingAt: 0)
        }

        let headerLine = headers.enumerated().map { pad($1, width: widths[$0]) }.joined(separator: " | ")
        let separator = widths.map { String(repeating: "-", count: $0) }.joined(separator: "-+-")

        var lines = [headerLine, separator]
        for row in rows {
            let line = row.enumerated().map { pad($1, width: widths[$0]) }.joined(separator: " | ")
            lines.append(line)
        }

        if rowCount > limit {
            lines.append("... (\(rowCount - limit) more rows)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func sanitizeTableName(_ name: String) -> String {
        // Remove non-alphanumeric chars, replace spaces/hyphens with underscore
        let cleaned = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return cleaned.isEmpty ? "data" : cleaned.lowercased()
    }

    private func escapePath(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "''")
    }

    /// Extract a cell value as a String by trying DuckDB type casts in priority order.
    /// DuckDB's Column.cast(to: String.self) only works for VARCHAR columns.
    /// SUM/COUNT return HUGEINT, so we must handle that separately.
    private func cellString(result: ResultSet, column: DBInt, row: Int) -> String {
        let col = result[column]
        // VARCHAR
        let s = col.cast(to: String.self)
        if let v = s[s.startIndex.advanced(by: row)] { return v }
        // BIGINT
        let i64 = col.cast(to: Int64.self)
        if let v = i64[i64.startIndex.advanced(by: row)] { return String(v) }
        // INTEGER
        let i32 = col.cast(to: Int32.self)
        if let v = i32[i32.startIndex.advanced(by: row)] { return String(v) }
        // HUGEINT (SUM/COUNT results)
        let ih = col.cast(to: IntHuge.self)
        if let v = ih[ih.startIndex.advanced(by: row)] { return v.description }
        // DOUBLE
        let d = col.cast(to: Double.self)
        if let v = d[d.startIndex.advanced(by: row)] { return String(v) }
        // FLOAT
        let f = col.cast(to: Float.self)
        if let v = f[f.startIndex.advanced(by: row)] { return String(v) }
        // DECIMAL
        let dec = col.cast(to: Decimal.self)
        if let v = dec[dec.startIndex.advanced(by: row)] { return "\(v)" }
        // BOOLEAN
        let b = col.cast(to: Bool.self)
        if let v = b[b.startIndex.advanced(by: row)] { return String(v) }
        // UUID
        let u = col.cast(to: UUID.self)
        if let v = u[u.startIndex.advanced(by: row)] { return v.uuidString }
        return "NULL"
    }
}
