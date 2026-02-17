# Chart Expansion Design: Data Analyst Focus

## Context

ChartingSkill produces ChartSpec JSON with 5 types (bar, line, pie, scatter, area). No SwiftUI renderer exists yet. Expanding to cover core data analysis workflows: distributions, comparisons, correlations, financials.

## New Chart Types

| Type | Use Case | Data Shape |
|---|---|---|
| `stackedBar` | Category breakdowns (revenue by product by region) | `series` with categorical labels |
| `donut` | Percentage breakdowns with center summary | `data` with label+value (like pie) |
| `histogram` | Distribution analysis, bin continuous data | `data` with just `value` (auto-binned) |
| `heatmap` | Correlation matrices, pivot tables | `heatmapData`: `{row, column, value}` |
| `candlestick` | Financial OHLC, time-range visualization | `candlestickData`: `{label, open, high, low, close}` |

## Cross-Cutting: Annotations

`annotations: [Annotation]?` on any chart type. Each annotation: `{label, value, style?}`. Rendered as RuleMark threshold lines (e.g. "average", "target", "budget").

## Data Model Changes (ChartSpec.swift)

New structs:
- `HeatmapCell`: `{ row: String, column: String, value: Double }`
- `CandlestickPoint`: `{ label: String, open: Double, high: Double, low: Double, close: Double }`
- `Annotation`: `{ label: String, value: Double, style: String? }` — style: "line" (default) or "area"

New fields on ChartSpec:
- `heatmapData: [HeatmapCell]?`
- `candlestickData: [CandlestickPoint]?`
- `annotations: [Annotation]?`
- `binCount: Int?` — for histogram (default: Sturges' rule)

ChartType enum gains: `stackedBar`, `donut`, `histogram`, `heatmap`, `candlestick`.

## ChartingSkill Changes

New tool parameters: `binCount`, `heatmapData`, `candlestickData`, `annotations`.

Auto-detection additions:
- All numeric values, no labels, >10 points -> histogram
- Data has row+column+value -> heatmap
- Data has open+high+low+close -> candlestick
- Existing pie detection + >6 categories -> donut
- Multiple series with categorical labels -> stackedBar

Validation:
- Histogram: >= 3 numeric values
- Heatmap: all cells need row, column, value
- Candlestick: all points need OHLC; high >= low
- Stacked bar: requires series
- Donut: same as pie

## SwiftUI Renderer (NEW: ChartRendererView.swift)

Single view: `ChartRendererView(spec: ChartSpec)`:
- Title header
- Swift Charts `Chart { }` switching on type
- bar/line/area: BarMark/LineMark/AreaMark
- scatter: PointMark
- pie/donut: SectorMark (donut uses innerRadius)
- stackedBar: BarMark with series foregroundStyle
- histogram: BarMark from pre-binned data
- heatmap: RectangleMark with color scale
- candlestick: RuleMark (high-low) + BarMark (open-close)
- Annotations: RuleMark overlay for threshold lines
- Axis labels from xLabel/yLabel

Size: ~300pt height, full message width. Heatmap taller based on row count.

## Chat Integration

In AgentChatView, detect `"__chart__":true` in assistant message text. Decode ChartSpec, render ChartRendererView inline instead of markdown.

## Files

| File | Change |
|---|---|
| `Sources/SBBender/Skill/ChartSpec.swift` | 5 new ChartTypes, HeatmapCell, CandlestickPoint, Annotation, binCount |
| `Sources/SBBender/Skill/ChartingSkill.swift` | New params, auto-detection, validation |
| `Sources/SBBenderApp/Views/Charts/ChartRendererView.swift` | NEW — Swift Charts renderer for all 10 types |
| `Sources/SBBenderApp/Views/Agents/AgentChatView.swift` | Detect __chart__ JSON, render inline |
| `Tests/SBBenderTests/ChartingSkillTests.swift` | Tests for new types + annotations |

## Testing

- ChartSpec: encode/decode round-trip for all 10 types + annotations
- ChartingSkill: auto-detection for new types, validation errors, edge cases
- SwiftUI rendering: manual testing in app
