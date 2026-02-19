import SwiftUI

struct ToolConfirmationSheet: View {
    let confirmation: ToolConfirmationInfo
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text("Tool Confirmation")
                    .font(.title3.bold())

                Text("Your assistant wants to perform an action that requires your approval.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Tool details
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Tool name badge
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.fill")
                            .foregroundStyle(.orange)
                        Text(confirmation.toolName)
                            .font(.headline)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.08))
                    )

                    // Arguments
                    if !confirmation.arguments.isEmpty {
                        Text("Arguments")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(confirmation.arguments.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack(alignment: .top, spacing: 8) {
                                Text(key)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .lineLimit(4)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button {
                    onDeny()
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button {
                    onAllow()
                } label: {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 400, height: 360)
    }
}
