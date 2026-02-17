import SwiftUI

/// Renders full markdown content using AttributedString.
///
/// Supports headings, code blocks, bullet lists, bold, italic, links, and
/// other block-level markdown that `Text(LocalizedStringKey(...))` cannot handle.
struct MarkdownView: View {
    let content: String

    @State private var attributedString: AttributedString?

    var body: some View {
        Group {
            if let attributedString {
                Text(attributedString)
                    .textSelection(.enabled)
            } else {
                // Fallback while parsing or if parsing fails
                Text(content)
                    .textSelection(.enabled)
            }
        }
        .task(id: content) {
            attributedString = parseMarkdown(content)
        }
    }

    private func parseMarkdown(_ source: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        options.allowsExtendedAttributes = true

        // Try full markdown first
        if let full = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full)
        ) {
            return full
        }

        // Fall back to inline-only
        if let inline = try? AttributedString(
            markdown: source,
            options: options
        ) {
            return inline
        }

        return nil
    }
}
