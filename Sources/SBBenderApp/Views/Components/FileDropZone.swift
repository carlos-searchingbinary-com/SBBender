import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    let supportedTypes: [String]
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    init(
        supportedTypes: [String] = ["txt", "md", "pdf", "pptx", "swift", "py", "js", "json", "csv"],
        onDrop: @escaping ([URL]) -> Void
    ) {
        self.supportedTypes = supportedTypes
        self.onDrop = onDrop
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop files or folders here")
                .font(.headline)
                .foregroundStyle(isTargeted ? .primary : .secondary)

            Text(supportedTypes.map { ".\($0)" }.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            onDrop(urls)
        }
    }
}
