import SwiftUI

struct ActivityFeedView: View {
    let events: [ActivityEvent]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(events) { event in
                        ActivityRow(event: event)
                            .id(event.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(12)
            }
            .onChange(of: events.count) { _, _ in
                if let last = events.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let event: ActivityEvent
    @State private var appeared = false

    private var isError: Bool {
        switch event.kind {
        case .error, .toolCallError: return true
        default: return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.icon)
                .font(.caption)
                .foregroundStyle(event.color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                if let name = event.agentName {
                    Text(name)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(event.description)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .primary)
                    .lineLimit(isError ? 4 : 2)
            }

            Spacer()

            Text(relativeTime(event.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isError ? Color.red.opacity(0.08) : event.color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isError ? Color.red.opacity(0.2) : .clear, lineWidth: 1)
        )
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                appeared = true
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 2 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
