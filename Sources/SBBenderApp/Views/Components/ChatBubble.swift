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
                    ToolCallBadges(toolCalls: calls)
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
        case "assistant-streaming": "sparkles"
        case "error": "exclamationmark.triangle.fill"
        default: "ellipsis.circle"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case "user": .blue
        case "assistant": .green
        case "assistant-streaming": .green
        case "error": .red
        default: .secondary
        }
    }

    // MARK: - Message Content (with inline chart detection)

    private var isAssistantRole: Bool {
        message.role == "assistant" || message.role == "assistant-streaming"
    }

    @ViewBuilder
    private var messageContent: some View {
        if isAssistantRole, let (before, chartSpec, after) = extractChart(from: message.content) {
            if !before.isEmpty {
                MarkdownView(content: before)
                    .font(.body)
            }
            ChartRendererView(spec: chartSpec)
            if !after.isEmpty {
                MarkdownView(content: after)
                    .font(.body)
            }
        } else if message.role == "assistant-streaming" {
            HStack(spacing: 0) {
                MarkdownView(content: message.content)
                    .font(.body)
                BlinkingCursor()
            }
        } else if isAssistantRole {
            MarkdownView(content: message.content)
                .font(.body)
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
        case "assistant", "assistant-streaming": AnyShapeStyle(Color.green.opacity(0.06))
        case "error": AnyShapeStyle(Color.red.opacity(0.06))
        default: AnyShapeStyle(Color.secondary.opacity(0.06))
        }
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("\u{258A}")
            .font(.body)
            .foregroundColor(.green)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

