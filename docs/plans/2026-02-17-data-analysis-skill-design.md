# DataAnalysisSkill Design

## Problem

Users want to analyze CSV/Excel files by dropping them into an agent chat. The current Data Analysis template only has shell tools (awk, sort, grep) which are painful for tabular data. There's no way to load a spreadsheet and run SQL queries against it.

## Solution

A `DataAnalysisSkill` NativeTool backed by DuckDB's Swift client. In-memory database, zero disk footprint, pure Swift dependency. The agent loads files into named tables and runs SQL queries.

## Dependency

- Package: `duckdb/duckdb-swift` (SPM, `.upToNextMajor(from: "1.0.0")`)
- No CLI install needed. Compiled into the app.

## Tool Design

Single tool with `action` parameter (like CalendarSkill pattern):

| Action | Parameters | Returns |
|--------|-----------|---------|
| `load` | `filePath`, optional `tableName` | Schema (columns, types, row count) + 10-row preview |
| `query` | `query` (SQL) | Text-formatted result table, capped at 100 rows |
| `describe` | `tableName` | Column names, types, row count, sample values |

### Tool Parameters (JSON Schema)

```json
{
  "action": { "type": "string", "description": "load, query, or describe" },
  "filePath": { "type": "string", "description": "Path to CSV/Excel/JSON/Parquet file (for load)" },
  "query": { "type": "string", "description": "SQL query to run (for query action)" },
  "tableName": { "type": "string", "description": "Table name. Defaults to filename stem on load." }
}
```

### File Format Support

DuckDB handles natively: CSV, TSV, Excel (.xlsx), JSON, Parquet. Auto-detected by file extension.

## Architecture

```
DataAnalysisSkill (NativeTool, Sendable)
├── id: "data-analysis"
├── name: "analyzeData"
├── database: Database (.inMemory)
├── connection: Connection
├── loadedTables: Set<String>  (track what's loaded)
└── execute(input:) → dispatches on action
```

- `isAvailable` always returns `true` (compiled in)
- Connection created lazily on first use
- State managed via `OSAllocatedUnfairLock` for Sendable safety
- Results formatted as aligned text tables (pipe-delimited)
- Max 100 rows returned per query to protect context window

## Security

- File paths validated: must exist, must have supported extension
- SQL is unrestricted within the in-memory database (no filesystem writes possible)
- No network access from DuckDB

## Integration

- New file: `Sources/SBBender/Skill/DataAnalysisSkill.swift`
- Added to `AppState.nativeSkills`
- Added to skill categories as ("Data", "tablecells", ["data-analysis"])
- Data Analysis template/bundle updated with `"data-analysis"` in enabledSkillIDs
- Knowledge base file drop could route CSV/Excel through this skill

## DuckDB Swift API Usage

```swift
let database = try Database(store: .inMemory)
let connection = try database.connect()

// Load CSV
try connection.execute("CREATE TABLE sales AS SELECT * FROM read_csv('/path/to/sales.csv')")

// Load Excel
try connection.execute("CREATE TABLE report AS SELECT * FROM read_xlsx('/path/to/report.xlsx')")

// Query
let result = try connection.query("SELECT product, SUM(revenue) FROM sales GROUP BY product")
// result.columnCount, result.rowCount, result.columnName(at:), result[i].cast(to:)
```
