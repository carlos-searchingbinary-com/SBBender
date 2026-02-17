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
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(event.color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                appeared = true
            }
        }
    }
}
