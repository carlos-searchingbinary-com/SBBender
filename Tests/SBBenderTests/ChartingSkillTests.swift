import Testing
import Foundation
@testable import SBBender

@Suite("ChartingSkill Tests")
struct ChartingSkillTests {

    // MARK: - Basics

    @Test("Skill is always available")
    func testAvailability() async {
        let skill = ChartingSkill()
        let available = await skill.isAvailable
        #expect(available)
    }

    @Test("No action throws error")
    func testNoAction() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: nil, parameters: [:]))
        }
    }

    @Test("Unknown action throws error")
    func testUnknownAction() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(text: "render", parameters: [:]))
        }
    }

    // MARK: - List Types

    @Test("Types action lists all chart types")
    func testListTypes() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(text: "types", parameters: [:]))
        #expect(result.output.contains("bar"))
        #expect(result.output.contains("line"))
        #expect(result.output.contains("pie"))
        #expect(result.output.contains("scatter"))
        #expect(result.output.contains("area"))
        #expect(result.structuredData["action"] == "types")
    }

    // MARK: - Bar Chart

    @Test("Explicit bar chart with structured output")
    func testBarChart() async throws {
        let spec = try await createChart(
            type: "bar",
            title: "Sales by Product",
            xLabel: "Product",
            yLabel: "Units Sold",
            data: [
                ["label": "Widget", "value": "130"],
                ["label": "Gadget", "value": "85"],
                ["label": "Doohickey", "value": "45"],
            ]
        )

        #expect(spec.__chart__ == true)
        #expect(spec.type == .bar)
        #expect(spec.title == "Sales by Product")
        #expect(spec.xLabel == "Product")
        #expect(spec.yLabel == "Units Sold")
        #expect(spec.autoDetected == false)
        #expect(spec.data?.count == 3)
        #expect(spec.data?[0].label == "Widget")
        #expect(spec.data?[0].value == 130)
    }

    @Test("Multi-series grouped bar chart")
    func testGroupedBarChart() async throws {
        let spec = try await createChartWithSeries(
            type: "bar",
            title: "Sales by Product & Region",
            series: [
                ["name": "North", "data": [["label": "Widget", "value": 80], ["label": "Gadget", "value": 60]]],
                ["name": "South", "data": [["label": "Widget", "value": 50], ["label": "Gadget", "value": 25]]],
            ]
        )

        #expect(spec.type == .bar)
        #expect(spec.series?.count == 2)
        #expect(spec.series?[0].name == "North")
        #expect(spec.series?[0].data.count == 2)
        #expect(spec.series?[1].name == "South")
    }

    // MARK: - Line Chart

    @Test("Explicit line chart with temporal data")
    func testLineChart() async throws {
        let spec = try await createChart(
            type: "line",
            title: "Monthly Revenue",
            data: [
                ["label": "Jan", "value": "1200"],
                ["label": "Feb", "value": "1350"],
                ["label": "Mar", "value": "1100"],
                ["label": "Apr", "value": "1500"],
            ]
        )

        #expect(spec.type == .line)
        #expect(spec.title == "Monthly Revenue")
        #expect(spec.data?.count == 4)
        #expect(spec.data?[3].value == 1500)
    }

    @Test("Multi-series line chart")
    func testMultiLineChart() async throws {
        let spec = try await createChartWithSeries(
            type: "line",
            title: "Product Trends",
            series: [
                ["name": "Widget", "data": [["label": "Q1", "value": 100], ["label": "Q2", "value": 150], ["label": "Q3", "value": 130]]],
                ["name": "Gadget", "data": [["label": "Q1", "value": 80], ["label": "Q2", "value": 90], ["label": "Q3", "value": 120]]],
            ]
        )

        #expect(spec.type == .line)
        #expect(spec.series?.count == 2)
    }

    // MARK: - Pie Chart

    @Test("Explicit pie chart with proportional data")
    func testPieChart() async throws {
        let spec = try await createChart(
            type: "pie",
            title: "Market Share",
            data: [
                ["label": "Company A", "value": "45"],
                ["label": "Company B", "value": "30"],
                ["label": "Company C", "value": "25"],
            ]
        )

        #expect(spec.type == .pie)
        #expect(spec.title == "Market Share")
        #expect(spec.data?.count == 3)
        let total = spec.data!.compactMap(\.value).reduce(0, +)
        #expect(total == 100.0)
    }

    @Test("Pie chart rejects negative values")
    func testPieChartNegativeValues() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "pie",
                    "data": "[{\"label\":\"A\",\"value\":10},{\"label\":\"B\",\"value\":-5}]",
                ]
            ))
        }
    }

    @Test("Pie chart rejects series data")
    func testPieChartRejectsSeries() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "pie",
                    "series": "[{\"name\":\"S1\",\"data\":[{\"label\":\"A\",\"value\":10}]}]",
                ]
            ))
        }
    }

    // MARK: - Scatter Plot

    @Test("Explicit scatter chart with x/y data")
    func testScatterChart() async throws {
        let spec = try await createChart(
            type: "scatter",
            title: "Price vs Quantity",
            xLabel: "Price ($)",
            yLabel: "Quantity",
            scatterData: [
                ["x": 9.99, "y": 130],
                ["x": 24.99, "y": 85],
                ["x": 14.99, "y": 45],
            ]
        )

        #expect(spec.type == .scatter)
        #expect(spec.title == "Price vs Quantity")
        #expect(spec.xLabel == "Price ($)")
        #expect(spec.data?.count == 3)
        #expect(spec.data?[0].x == 9.99)
        #expect(spec.data?[0].y == 130)
    }

    @Test("Scatter chart with named points")
    func testScatterWithNames() async throws {
        let spec = try await createChart(
            type: "scatter",
            title: "Products",
            scatterData: [
                ["x": 10, "y": 100, "name": "Widget"],
                ["x": 25, "y": 50, "name": "Gadget"],
            ]
        )

        #expect(spec.data?[0].name == "Widget")
        #expect(spec.data?[1].name == "Gadget")
    }

    @Test("Scatter chart rejects label/value data")
    func testScatterRejectsLabelValue() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "scatter",
                    "data": "[{\"label\":\"A\",\"value\":10}]",
                ]
            ))
        }
    }

    // MARK: - Area Chart

    @Test("Explicit area chart")
    func testAreaChart() async throws {
        let spec = try await createChart(
            type: "area",
            title: "Cumulative Sales",
            data: [
                ["label": "Week 1", "value": "100"],
                ["label": "Week 2", "value": "250"],
                ["label": "Week 3", "value": "420"],
                ["label": "Week 4", "value": "600"],
            ]
        )

        #expect(spec.type == .area)
        #expect(spec.data?.count == 4)
    }

    // MARK: - Auto-Detection

    @Test("Auto-detects scatter from x/y data")
    func testAutoDetectScatter() async throws {
        let spec = try await createChart(
            scatterData: [
                ["x": 1.0, "y": 2.0],
                ["x": 3.0, "y": 4.0],
                ["x": 5.0, "y": 6.0],
            ]
        )

        #expect(spec.type == .scatter)
        #expect(spec.autoDetected == true)
        #expect(spec.reason?.contains("scatter") == true)
    }

    @Test("Auto-detects line from temporal labels")
    func testAutoDetectLineFromMonths() async throws {
        let spec = try await createChart(
            data: [
                ["label": "Jan", "value": "100"],
                ["label": "Feb", "value": "120"],
                ["label": "Mar", "value": "115"],
                ["label": "Apr", "value": "140"],
            ]
        )

        #expect(spec.type == .line)
        #expect(spec.autoDetected == true)
        #expect(spec.reason?.contains("temporal") == true || spec.reason?.contains("line") == true)
    }

    @Test("Auto-detects line from quarter labels")
    func testAutoDetectLineFromQuarters() async throws {
        let spec = try await createChart(
            data: [
                ["label": "Q1", "value": "1000"],
                ["label": "Q2", "value": "1200"],
                ["label": "Q3", "value": "900"],
                ["label": "Q4", "value": "1500"],
            ]
        )

        #expect(spec.type == .line)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects line from year labels")
    func testAutoDetectLineFromYears() async throws {
        let spec = try await createChart(
            data: [
                ["label": "2020", "value": "500"],
                ["label": "2021", "value": "600"],
                ["label": "2022", "value": "750"],
                ["label": "2023", "value": "900"],
            ]
        )

        #expect(spec.type == .line)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects pie from few proportional categories")
    func testAutoDetectPie() async throws {
        let spec = try await createChart(
            data: [
                ["label": "Chrome", "value": "65"],
                ["label": "Safari", "value": "19"],
                ["label": "Firefox", "value": "10"],
                ["label": "Other", "value": "6"],
            ]
        )

        #expect(spec.type == .pie)
        #expect(spec.autoDetected == true)
        #expect(spec.reason?.contains("pie") == true)
    }

    @Test("Auto-detects bar when one category dominates (not pie)")
    func testAutoDetectBarWhenDominant() async throws {
        let spec = try await createChart(
            data: [
                ["label": "Leader", "value": "950"],
                ["label": "Other1", "value": "25"],
                ["label": "Other2", "value": "25"],
            ]
        )

        // One slice at 95% → should NOT be pie, should be bar
        #expect(spec.type == .bar)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects bar from non-temporal categories with dominant value")
    func testAutoDetectBar() async throws {
        let spec = try await createChart(
            data: [
                ["label": "Widget", "value": "950"],
                ["label": "Gadget", "value": "10"],
                ["label": "Doohickey", "value": "10"],
                ["label": "Thingamajig", "value": "10"],
                ["label": "Whatchamacallit", "value": "5"],
                ["label": "Gizmo", "value": "5"],
                ["label": "Contraption", "value": "5"],
                ["label": "Apparatus", "value": "5"],
            ]
        )

        // 8 categories with one dominant value → bar (not donut)
        #expect(spec.type == .bar)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects grouped bar from multi-series")
    func testAutoDetectGroupedBar() async throws {
        let spec = try await createChartWithSeries(
            series: [
                ["name": "North", "data": [["label": "Widget", "value": 80], ["label": "Gadget", "value": 60]]],
                ["name": "South", "data": [["label": "Widget", "value": 50], ["label": "Gadget", "value": 25]]],
            ]
        )

        #expect(spec.type == .bar)
        #expect(spec.autoDetected == true)
        #expect(spec.reason?.contains("series") == true || spec.reason?.contains("grouped") == true)
    }

    // MARK: - Auto-Detection: New Types

    @Test("Auto-detects histogram from raw numeric values")
    func testAutoDetectHistogram() async throws {
        let values = (0..<15).map { _ in Double.random(in: 0...100) }
        let dataJSON = values.map { "{\"value\":\($0)}" }.joined(separator: ",")
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: ["data": "[\(dataJSON)]"]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .histogram)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects heatmap from row/column/value data")
    func testAutoDetectHeatmap() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "heatmapData": "[{\"row\":\"A\",\"column\":\"X\",\"value\":0.9},{\"row\":\"B\",\"column\":\"X\",\"value\":0.5}]"
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .heatmap)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects candlestick from OHLC data")
    func testAutoDetectCandlestick() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "candlestickData": "[{\"label\":\"Mon\",\"open\":150,\"high\":155,\"low\":148,\"close\":153}]"
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .candlestick)
        #expect(spec.autoDetected == true)
    }

    @Test("Auto-detects donut over pie for 7+ categories")
    func testAutoDetectDonutOverPie() async throws {
        let spec = try await createChart(
            data: [
                ["label": "A", "value": "20"],
                ["label": "B", "value": "18"],
                ["label": "C", "value": "15"],
                ["label": "D", "value": "14"],
                ["label": "E", "value": "13"],
                ["label": "F", "value": "12"],
                ["label": "G", "value": "8"],
            ]
        )
        #expect(spec.type == .donut)
        #expect(spec.autoDetected == true)
    }

    // MARK: - Validation Errors

    @Test("Chart without data or series throws error")
    func testChartNoData() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: ["type": "bar", "title": "Empty"]
            ))
        }
    }

    @Test("Invalid data JSON throws error")
    func testInvalidDataJSON() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: ["data": "not json at all"]
            ))
        }
    }

    @Test("Bar chart without labels throws error")
    func testBarChartNoLabels() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "bar",
                    "data": "[{\"x\":1,\"y\":2}]",
                ]
            ))
        }
    }

    // MARK: - Structured Output Verification

    @Test("Output contains __chart__ marker for chat detection")
    func testOutputHasChartMarker() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "bar",
                "data": "[{\"label\":\"A\",\"value\":10},{\"label\":\"B\",\"value\":20}]",
            ]
        ))

        #expect(result.output.contains("\"__chart__\":true") || result.output.contains("\"__chart__\" : true"))
        #expect(result.structuredData["action"] == "chart")
        #expect(result.structuredData["type"] == "bar")

        // Should be valid JSON that decodes to ChartSpec
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.__chart__ == true)
        #expect(spec.type == .bar)
    }

    @Test("Each chart type has correct structured output fields")
    func testStructuredOutputPerType() async throws {
        // Bar
        let bar = try await createChart(type: "bar", data: [["label": "A", "value": "10"]])
        #expect(bar.type == .bar)
        #expect(bar.data != nil)

        // Line
        let line = try await createChart(type: "line", data: [["label": "A", "value": "10"]])
        #expect(line.type == .line)

        // Pie
        let pie = try await createChart(type: "pie", data: [["label": "A", "value": "10"], ["label": "B", "value": "20"]])
        #expect(pie.type == .pie)

        // Scatter
        let scatter = try await createChart(type: "scatter", scatterData: [["x": 1.0, "y": 2.0]])
        #expect(scatter.type == .scatter)
        #expect(scatter.data?[0].x != nil)
        #expect(scatter.data?[0].y != nil)

        // Area
        let area = try await createChart(type: "area", data: [["label": "A", "value": "10"]])
        #expect(area.type == .area)
    }

    // MARK: - asTool

    @Test("asTool returns valid Tool")
    func testAsTool() async throws {
        let skill = ChartingSkill()
        let tool = skill.asTool()
        #expect(tool.name == "createChart")
        #expect(!tool.description.isEmpty)

        let ctx = ToolContext(agentID: "test", sessionID: "test", runID: "test")
        let output = try await tool.execute(arguments: "{\"action\":\"types\"}", context: ctx)
        #expect(output.contains("bar"))
        #expect(output.contains("pie"))
    }

    @Test("asTool with chart action returns valid ChartSpec JSON")
    func testAsToolChart() async throws {
        let skill = ChartingSkill()
        let tool = skill.asTool()
        let ctx = ToolContext(agentID: "test", sessionID: "test", runID: "test")

        let args = """
        {"action":"chart","type":"bar","title":"Test","data":[{"label":"X","value":42}]}
        """
        let output = try await tool.execute(arguments: args, context: ctx)
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(output.utf8))
        #expect(spec.type == .bar)
        #expect(spec.title == "Test")
        #expect(spec.data?[0].value == 42)
    }

    // MARK: - ChartSpec Codable Round-Trip

    @Test("ChartSpec encodes and decodes correctly")
    func testChartSpecCodable() throws {
        let original = ChartSpec(
            type: .pie,
            title: "Market Share",
            data: [
                ChartSpec.DataPoint(label: "A", value: 60),
                ChartSpec.DataPoint(label: "B", value: 40),
            ],
            autoDetected: true,
            reason: "Test reason"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)

        #expect(decoded.__chart__ == true)
        #expect(decoded.type == .pie)
        #expect(decoded.title == "Market Share")
        #expect(decoded.data?.count == 2)
        #expect(decoded.autoDetected == true)
        #expect(decoded.reason == "Test reason")
    }

    // MARK: - New Chart Types: Codable Round-Trip

    @Test("Stacked bar ChartSpec round-trip")
    func testStackedBarCodable() throws {
        let spec = ChartSpec(
            type: .stackedBar,
            title: "Revenue by Region",
            series: [
                ChartSpec.DataSeries(name: "North", data: [
                    ChartSpec.DataPoint(label: "Q1", value: 100),
                    ChartSpec.DataPoint(label: "Q2", value: 150),
                ]),
                ChartSpec.DataSeries(name: "South", data: [
                    ChartSpec.DataPoint(label: "Q1", value: 80),
                    ChartSpec.DataPoint(label: "Q2", value: 120),
                ]),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.type == .stackedBar)
        #expect(decoded.series?.count == 2)
    }

    @Test("Donut ChartSpec round-trip")
    func testDonutCodable() throws {
        let spec = ChartSpec(
            type: .donut,
            title: "Market Share",
            data: [
                ChartSpec.DataPoint(label: "A", value: 60),
                ChartSpec.DataPoint(label: "B", value: 40),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.type == .donut)
    }

    @Test("Histogram ChartSpec round-trip with binCount")
    func testHistogramCodable() throws {
        let spec = ChartSpec(
            type: .histogram,
            title: "Age Distribution",
            data: [
                ChartSpec.DataPoint(label: "20-30", value: 15),
                ChartSpec.DataPoint(label: "30-40", value: 25),
                ChartSpec.DataPoint(label: "40-50", value: 20),
            ],
            binCount: 10
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.type == .histogram)
        #expect(decoded.binCount == 10)
    }

    @Test("Heatmap ChartSpec round-trip")
    func testHeatmapCodable() throws {
        let spec = ChartSpec(
            type: .heatmap,
            title: "Correlation Matrix",
            heatmapData: [
                ChartSpec.HeatmapCell(row: "A", column: "X", value: 0.9),
                ChartSpec.HeatmapCell(row: "A", column: "Y", value: 0.3),
                ChartSpec.HeatmapCell(row: "B", column: "X", value: 0.5),
                ChartSpec.HeatmapCell(row: "B", column: "Y", value: 0.8),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.type == .heatmap)
        #expect(decoded.heatmapData?.count == 4)
        #expect(decoded.heatmapData?[0].row == "A")
        #expect(decoded.heatmapData?[0].column == "X")
        #expect(decoded.heatmapData?[0].value == 0.9)
    }

    @Test("Candlestick ChartSpec round-trip")
    func testCandlestickCodable() throws {
        let spec = ChartSpec(
            type: .candlestick,
            title: "AAPL Weekly",
            candlestickData: [
                ChartSpec.CandlestickPoint(label: "Mon", open: 150, high: 155, low: 148, close: 153),
                ChartSpec.CandlestickPoint(label: "Tue", open: 153, high: 158, low: 151, close: 156),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.type == .candlestick)
        #expect(decoded.candlestickData?.count == 2)
        #expect(decoded.candlestickData?[0].open == 150)
        #expect(decoded.candlestickData?[0].high == 155)
        #expect(decoded.candlestickData?[0].low == 148)
        #expect(decoded.candlestickData?[0].close == 153)
    }

    // MARK: - Stacked Bar

    @Test("Explicit stacked bar chart")
    func testStackedBarChart() async throws {
        let spec = try await createChartWithSeries(
            type: "stackedBar",
            title: "Revenue Breakdown",
            series: [
                ["name": "Product A", "data": [["label": "Q1", "value": 100], ["label": "Q2", "value": 150]]],
                ["name": "Product B", "data": [["label": "Q1", "value": 80], ["label": "Q2", "value": 120]]],
            ]
        )
        #expect(spec.type == .stackedBar)
        #expect(spec.series?.count == 2)
    }

    @Test("Stacked bar rejects single data (requires series)")
    func testStackedBarRejectsSingleData() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "stackedBar",
                    "data": "[{\"label\":\"A\",\"value\":10}]",
                ]
            ))
        }
    }

    // MARK: - Donut

    @Test("Explicit donut chart")
    func testDonutChart() async throws {
        let spec = try await createChart(
            type: "donut",
            title: "Browser Share",
            data: [
                ["label": "Chrome", "value": "65"],
                ["label": "Safari", "value": "20"],
                ["label": "Firefox", "value": "15"],
            ]
        )
        #expect(spec.type == .donut)
        #expect(spec.data?.count == 3)
    }

    // MARK: - Histogram

    @Test("Histogram with raw values auto-bins")
    func testHistogramAutoBin() async throws {
        let skill = ChartingSkill()
        let values = (0..<20).map { _ in Double.random(in: 0...100) }
        let dataJSON = values.map { "{\"value\":\($0)}" }.joined(separator: ",")
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "histogram",
                "title": "Distribution",
                "data": "[\(dataJSON)]",
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .histogram)
        #expect(spec.data != nil)
        #expect(spec.data!.count >= 3)
        #expect(spec.data!.allSatisfy { $0.label != nil && $0.value != nil })
    }

    @Test("Histogram with explicit binCount")
    func testHistogramExplicitBins() async throws {
        let skill = ChartingSkill()
        let values = (0..<30).map { "\($0 * 3)" }
        let dataJSON = values.map { "{\"value\":\($0)}" }.joined(separator: ",")
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "histogram",
                "title": "Custom Bins",
                "data": "[\(dataJSON)]",
                "binCount": "5",
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .histogram)
        #expect(spec.data?.count == 5)
        #expect(spec.binCount == 5)
    }

    @Test("Histogram rejects fewer than 3 values")
    func testHistogramTooFewValues() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "histogram",
                    "data": "[{\"value\":10},{\"value\":20}]",
                ]
            ))
        }
    }

    // MARK: - Heatmap

    @Test("Heatmap chart from heatmapData")
    func testHeatmapChart() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "heatmap",
                "title": "Correlation",
                "heatmapData": """
                [{"row":"A","column":"X","value":0.9},{"row":"A","column":"Y","value":0.3},{"row":"B","column":"X","value":0.5},{"row":"B","column":"Y","value":0.8}]
                """,
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .heatmap)
        #expect(spec.heatmapData?.count == 4)
    }

    @Test("Heatmap rejects missing fields")
    func testHeatmapValidation() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "heatmap",
                ]
            ))
        }
    }

    // MARK: - Candlestick

    @Test("Candlestick chart from candlestickData")
    func testCandlestickChart() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "candlestick",
                "title": "AAPL",
                "candlestickData": """
                [{"label":"Mon","open":150,"high":155,"low":148,"close":153},{"label":"Tue","open":153,"high":158,"low":151,"close":156}]
                """,
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.type == .candlestick)
        #expect(spec.candlestickData?.count == 2)
    }

    @Test("Candlestick rejects high < low")
    func testCandlestickValidation() async {
        let skill = ChartingSkill()
        await #expect(throws: SBBenderError.self) {
            try await skill.execute(input: NativeToolInput(
                text: "chart",
                parameters: [
                    "type": "candlestick",
                    "candlestickData": "[{\"label\":\"Mon\",\"open\":150,\"high\":145,\"low\":148,\"close\":153}]",
                ]
            ))
        }
    }

    // MARK: - Annotations

    @Test("Chart with annotations")
    func testChartWithAnnotations() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(
            text: "chart",
            parameters: [
                "type": "bar",
                "data": "[{\"label\":\"A\",\"value\":100},{\"label\":\"B\",\"value\":200}]",
                "annotations": "[{\"label\":\"Target\",\"value\":150},{\"label\":\"Avg\",\"value\":150,\"style\":\"line\"}]",
            ]
        ))
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
        #expect(spec.annotations?.count == 2)
        #expect(spec.annotations?[0].label == "Target")
    }

    // MARK: - Types Action includes new types

    @Test("Types action lists all 10 chart types")
    func testListAllTypes() async throws {
        let skill = ChartingSkill()
        let result = try await skill.execute(input: NativeToolInput(text: "types", parameters: [:]))
        #expect(result.output.contains("stackedBar"))
        #expect(result.output.contains("donut"))
        #expect(result.output.contains("histogram"))
        #expect(result.output.contains("heatmap"))
        #expect(result.output.contains("candlestick"))
    }

    @Test("Annotations round-trip on bar chart")
    func testAnnotationsCodable() throws {
        let spec = ChartSpec(
            type: .bar,
            title: "Sales vs Target",
            data: [
                ChartSpec.DataPoint(label: "Q1", value: 100),
                ChartSpec.DataPoint(label: "Q2", value: 150),
            ],
            annotations: [
                ChartSpec.Annotation(label: "Target", value: 120),
                ChartSpec.Annotation(label: "Average", value: 125, style: "line"),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(ChartSpec.self, from: data)
        #expect(decoded.annotations?.count == 2)
        #expect(decoded.annotations?[0].label == "Target")
        #expect(decoded.annotations?[0].value == 120)
        #expect(decoded.annotations?[1].style == "line")
    }

    // MARK: - Helpers

    private func createChart(
        type: String? = nil,
        title: String? = nil,
        xLabel: String? = nil,
        yLabel: String? = nil,
        data: [[String: String]]? = nil,
        scatterData: [[String: Any]]? = nil
    ) async throws -> ChartSpec {
        let skill = ChartingSkill()
        var params: [String: String] = [:]
        if let type { params["type"] = type }
        if let title { params["title"] = title }
        if let xLabel { params["xLabel"] = xLabel }
        if let yLabel { params["yLabel"] = yLabel }

        if let data {
            let points = data.map { dict -> [String: Any] in
                var point: [String: Any] = [:]
                if let label = dict["label"] { point["label"] = label }
                if let value = dict["value"], let num = Double(value) { point["value"] = num }
                return point
            }
            let jsonData = try JSONSerialization.data(withJSONObject: points, options: [])
            params["data"] = String(data: jsonData, encoding: .utf8)!
        }

        if let scatterData {
            let jsonData = try JSONSerialization.data(withJSONObject: scatterData, options: [])
            params["data"] = String(data: jsonData, encoding: .utf8)!
        }

        let result = try await skill.execute(input: NativeToolInput(text: "chart", parameters: params))
        return try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
    }

    private func createChartWithSeries(
        type: String? = nil,
        title: String? = nil,
        series: [[String: Any]]
    ) async throws -> ChartSpec {
        let skill = ChartingSkill()
        var params: [String: String] = [:]
        if let type { params["type"] = type }
        if let title { params["title"] = title }

        let jsonData = try JSONSerialization.data(withJSONObject: series, options: [])
        params["series"] = String(data: jsonData, encoding: .utf8)!

        let result = try await skill.execute(input: NativeToolInput(text: "chart", parameters: params))
        return try JSONDecoder().decode(ChartSpec.self, from: Data(result.output.utf8))
    }
}
