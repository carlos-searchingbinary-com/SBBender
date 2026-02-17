import SwiftUI
import SBBender

struct SkillDetailSheet: View {
    let skill: SkillListEntry
    @Bindable var viewModel: MarketplaceViewModel
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    var isInstalled: Bool { viewModel.installedSlugs.contains(skill.slug) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.title2.bold())
                    Text(skill.slug)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Details") {
                        LabeledContent("Version", value: skill.version)
                        if !skill.author.isEmpty {
                            LabeledContent("Author", value: skill.author)
                        }
                        if skill.downloads > 0 {
                            LabeledContent("Downloads", value: "\(skill.downloads)")
                        }
                    }

                    GroupBox("Description") {
                        Text(skill.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Requirements") {
                        Text("Skills run in sandboxed Linux containers via the Containerization framework. Requires macOS 26+.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                        }
                    }

                    // Actions
                    HStack {
                        Spacer()
                        if isInstalled {
                            Button("Uninstall", role: .destructive) {
                                Task { await viewModel.uninstall(skill: skill, appState: appState) }
                            }
                            .buttonStyle(.bordered)
                        } else if viewModel.installingSlugs.contains(skill.slug) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Install") {
                                Task { await viewModel.installFromRegistry(skill: skill, appState: appState) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}
