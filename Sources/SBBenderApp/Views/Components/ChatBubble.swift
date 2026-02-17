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

                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)

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

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case "user": AnyShapeStyle(Color.blue.opacity(0.06))
        case "assistant": AnyShapeStyle(Color.green.opacity(0.06))
        case "error": AnyShapeStyle(Color.red.opacity(0.06))
        default: AnyShapeStyle(Color.secondary.opacity(0.06))
        }
    }
}
