import SwiftUI

/// Renders markdown content with proper block-level layout.
///
/// Parses content into blocks (headings, paragraphs, lists, code blocks) and
/// renders each block separately so paragraph spacing and list formatting work
/// correctly — something `Text(AttributedString(...))` cannot do alone.
struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            inlineText(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let text, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(indent) * 12)
                inlineText(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numberedItem(let number, let text, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text("\(number).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, CGFloat(indent) * 12)
                inlineText(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .codeBlock(let code, _):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .thematicBreak:
            Divider()
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
        return inlineText(text)
            .font(font)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, level <= 2 ? 4 : 0)
    }

    // Renders inline markdown (bold, italic, code) via AttributedString
    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    // MARK: - Block Parser

    private func parseBlocks(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var i = 0
        var codeLines: [String] = []
        var codeLang: String? = nil
        var inCodeBlock = false

        while i < lines.count {
            let raw = lines[i]
            let line = raw

            // Code fence
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n"), language: codeLang))
                    codeLines = []
                    codeLang = nil
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                i += 1
                continue
            }

            // Thematic break
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "---" || stripped == "***" || stripped == "___" {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // Heading
            if let heading = parseHeading(line) {
                blocks.append(heading)
                i += 1
                continue
            }

            // List item (unordered)
            if let (text, indent) = parseListItem(line) {
                blocks.append(.listItem(text, indent: indent))
                i += 1
                continue
            }

            // List item (ordered)
            if let (num, text, indent) = parseOrderedItem(line) {
                blocks.append(.numberedItem(num, text, indent: indent))
                i += 1
                continue
            }

            // Empty line — skip (spacing handled by VStack spacing)
            if stripped.isEmpty {
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let pLine = lines[i]
                let pStripped = pLine.trimmingCharacters(in: .whitespaces)

                // Stop at structural elements
                if pStripped.isEmpty
                    || pLine.hasPrefix("```")
                    || parseHeading(pLine) != nil
                    || parseListItem(pLine) != nil
                    || parseOrderedItem(pLine) != nil
                    || pStripped == "---" || pStripped == "***" || pStripped == "___"
                {
                    break
                }
                paraLines.append(pLine)
                i += 1
            }

            if !paraLines.isEmpty {
                // Join with space to form a single paragraph
                let para = paraLines.joined(separator: " ")
                blocks.append(.paragraph(para))
            }
        }

        // Unclosed code block
        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n"), language: codeLang))
        }

        return blocks
    }

    // MARK: - Line Parsers

    private func parseHeading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var rest = line[line.startIndex...]
        while rest.first == "#" {
            level += 1
            rest = rest.dropFirst()
        }
        guard level <= 6, rest.first == " " else { return nil }
        let text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level, text)
    }

    private func parseListItem(_ line: String) -> (String, indent: Int)? {
        let indent = leadingSpaceCount(line) / 2
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))
        let prefixes = ["- ", "* ", "+ "]
        for prefix in prefixes {
            if trimmed.hasPrefix(prefix) {
                let text = String(trimmed.dropFirst(prefix.count))
                return (text, indent)
            }
        }
        return nil
    }

    private func parseOrderedItem(_ line: String) -> (Int, String, indent: Int)? {
        let indent = leadingSpaceCount(line) / 2
        let trimmed = line.trimmingCharacters(in: .init(charactersIn: " \t"))
        // Match "1. " or "12. " etc.
        var numStr = ""
        var rest = trimmed[trimmed.startIndex...]
        while let c = rest.first, c.isNumber {
            numStr.append(c)
            rest = rest.dropFirst()
        }
        guard !numStr.isEmpty,
              rest.hasPrefix(". "),
              let num = Int(numStr) else { return nil }
        let text = String(rest.dropFirst(2))
        return (num, text, indent)
    }

    private func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for c in line {
            if c == " " { count += 1 }
            else if c == "\t" { count += 2 }
            else { break }
        }
        return count
    }
}

// MARK: - Block Types

private enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case listItem(String, indent: Int)
    case numberedItem(Int, String, indent: Int)
    case codeBlock(String, language: String?)
    case thematicBreak
}
