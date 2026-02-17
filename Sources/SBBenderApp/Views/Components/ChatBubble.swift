import SwiftUI
import SBBender

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            roleIcon
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(message.role.capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(roleColor)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                messageContent

                if let calls = message.toolCalls, !calls.isEmpty {
                    ForEach(calls) { call in
                        ToolCallCard(toolCall: call)
                    }
                }
            }
        }
        .padding(12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var roleIcon: some View {
        Image(systemName: iconName)
            .font(.title3)
            .foregroundStyle(roleColor)
            .frame(width: 28)
    }

    private var iconName: String {
        switch message.role {
        case "user": "person.fill"
        case "assistant": "sparkles"
        case "error": "exclamationmark.triangle.fill"
        default: "ellipsis.circle"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case "user": .blue
        case "assistant": .green
        case "error": .red
        default: .secondary
        }
    }

    // MARK: - Message Content (with inline chart detection)

    @ViewBuilder
    private var messageContent: some View {
        if message.role == "assistant", let (before, chartSpec, after) = extractChart(from: message.content) {
            if !before.isEmpty {
                Text(before)
                    .textSelection(.enabled)
                    .font(.body)
            }
            ChartRendererView(spec: chartSpec)
            if !after.isEmpty {
                Text(after)
                    .textSelection(.enabled)
                    .font(.body)
            }
        } else {
            Text(message.content)
                .textSelection(.enabled)
                .font(.body)
        }
    }

    private func extractChart(from text: String) -> (String, ChartSpec, String)? {
        // Find JSON object containing "__chart__"
        guard let startIdx = text.range(of: "{\"__chart__\"")?.lowerBound
                ?? text.range(of: "{ \"__chart__\"")?.lowerBound else { return nil }

        // Find matching closing brace
        let substring = text[startIdx...]
        var depth = 0
        var endIdx = substring.endIndex
        for i in substring.indices {
            if substring[i] == "{" { depth += 1 }
            if substring[i] == "}" {
                depth -= 1
                if depth == 0 {
                    endIdx = text.index(after: i)
                    break
                }
            }
        }

        let jsonStr = String(text[startIdx..<endIdx])
        guard let data = jsonStr.data(using: .utf8),
              let spec = try? JSONDecoder().decode(ChartSpec.self, from: data) else { return nil }

        let before = String(text[text.startIndex..<startIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(text[endIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before, spec, after)
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case "user": AnyShapeStyle(Color.blue.opacity(0.06))
        case "assistant": AnyShapeStyle(Color.green.opacity(0.06))
        case "error": AnyShapeStyle(Color.red.opacity(0.06))
        default: AnyShapeStyle(Color.secondary.opacity(0.06))
        }
    }
}
