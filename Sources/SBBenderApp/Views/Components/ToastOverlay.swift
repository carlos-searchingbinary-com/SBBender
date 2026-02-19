import SwiftUI

// MARK: - Toast Message

struct ToastMessage: Identifiable {
    let id: String
    let severity: Severity
    let title: String
    let message: String
    let timestamp: Date

    enum Severity {
        case info, warning, error

        var icon: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: .blue
            case .warning: .orange
            case .error: .red
            }
        }
    }

    init(severity: Severity, title: String, message: String = "") {
        self.id = UUID().uuidString
        self.severity = severity
        self.title = title
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Toast Overlay

struct ToastOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(appState.toasts) { toast in
                ToastCard(toast: toast) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.dismissToast(id: toast.id)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(.spring(duration: 0.3), value: appState.toasts.map(\.id))
    }
}

// MARK: - Toast Card

private struct ToastCard: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.severity.icon)
                .font(.body)
                .foregroundStyle(toast.severity.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.medium))
                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(toast.severity.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .frame(maxWidth: 420)
        .task {
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}
