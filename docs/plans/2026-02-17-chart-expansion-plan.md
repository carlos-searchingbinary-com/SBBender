# Chart Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 5 new chart types (stackedBar, donut, histogram, heatmap, candlestick) + annotations to ChartingSkill, and build a SwiftUI renderer that displays charts inline in chat.

**Architecture:** Extend ChartSpec with new types and data structs. Extend ChartingSkill with new auto-detection, validation, and parsing. Create ChartRendererView using Swift Charts framework. Integrate into ChatBubble for inline rendering.

**Tech Stack:** Swift Charts framework, SwiftUI, existing ChartSpec/ChartingSkill infrastructure.

---

### Task 1: Extend ChartSpec Data Model

**Files:**
- Modify: `Sources/SBBender/Skill/ChartSpec.swift`
- Test: `Tests/SBBenderTests/ChartingSkillTests.swift`

**Step 1: Write failing tests for new types and structs**

Add to `ChartingSkillTests.swift`:

```swift
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
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ChartingSkillTests 2>&1 | grep -E '(error|FAIL|compile)'`
Expected: Compilation errors — types don't exist yet.

**Step 3: Implement ChartSpec extensions**

In `Sources/SBBender/Skill/ChartSpec.swift`:

1. Add to `ChartType` enum:
```swift
case stackedBar
case donut
case histogram
case heatmap
case candlestick
```

2. Add `displayName` and `description` cases for each.

3. Add new structs inside `ChartSpec`:
```swift
public struct HeatmapCell: Codable, Sendable, Equatable {
    public let row: String
    public let column: String
    public let value: Double
    public init(row: String, column: String, value: Double) {
        self.row = row; self.column = column; self.value = value
    }
}

public struct CandlestickPoint: Codable, Sendable, Equatable {
    public let label: String
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public init(label: String, open: Double, high: Double, low: Double, close: Double) {
        self.label = label; self.open = open; self.high = high; self.low = low; self.close = close
    }
}

public struct Annotation: Codable, Sendable, Equatable {
    public let label: String
    public let value: Double
    public let style: String?
    public init(label: String, value: Double, style: String? = nil) {
        self.label = label; self.value = value; self.style = style
    }
}
```

4. Add new optional fields to `ChartSpec`:
```swift
public let heatmapData: [HeatmapCell]?
public let candlestickData: [CandlestickPoint]?
public let annotations: [Annotation]?
public let binCount: Int?
```

5. Update `init` to include new fields (with defaults of `nil`).

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ChartingSkillTests 2>&1 | tail -5`
Expected: All tests pass including new round-trip tests.

**Step 5: Commit**

```bash
git add Sources/SBBender/Skill/ChartSpec.swift Tests/SBBenderTests/ChartingSkillTests.swift
git commit -m "feat(charts): add 5 new chart types and annotations to ChartSpec"
```

---

### Task 2: Extend ChartingSkill — Parsing and Parameters

**Files:**
- Modify: `Sources/SBBender/Skill/ChartingSkill.swift`
- Test: `Tests/SBBenderTests/ChartingSkillTests.swift`

**Step 1: Write failing tests for new chart creation**

Add to `ChartingSkillTests.swift`:

```swift
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
    // Pass raw numeric values — skill should bin them
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
    #expect(spec.data!.count >= 3)  // should have multiple bins
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
                // No heatmapData
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
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ChartingSkillTests 2>&1 | grep -c FAIL`
Expected: Multiple failures — skill doesn't handle new types yet.

**Step 3: Implement ChartingSkill extensions**

In `Sources/SBBender/Skill/ChartingSkill.swift`:

1. Add new parameters to `toolParameters`:
   - `"binCount"` — integer for histogram bins
   - `"heatmapData"` — JSON array of `{row, column, value}`
   - `"candlestickData"` — JSON array of `{label, open, high, low, close}`
   - `"annotations"` — JSON array of `{label, value, style?}`

2. Update `DecodedArgs` with new optional fields: `binCount: String?`, `heatmapData: ChartDataInputGeneric?`, `candlestickData: ChartDataInputGeneric?`, `annotations: ChartDataInputGeneric?`.

3. In `buildChartSpec`, parse new fields: `parseHeatmapData`, `parseCandlestickData`, `parseAnnotations`, read `binCount` from params.

4. For histogram: if raw values are provided (DataPoints with only `value`, no `label`), auto-bin using Sturges' rule `ceil(log2(n) + 1)`. Create label+value DataPoints for each bin range like `"20-30"`.

5. Add validation in `validateData` for new types:
   - `.stackedBar`: requires `series`, not just `data`
   - `.donut`: same rules as `.pie`
   - `.histogram`: at least 3 numeric values
   - `.heatmap`: requires `heatmapData` with all fields
   - `.candlestick`: requires `candlestickData`, high >= low for all points

6. Add auto-detection cases in `resolveChartType` (before existing checks).

7. Pass new fields through to `ChartSpec` init.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ChartingSkillTests 2>&1 | tail -5`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add Sources/SBBender/Skill/ChartingSkill.swift Tests/SBBenderTests/ChartingSkillTests.swift
git commit -m "feat(charts): add parsing, validation, auto-detection for 5 new chart types + annotations"
```

---

### Task 3: Auto-Detection Tests for New Types

**Files:**
- Test: `Tests/SBBenderTests/ChartingSkillTests.swift`

**Step 1: Write failing auto-detection tests**

```swift
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
    // 7 categories with proportional values -> donut (too many for pie)
    #expect(spec.type == .donut)
    #expect(spec.autoDetected == true)
}
```

**Step 2: Run tests — they should pass since auto-detection was implemented in Task 2**

Run: `swift test --filter ChartingSkillTests 2>&1 | tail -5`
Expected: All pass.

**Step 3: Commit**

```bash
git add Tests/SBBenderTests/ChartingSkillTests.swift
git commit -m "test(charts): add auto-detection tests for new chart types"
```

---

### Task 4: SwiftUI Chart Renderer

**Files:**
- Create: `Sources/SBBenderApp/Views/Charts/ChartRendererView.swift`

**Step 1: Create ChartRendererView**

Create `Sources/SBBenderApp/Views/Charts/ChartRendererView.swift`:

```swift
import SwiftUI
import Charts
import SBBender

struct ChartRendererView: View {
    let spec: ChartSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = spec.title {
                Text(title)
                    .font(.headline)
            }
            chartContent
                .frame(height: chartHeight)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private var chartHeight: CGFloat {
        switch spec.type {
        case .heatmap:
            let rows = Set(spec.heatmapData?.map(\.row) ?? []).count
            return max(200, CGFloat(rows) * 40)
        case .pie, .donut:
            return 260
        default:
            return 300
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch spec.type {
        case .bar:
            barChart
        case .stackedBar:
            stackedBarChart
        case .line:
            lineChart
        case .area:
            areaChart
        case .pie:
            pieChart(innerRadius: 0)
        case .donut:
            pieChart(innerRadius: 0.4)
        case .scatter:
            scatterChart
        case .histogram:
            histogramChart
        case .heatmap:
            heatmapChart
        case .candlestick:
            candlestickChart
        }
    }
}
```

Then implement each chart method as `private var` computed properties using Swift Charts `Chart { }` with `BarMark`, `LineMark`, `AreaMark`, `PointMark`, `SectorMark`, `RuleMark`, `RectangleMark`.

Key patterns:
- **Bar**: `BarMark(x: .value(xLabel, label), y: .value(yLabel, value))` + series `foregroundStyle(by:)` for grouped
- **Stacked bar**: Same as bar but with `.foregroundStyle(by: .value("Series", seriesName))` on stacked series
- **Line**: `LineMark` with optional `PointMark` overlay
- **Area**: `AreaMark` with gradient fill
- **Pie/Donut**: `SectorMark(angle: .value(...), innerRadius: ...)` with `.foregroundStyle(by:)`
- **Scatter**: `PointMark(x: .value(..., x), y: .value(..., y))`
- **Histogram**: `BarMark` from pre-binned data (labels are bin ranges)
- **Heatmap**: `RectangleMark(x: .value(..., column), y: .value(..., row))` with `.foregroundStyle(by: .value("Value", value))`
- **Candlestick**: For each point, `RuleMark(x:, yStart: low, yEnd: high)` + `BarMark(x:, yStart: min(open,close), yEnd: max(open,close))` colored green/red
- **Annotations**: Overlay `RuleMark(y: .value(...))` with `.annotation { Text(label) }`

Add axis labels from `spec.xLabel` and `spec.yLabel` using `.chartXAxisLabel` and `.chartYAxisLabel`.

**Step 2: Build to verify compilation**

Run: `swift build 2>&1 | grep -E '(error|Build complete)'`
Expected: Build complete.

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Views/Charts/ChartRendererView.swift
git commit -m "feat(charts): add SwiftUI ChartRendererView for all 10 chart types"
```

---

### Task 5: Integrate Charts into Chat Bubbles

**Files:**
- Modify: `Sources/SBBenderApp/Views/Components/ChatBubble.swift`

**Step 1: Add chart detection and inline rendering**

In `ChatBubble.swift`, modify the assistant message content area to detect `__chart__` JSON and render `ChartRendererView` inline:

```swift
// Replace the plain Text(message.content) with:
if message.role == "assistant", let chartSpec = extractChartSpec(from: message.content) {
    // Split content: text before chart JSON + chart + text after
    let parts = splitAroundChart(message.content)
    if !parts.before.isEmpty {
        Text(parts.before)
            .textSelection(.enabled)
            .font(.body)
    }
    ChartRendererView(spec: chartSpec)
    if !parts.after.isEmpty {
        Text(parts.after)
            .textSelection(.enabled)
            .font(.body)
    }
} else {
    Text(message.content)
        .textSelection(.enabled)
        .font(.body)
}
```

Add helper methods:
```swift
private func extractChartSpec(from text: String) -> ChartSpec? {
    // Find JSON object containing "__chart__":true
    guard let startRange = text.range(of: "{\"__chart__\"") ?? text.range(of: "{ \"__chart__\"") else { return nil }
    let substring = text[startRange.lowerBound...]
    // Find matching closing brace
    var depth = 0
    var endIndex = substring.startIndex
    for (i, char) in substring.enumerated() {
        if char == "{" { depth += 1 }
        if char == "}" { depth -= 1 }
        if depth == 0 {
            endIndex = substring.index(substring.startIndex, offsetBy: i + 1)
            break
        }
    }
    let jsonStr = String(substring[substring.startIndex..<endIndex])
    guard let data = jsonStr.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(ChartSpec.self, from: data)
}

private func splitAroundChart(_ text: String) -> (before: String, after: String) {
    guard let startRange = text.range(of: "{\"__chart__\"") ?? text.range(of: "{ \"__chart__\"") else {
        return (text, "")
    }
    let before = String(text[text.startIndex..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    // Find end of JSON
    let substring = text[startRange.lowerBound...]
    var depth = 0
    var endIndex = substring.endIndex
    for (i, char) in substring.enumerated() {
        if char == "{" { depth += 1 }
        if char == "}" { depth -= 1 }
        if depth == 0 {
            endIndex = substring.index(substring.startIndex, offsetBy: i + 1)
            break
        }
    }
    let after = String(text[endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    return (before, after)
}
```

**Step 2: Build to verify compilation**

Run: `swift build 2>&1 | grep -E '(error|Build complete)'`
Expected: Build complete.

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Views/Components/ChatBubble.swift
git commit -m "feat(charts): render ChartSpec inline in chat bubbles"
```

---

### Task 6: Full Build + Test Verification

**Step 1: Run full build**

Run: `swift build 2>&1 | grep -E '(error|Build complete)'`
Expected: Build complete.

**Step 2: Run all charting tests**

Run: `swift test --filter ChartingSkillTests 2>&1 | tail -10`
Expected: All tests pass.

**Step 3: Run full test suite to check for regressions**

Run: `swift test --filter SBBenderTests 2>&1 | tail -5`
Expected: Same pass/fail as before (381/383 with 2 pre-existing failures).

**Step 4: Validate JSON for list types output**

Run a quick sanity check that `types` action returns all 10 chart types.

**Step 5: Final commit if any fixups needed, then push**

```bash
git push
```
