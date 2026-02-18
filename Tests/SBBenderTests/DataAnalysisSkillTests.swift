import Testing
import Foundation
@testable import SBBender

@Suite("DataAnalysisSkill Tests")
struct DataAnalysisSkillTests {

    // MARK: - Basics

    @Test("Skill is always available")
    func testAvailability() async {
        let skill = DataAnalysisSkill()
        let available = await skill.isAvailable
        #expect(available)
    }

    @Test("No action throws error")
    func testNoAction() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: nil, parameters: [:]))
        }
    }

    @Test("Unknown action throws error")
    func testUnknownAction() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: "explode", parameters: [:]))
        }
    }

    @Test("Tables returns empty list initially")
    func testEmptyTables() async throws {
        let skill = DataAnalysisSkill()
        let result = try await skill.execute(input: NativeToolInput(text: "tables", parameters: [:]))
        #expect(result.output.contains("No tables loaded"))
    }

    // MARK: - CSV Load & Query

    @Test("Load CSV and query")
    func testLoadCSVAndQuery() async throws {
        let skill = DataAnalysisSkill()
        let csvPath = try createTempCSV(
            name: "sales",
            content: "product,quantity,price\nWidget,10,9.99\nGadget,5,24.99\nWidget,3,9.99\n"
        )
        defer { try? FileManager.default.removeItem(atPath: csvPath) }

        // Load with explicit table name
        let loadResult = try await skill.execute(input: NativeToolInput(
            text: "load",
            parameters: ["filePath": csvPath, "tableName": "sales"]
        ))
        #expect(loadResult.output.contains("sales"))
        #expect(loadResult.output.contains("product"))
        #expect(loadResult.output.contains("quantity"))
        #expect(loadResult.output.contains("price"))
        #expect(loadResult.confidence == 1.0)

        // Tables
        let tablesResult = try await skill.execute(input: NativeToolInput(
            text: "tables",
            parameters: [:]
        ))
        #expect(tablesResult.output.contains("sales"))
        #expect(tablesResult.output.contains("3 rows"))

        // Query
        let queryResult = try await skill.execute(input: NativeToolInput(
            text: "query",
            parameters: ["query": "SELECT product, SUM(quantity) AS total_qty FROM sales GROUP BY product ORDER BY total_qty DESC"]
        ))
        #expect(queryResult.output.contains("Widget"))
        #expect(queryResult.output.contains("13"))

        // Describe
        let descResult = try await skill.execute(input: NativeToolInput(
            text: "describe",
            parameters: ["tableName": "sales"]
        ))
        #expect(descResult.output.contains("product"))
        #expect(descResult.output.contains("quantity"))
    }

    @Test("Load with custom table name")
    func testCustomTableName() async throws {
        let skill = DataAnalysisSkill()
        let csvPath = try createTempCSV(
            name: "raw-data",
            content: "a,b\n1,2\n3,4\n"
        )
        defer { try? FileManager.default.removeItem(atPath: csvPath) }

        let result = try await skill.execute(input: NativeToolInput(
            text: "load",
            parameters: ["filePath": csvPath, "tableName": "mytable"]
        ))
        #expect(result.output.contains("mytable"))

        let queryResult = try await skill.execute(input: NativeToolInput(
            text: "query",
            parameters: ["query": "SELECT count(*) AS cnt FROM mytable"]
        ))
        #expect(queryResult.output.contains("2"))
    }

    @Test("Load JSON file")
    func testLoadJSON() async throws {
        let skill = DataAnalysisSkill()
        let jsonPath = try createTempFile(
            name: "items",
            ext: "json",
            content: "[{\"name\": \"Alice\", \"age\": 30},{\"name\": \"Bob\", \"age\": 25},{\"name\": \"Charlie\", \"age\": 35}]"
        )
        defer { try? FileManager.default.removeItem(atPath: jsonPath) }

        let loadResult = try await skill.execute(input: NativeToolInput(
            text: "load",
            parameters: ["filePath": jsonPath, "tableName": "items"]
        ))
        #expect(loadResult.output.contains("items"))
        #expect(loadResult.output.contains("name"))
        #expect(loadResult.output.contains("age"))

        let queryResult = try await skill.execute(input: NativeToolInput(
            text: "query",
            parameters: ["query": "SELECT name FROM items WHERE age > 28 ORDER BY name"]
        ))
        #expect(queryResult.output.contains("Alice"))
        #expect(queryResult.output.contains("Charlie"))
        #expect(!queryResult.output.contains("Bob"))
    }

    // MARK: - Multiple Tables & Joins

    @Test("Load multiple files and JOIN")
    func testJoinTables() async throws {
        let skill = DataAnalysisSkill()
        let ordersPath = try createTempCSV(
            name: "orders",
            content: "order_id,customer_id,amount\n1,100,50.00\n2,101,75.00\n3,100,25.00\n"
        )
        let customersPath = try createTempCSV(
            name: "customers",
            content: "id,name\n100,Alice\n101,Bob\n"
        )
        defer {
            try? FileManager.default.removeItem(atPath: ordersPath)
            try? FileManager.default.removeItem(atPath: customersPath)
        }

        _ = try await skill.execute(input: NativeToolInput(text: "load", parameters: ["filePath": ordersPath, "tableName": "orders"]))
        _ = try await skill.execute(input: NativeToolInput(text: "load", parameters: ["filePath": customersPath, "tableName": "customers"]))

        let joinResult = try await skill.execute(input: NativeToolInput(
            text: "query",
            parameters: ["query": """
                SELECT c.name, SUM(o.amount) AS total
                FROM orders o JOIN customers c ON o.customer_id = c.id
                GROUP BY c.name ORDER BY total DESC
                """]
        ))
        #expect(joinResult.output.contains("Alice"))
        #expect(joinResult.output.contains("75"))
        #expect(joinResult.output.contains("Bob"))
    }

    // MARK: - Error Cases

    @Test("Load missing file throws error")
    func testMissingFile() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "load",
                parameters: ["filePath": "/nonexistent/file.csv"]
            ))
        }
    }

    @Test("Load without filePath throws error")
    func testLoadNoPath() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: "load", parameters: [:]))
        }
    }

    @Test("Query without sql throws error")
    func testQueryNoSQL() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: "query", parameters: [:]))
        }
    }

    @Test("Describe without tableName throws error")
    func testDescribeNoTable() async {
        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: "describe", parameters: [:]))
        }
    }

    @Test("Unsupported file extension throws error")
    func testUnsupportedExtension() async throws {
        let path = try createTempFile(name: "test", ext: "pdf", content: "fake content")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let skill = DataAnalysisSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "load",
                parameters: ["filePath": path]
            ))
        }
    }

    // MARK: - Row Limiting

    @Test("maxResultRows limits output")
    func testMaxResultRows() async throws {
        let skill = DataAnalysisSkill(maxResultRows: 2)
        var csv = "value\n"
        for i in 1...10 { csv += "\(i)\n" }
        let path = try createTempCSV(name: "numbers", content: csv)
        defer { try? FileManager.default.removeItem(atPath: path) }

        _ = try await skill.execute(input: NativeToolInput(text: "load", parameters: ["filePath": path, "tableName": "numbers"]))

        let result = try await skill.execute(input: NativeToolInput(
            text: "query",
            parameters: ["query": "SELECT * FROM numbers"]
        ))
        #expect(result.output.contains("10 total rows"))
        #expect(result.output.contains("showing first 2"))
    }

    // MARK: - Real Excel File (if available)

    @Test("Excel file loading (extension may or may not be available)")
    func testExcelHandling() async throws {
        let skill = DataAnalysisSkill()
        // Create a fake xlsx file — not valid Excel content
        let path = try createTempFile(name: "test", ext: "xlsx", content: "fake excel content")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // This should either:
        // - Fail with a clear SBBenderError about missing extension, OR
        // - Fail with a DuckDB error about invalid file content (extension loaded but file is fake)
        // Either way, it should throw an error — never succeed silently
        await #expect(throws: (any Error).self) {
            try await skill.execute(input: NativeToolInput(
                text: "load",
                parameters: ["filePath": path, "tableName": "test"]
            ))
        }
    }

    @Test("Real xlsx file loading from Downloads")
    func testRealXlsx() async throws {
        let path = "/Users/cmartins-rlabs/Downloads/NWC_Data_Size.xlsx"
        guard FileManager.default.fileExists(atPath: path) else { return }

        let skill = DataAnalysisSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "load",
            parameters: ["filePath": path, "tableName": "nwc_data"]
        ))
        print("XLSX LOAD RESULT:\n\(result.output)")
        #expect(result.output.contains("nwc_data"))
    }

    // MARK: - asTool

    @Test("asTool returns valid Tool")
    func testAsTool() async throws {
        let skill = DataAnalysisSkill()
        let tool = skill.asTool()
        #expect(tool.name == "analyzeData")
        #expect(!tool.description.isEmpty)

        // Call via tool with JSON args
        let args = """
        {"action": "tables"}
        """
        let ctx = ToolContext(agentID: "test", sessionID: "test", runID: "test")
        let output = try await tool.execute(arguments: args, context: ctx)
        #expect(output.contains("No tables loaded"))
    }

    // MARK: - Helpers

    private func createTempCSV(name: String, content: String) throws -> String {
        try createTempFile(name: name, ext: "csv", content: content)
    }

    private func createTempFile(name: String, ext: String, content: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let path = dir.appendingPathComponent("\(name)_\(UUID().uuidString.prefix(8)).\(ext)").path
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
