import SwiftUI

/// Human-readable metadata for native tool IDs.
enum SkillMetadata {
    struct Info {
        let name: String
        let icon: String
        let description: String
    }

    static let all: [String: Info] = [
        // Language
        "language-detection": Info(name: "Language Detection", icon: "textformat", description: "Detect the language of text"),
        "sentiment": Info(name: "Sentiment", icon: "face.smiling", description: "Analyze emotional tone of text"),
        "entity-extraction": Info(name: "Entity Extraction", icon: "person.text.rectangle", description: "Extract names, places, and organizations"),
        "tokenization": Info(name: "Tokenization", icon: "text.word.spacing", description: "Split text into tokens and sentences"),
        "embedding-distance": Info(name: "Similarity", icon: "arrow.left.and.right", description: "Compare semantic similarity of texts"),
        // System
        "shell": Info(name: "Terminal", icon: "terminal", description: "Run shell commands"),
        "applescript": Info(name: "AppleScript", icon: "applescript", description: "Automate macOS apps"),
        "web-fetch": Info(name: "Web Fetch", icon: "globe", description: "Fetch and read web pages"),
        "browser": Info(name: "Browser", icon: "safari", description: "Browse the web interactively"),
        "shortcuts": Info(name: "Shortcuts", icon: "square.on.square.badge.person.crop", description: "Run Siri Shortcuts"),
        // Data
        "data-analysis": Info(name: "Data Analysis", icon: "tablecells", description: "Load and query data with SQL"),
        "charting": Info(name: "Charts", icon: "chart.bar", description: "Create charts and visualizations"),
        // Communication
        "email": Info(name: "Email", icon: "envelope", description: "Read and compose emails"),
        // Calendar
        "calendar": Info(name: "Calendar", icon: "calendar", description: "Read and create calendar events"),
        "reminders": Info(name: "Reminders", icon: "checklist", description: "Manage reminders and to-dos"),
        // Media
        "transcription": Info(name: "Transcription", icon: "waveform", description: "Transcribe audio to text"),
        "screencapture": Info(name: "Screen Capture", icon: "rectangle.dashed.badge.record", description: "Capture screen content"),
        "vision": Info(name: "Vision", icon: "eye", description: "Analyze images and visual content"),
        "translation": Info(name: "Translation", icon: "character.book.closed", description: "Translate between languages"),
    ]

    /// Get human-readable name for a skill ID, falling back to titlecased ID.
    static func displayName(for id: String) -> String {
        all[id]?.name ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Get SF Symbol icon for a skill ID.
    static func icon(for id: String) -> String {
        all[id]?.icon ?? "puzzlepiece"
    }
}
