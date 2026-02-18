import Foundation

/// Fetches web content via URLSession and extracts readable text.
///
/// Lightweight alternative to BrowserSkill — no Playwright dependency.
/// Best for fetching articles, APIs, and static pages. For JavaScript-heavy
/// sites, use BrowserSkill instead.
///
/// Latency: Network-dependent (typically 0.5-3s).
public struct WebFetchSkill: NativeTool {
    public let id = "web-fetch"
    public let name = "fetchWebPage"
    public let description = "Fetch a web page and extract its text content"

    public let timeoutInterval: TimeInterval
    public let maxContentLength: Int

    public var isAvailable: Bool {
        get async { true }
    }

    /// Create a WebFetchSkill.
    ///
    /// - Parameters:
    ///   - timeoutInterval: Request timeout in seconds. Default: 15.
    ///   - maxContentLength: Maximum characters to return. Default: 50000.
    public init(timeoutInterval: TimeInterval = 15, maxContentLength: Int = 50_000) {
        self.timeoutInterval = timeoutInterval
        self.maxContentLength = maxContentLength
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The URL to fetch"),
                "query": .string("Optional: extract only content relevant to this query"),
            ],
            required: ["input"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String; let query: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            var params: [String: String] = [:]
            if let query = args.query { params["query"] = query }
            let result = try await skill.execute(input: NativeToolInput(text: args.input, parameters: params))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let urlString = input.text, !urlString.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No URL provided")
        }

        guard let url = URL(string: urlString) else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Invalid URL: \(urlString)")
        }

        let start = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Non-HTTP response")
        }

        guard (200..<400).contains(httpResponse.statusCode) else {
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "HTTP \(httpResponse.statusCode) for \(urlString)"
            )
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let rawText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""

        let extractedText: String
        if contentType.contains("html") {
            extractedText = Self.stripHTML(rawText)
        } else if contentType.contains("json") {
            // Pretty-print JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                extractedText = prettyString
            } else {
                extractedText = rawText
            }
        } else {
            extractedText = rawText
        }

        // Truncate if too long
        let output: String
        if extractedText.count > maxContentLength {
            output = String(extractedText.prefix(maxContentLength)) + "\n... [truncated, \(extractedText.count) chars total]"
        } else {
            output = extractedText
        }

        let latency = CFAbsoluteTimeGetCurrent() - start

        return NativeToolResult(
            output: output,
            structuredData: [
                "url": urlString,
                "statusCode": String(httpResponse.statusCode),
                "contentType": contentType,
                "contentLength": String(extractedText.count),
            ],
            confidence: 1.0,
            latency: latency
        )
    }

    /// Strip HTML tags and decode common entities, producing readable text.
    static func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style blocks entirely
        let blockPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
            "<!--[\\s\\S]*?-->",
        ]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }

        // Add newlines before block elements
        let blockTags = ["<br", "<p ", "<p>", "<div", "<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<li", "<tr", "<table", "<article", "<section"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n" + tag, options: .caseInsensitive)
        }

        // Remove all remaining HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&nbsp;", " "), ("&ndash;", "-"), ("&mdash;", "--"),
            ("&hellip;", "..."), ("&copy;", "(c)"), ("&reg;", "(R)"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric entities (&#123; or &#x1F;)
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: text),
                   let code = Int(text[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let range = Range(match.range, in: text)!
                    text.replaceSubrange(range, with: String(scalar))
                }
            }
        }

        // Collapse whitespace
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }
}
