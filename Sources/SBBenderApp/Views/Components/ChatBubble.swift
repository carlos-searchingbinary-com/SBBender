import SwiftUI
import SBBender

struct ChatBubble: View {
    let message: ChatMessage

    @State private var isHovered = false

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
        .overlay(alignment: .topTrailing) {
            if isHovered && !message.content.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
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
        let (thinking, answer) = extractThinking(from: message.content)

        if isAssistantRole, let (before, chartSpec, after) = extractChart(from: answer) {
            if let thinking { ThinkingDisclosure(content: thinking) }
            if !before.isEmpty { MarkdownView(content: before).font(.body) }
            ChartRendererView(spec: chartSpec)
            if !after.isEmpty { MarkdownView(content: after).font(.body) }
        } else if message.role == "assistant-streaming" {
            if let thinking { ThinkingDisclosure(content: thinking) }
            HStack(spacing: 0) {
                MarkdownView(content: answer).font(.body)
                if answer.isEmpty { BlinkingCursor() }
            }
        } else if isAssistantRole {
            if let thinking { ThinkingDisclosure(content: thinking) }
            MarkdownView(content: answer).font(.body)
        } else {
            Text(message.content)
                .textSelection(.enabled)
                .font(.body)
        }
    }

    // Splits <think>…</think> from the visible answer
    private func extractThinking(from text: String) -> (thinking: String?, answer: String) {
        guard let start = text.range(of: "<think>"),
              let end = text.range(of: "</think>") else {
            // Still streaming the thinking block — hide it until </think> arrives
            if text.contains("<think>") {
                return ("...", "")
            }
            return (nil, text)
        }
        let thinking = String(text[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = String(text[end.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (thinking.isEmpty ? nil : thinking, answer)
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


// MARK: - Thinking Disclosure

struct ThinkingDisclosure: View {
    let content: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Thinking")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 4)
    }
}
