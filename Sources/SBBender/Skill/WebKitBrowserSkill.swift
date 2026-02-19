import Foundation
import SBBenderCore
import os

#if os(macOS)
import WebKit

/// Native WebKit-based browser skill that requires no external dependencies.
///
/// Unlike `BrowserSkill` (which requires Node.js + npx for Playwright MCP), this skill
/// uses a hidden WKWebView for all browser operations — zero installs needed.
///
/// Actions (exposed as individual tools via `ToolKit`):
/// - `navigate` — Load a URL and return page title
/// - `get_content` — Extract page text content
/// - `screenshot` — Capture viewport as base64 PNG
/// - `click` — Click an element by CSS selector
/// - `fill` — Fill a form field by CSS selector
/// - `evaluate_js` — Run arbitrary JavaScript
/// - `get_links` — Extract all links from the page
/// - `search_text` — Search for text on the page
public final class WebKitBrowserSkill: @unchecked Sendable, NativeTool, ToolKit {
    public let id = "webkit_browser"
    public let name = "webkit_browser"
    public let description = "Browse the web using native WebKit: navigate, extract content, click, fill forms, take screenshots"

    private let host: WebViewHost

    public init() {
        self.host = WebViewHost()
    }

    // MARK: - NativeTool

    public var isAvailable: Bool {
        get async { true }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let url = input.text, !url.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No URL provided")
        }
        let start = CFAbsoluteTimeGetCurrent()
        let title = try await host.navigate(to: url)
        let content = try await host.getContent()
        let truncated = content.count > 4000 ? String(content.prefix(4000)) + "\n... [truncated]" : content
        return NativeToolResult(
            output: "Title: \(title)\n\n\(truncated)",
            structuredData: ["url": url, "title": title],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }

    // MARK: - ToolKit

    public var tools: [SBTool] {
        [
            navigateTool,
            getContentTool,
            screenshotTool,
            clickTool,
            fillTool,
            evaluateJSTool,
            getLinksTool,
            searchTextTool,
        ]
    }

    // MARK: - NativeTool → Tool Override

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("URL to navigate to"),
            ],
            required: ["input"]
        )
    }

    public func asTool() -> SBTool {
        let skill = self
        return SBTool(
            name: "browser_navigate_and_read",
            description: "Navigate to a URL and return the page title and text content",
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: .text(args.input))
            return result.output
        }
    }

    // MARK: - Individual Tools

    private var navigateTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_navigate",
            description: "Navigate to a URL. Returns the page title.",
            parameters: JSONSchema(
                properties: ["url": .string("The URL to navigate to")],
                required: ["url"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let url: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let title = try await h.navigate(to: args.url)
            return "Navigated to page: \(title)"
        }
    }

    private var getContentTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_get_content",
            description: "Get the text content of the current page.",
            parameters: JSONSchema(
                properties: ["max_length": .string("Maximum characters to return (default: 8000)")],
                required: []
            )
        ) { arguments, _ in
            struct Args: Decodable { let max_length: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let maxLen = Int(args.max_length ?? "8000") ?? 8000
            let content = try await h.getContent()
            if content.count > maxLen {
                return String(content.prefix(maxLen)) + "\n... [truncated at \(maxLen) chars]"
            }
            return content
        }
    }

    private var screenshotTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_screenshot",
            description: "Take a screenshot of the current page viewport. Returns base64-encoded PNG.",
            parameters: JSONSchema()
        ) { _, _ in
            let base64 = try await h.screenshot()
            return base64
        }
    }

    private var clickTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_click",
            description: "Click an element on the page by CSS selector.",
            parameters: JSONSchema(
                properties: ["selector": .string("CSS selector for the element to click")],
                required: ["selector"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let selector: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            try await h.click(selector: args.selector)
            return "Clicked element: \(args.selector)"
        }
    }

    private var fillTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_fill",
            description: "Fill a form field by CSS selector with the given value.",
            parameters: JSONSchema(
                properties: [
                    "selector": .string("CSS selector for the input field"),
                    "value": .string("Value to fill in"),
                ],
                required: ["selector", "value"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let selector: String; let value: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            try await h.fill(selector: args.selector, value: args.value)
            return "Filled '\(args.selector)' with value"
        }
    }

    private var evaluateJSTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_evaluate_js",
            description: "Execute JavaScript on the current page and return the result.",
            parameters: JSONSchema(
                properties: ["script": .string("JavaScript code to execute")],
                required: ["script"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let script: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await h.evaluateJS(script: args.script)
            return result
        }
    }

    private var getLinksTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_get_links",
            description: "Get all links from the current page. Returns JSON array of {text, href} objects.",
            parameters: JSONSchema()
        ) { _, _ in
            try await h.getLinks()
        }
    }

    private var searchTextTool: SBTool {
        let h = host
        return SBTool(
            name: "browser_search_text",
            description: "Search for text on the current page. Returns matching text snippets with context.",
            parameters: JSONSchema(
                properties: ["query": .string("Text to search for on the page")],
                required: ["query"]
            )
        ) { arguments, _ in
            struct Args: Decodable { let query: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            return try await h.searchText(query: args.query)
        }
    }
}

// MARK: - WebViewHost

/// @MainActor helper that manages a hidden WKWebView for browser operations.
@MainActor
private final class WebViewHost: @unchecked Sendable {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var navigationDelegate: NavigationHandler?

    private func ensureWebView() -> WKWebView {
        if let existing = webView { return existing }
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let wv = WKWebView(frame: NSRect(x: -10000, y: -10000, width: 1280, height: 800), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        let win = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1280, height: 800),
                           styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = wv
        win.orderOut(nil)
        self.window = win
        self.webView = wv
        return wv
    }

    func navigate(to urlString: String) async throws -> String {
        let wv = ensureWebView()
        guard let url = URL(string: urlString) ?? URL(string: "https://\(urlString)") else {
            throw SBBenderError.skillExecutionFailed(skill: "webkit_browser", reason: "Invalid URL: \(urlString)")
        }

        let handler = NavigationHandler()
        self.navigationDelegate = handler
        wv.navigationDelegate = handler
        wv.load(URLRequest(url: url))

        try await handler.waitForNavigation()
        return wv.title ?? url.host ?? urlString
    }

    func getContent() async throws -> String {
        let wv = ensureWebView()
        let js = "document.body.innerText || document.documentElement.textContent || ''"
        let result = try await wv.evaluateJavaScript(js)
        return (result as? String) ?? ""
    }

    func screenshot() async throws -> String {
        let wv = ensureWebView()
        let config = WKSnapshotConfiguration()
        let image = try await wv.takeSnapshot(configuration: config)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SBBenderError.skillExecutionFailed(skill: "webkit_browser", reason: "Failed to capture screenshot")
        }
        return pngData.base64EncodedString()
    }

    func click(selector: String) async throws {
        let wv = ensureWebView()
        let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var el = document.querySelector('\(escaped)');
            if (!el) throw new Error('Element not found: \(escaped)');
            el.click();
            return 'clicked';
        })()
        """
        _ = try await wv.evaluateJavaScript(js)
    }

    func fill(selector: String, value: String) async throws {
        let wv = ensureWebView()
        let escapedSel = selector.replacingOccurrences(of: "'", with: "\\'")
        let escapedVal = value.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var el = document.querySelector('\(escapedSel)');
            if (!el) throw new Error('Element not found: \(escapedSel)');
            el.focus();
            el.value = '\(escapedVal)';
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return 'filled';
        })()
        """
        _ = try await wv.evaluateJavaScript(js)
    }

    func evaluateJS(script: String) async throws -> String {
        let wv = ensureWebView()
        let result = try await wv.evaluateJavaScript(script)
        if let str = result as? String { return str }
        if let num = result as? NSNumber { return num.stringValue }
        if result == nil { return "undefined" }
        if let data = try? JSONSerialization.data(withJSONObject: result!, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: result!)
    }

    func getLinks() async throws -> String {
        let wv = ensureWebView()
        let js = """
        JSON.stringify(Array.from(document.querySelectorAll('a[href]')).slice(0, 100).map(a => ({
            text: (a.textContent || '').trim().substring(0, 100),
            href: a.href
        })))
        """
        let result = try await wv.evaluateJavaScript(js)
        return (result as? String) ?? "[]"
    }

    func searchText(query: String) async throws -> String {
        let wv = ensureWebView()
        let escapedQuery = query.replacingOccurrences(of: "'", with: "\\'").lowercased()
        let js = """
        (function() {
            var text = document.body.innerText || '';
            var lower = text.toLowerCase();
            var query = '\(escapedQuery)';
            var results = [];
            var idx = 0;
            while (results.length < 10) {
                idx = lower.indexOf(query, idx);
                if (idx === -1) break;
                var start = Math.max(0, idx - 50);
                var end = Math.min(text.length, idx + query.length + 50);
                results.push('...' + text.substring(start, end) + '...');
                idx += query.length;
            }
            return results.length > 0 ? results.join('\\n---\\n') : 'No matches found for: ' + query;
        })()
        """
        let result = try await wv.evaluateJavaScript(js)
        return (result as? String) ?? "No matches found"
    }
}

// MARK: - Navigation Handler

@MainActor
private final class NavigationHandler: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForNavigation() async throws {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

#endif
