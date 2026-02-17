import Foundation
import os

/// Client for the skills.sh registry (https://skills.sh).
///
/// skills.sh skills are markdown instruction files (SKILL.md) that provide
/// agent instructions and guidance — not executable code. They come from
/// GitHub repositories and are installed as local instruction files.
public actor SkillsShClient {
    /// Base URL for the skills.sh search API.
    public let apiURL: URL
    /// URLSession for API calls.
    private let session: URLSession
    /// Local directory where installed skills are stored.
    public let skillsDirectory: URL

    private static let logger = Logger(subsystem: "com.sbbender", category: "skills-sh")

    public init(
        apiURL: URL = URL(string: "https://skills.sh")!,
        skillsDirectory: URL? = nil,
        session: URLSession = .shared
    ) {
        self.apiURL = apiURL
        self.session = session

        if let dir = skillsDirectory {
            self.skillsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.skillsDirectory = appSupport
                .appendingPathComponent("com.sbbender")
                .appendingPathComponent("skills-sh")
        }
    }

    // MARK: - Search

    /// Search the skills.sh registry.
    ///
    /// - Parameters:
    ///   - query: Search query string.
    ///   - limit: Maximum number of results (default 20).
    /// - Returns: Array of matching skill entries.
    public func search(query: String, limit: Int = 20) async throws -> [SkillsShEntry] {
        var components = URLComponents(url: apiURL.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        guard let url = components.url else {
            throw SkillsShError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse else {
            throw SkillsShError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SkillsShError.httpError(status: http.statusCode)
        }

        let result = try JSONDecoder().decode(SkillsShSearchResponse.self, from: data)
        return result.skills
    }

    // MARK: - Fetch Skill Content

    /// Fetch a skill's SKILL.md content from its GitHub source.
    ///
    /// Uses the GitHub Trees API to find all SKILL.md files in the repo,
    /// then fetches each one until finding the one whose frontmatter `name:`
    /// matches the skill name. This mirrors how the skills.sh CLI works:
    /// it clones the repo, walks the filesystem, and matches by name — not
    /// by directory name (which can differ from the skill name).
    public func fetchSkill(_ entry: SkillsShEntry) async throws -> SkillsShContent {
        let source = entry.source
        let name = entry.name

        // Step 1: Use GitHub Trees API to find all SKILL.md paths
        for branch in ["main", "master"] {
            guard let skillMDPaths = try? await findSkillMDPaths(source: source, branch: branch) else {
                continue
            }

            // Step 2: Fetch each SKILL.md and match by frontmatter name
            for path in skillMDPaths {
                let rawURL = URL(string: "https://raw.githubusercontent.com/\(source)/\(branch)/\(path)")!
                do {
                    let (data, response) = try await session.data(from: rawURL)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let content = String(data: data, encoding: .utf8) else {
                        continue
                    }

                    let parsed = parseSkillMD(content, name: name)
                    // Match: the frontmatter name must match the skill name (case-insensitive)
                    if parsed.name.lowercased() == name.lowercased() {
                        // Derive the directory path from the SKILL.md path
                        let dirPath = (path as NSString).deletingLastPathComponent
                        let resolved = parseSkillMD(content, name: name, resolvedPath: dirPath.isEmpty ? nil : dirPath, resolvedBranch: branch)
                        Self.logger.info("Fetched skill '\(name)' from \(source)/\(path) (\(branch))")
                        return resolved
                    }
                } catch {
                    continue
                }
            }
        }

        throw SkillsShError.skillNotFound(name: name, source: source)
    }

    /// Find all SKILL.md file paths in a GitHub repo using the Trees API.
    private func findSkillMDPaths(source: String, branch: String) async throws -> [String] {
        let url = URL(string: "https://api.github.com/repos/\(source)/git/trees/\(branch)?recursive=1")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        struct TreeResponse: Decodable {
            struct Entry: Decodable {
                let path: String
                let type: String
            }
            let tree: [Entry]
        }

        let tree = try JSONDecoder().decode(TreeResponse.self, from: data)
        return tree.tree
            .filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }
            .map(\.path)
    }

    // MARK: - List Files

    /// List files in a skill's GitHub directory.
    ///
    /// Requires a resolved `SkillsShContent` to know the directory path.
    public func fetchSkillFiles(entry: SkillsShEntry, content: SkillsShContent) async throws -> [SkillsShFile] {
        guard let dirPath = content.resolvedPath,
              let branch = content.resolvedBranch else {
            return []
        }

        // Use GitHub API to list directory contents
        let apiURL = URL(string: "https://api.github.com/repos/\(entry.source)/contents/\(dirPath)?ref=\(branch)")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        struct GitHubFile: Decodable {
            let name: String
            let path: String
            let size: Int?
            let download_url: String?
            let type: String // "file" or "dir"
        }

        let files = try JSONDecoder().decode([GitHubFile].self, from: data)
        return files
            .filter { $0.type == "file" }
            .map { SkillsShFile(name: $0.name, path: $0.path, size: $0.size ?? 0, downloadURL: $0.download_url) }
    }

    /// Fetch the content of a specific file from GitHub.
    public func fetchFileContent(downloadURL: String) async throws -> String {
        guard let url = URL(string: downloadURL) else {
            throw SkillsShError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SkillsShError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? "(binary file)"
    }

    // MARK: - Install

    /// Install a skill locally by fetching its content and all supporting files.
    ///
    /// Downloads the SKILL.md plus all sibling files (scripts, configs, etc.)
    /// from the skill's GitHub directory — mirroring how the skills.sh CLI works.
    ///
    /// - Parameter entry: The skill entry to install.
    /// - Returns: A `Skill` wrapping the installed content.
    public func install(_ entry: SkillsShEntry) async throws -> Skill {
        let content = try await fetchSkill(entry)

        // Save to local directory
        let skillDir = skillsDirectory.appendingPathComponent(sanitizeName(content.name))
        let fm = FileManager.default
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        // Always save SKILL.md (we already have its content)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try content.rawContent.write(to: skillFile, atomically: true, encoding: .utf8)

        // Download all sibling files from the skill directory
        let files = try await fetchSkillFiles(entry: entry, content: content)
        for file in files where file.name != "SKILL.md" {
            guard let downloadURL = file.downloadURL else { continue }
            do {
                let fileContent = try await fetchFileContent(downloadURL: downloadURL)
                let filePath = skillDir.appendingPathComponent(file.name)
                try fileContent.write(to: filePath, atomically: true, encoding: .utf8)
                Self.logger.debug("Downloaded \(file.name) (\(file.size) bytes)")
            } catch {
                Self.logger.warning("Failed to download \(file.name): \(error)")
            }
        }

        // Save metadata
        let meta = SkillsShMeta(
            name: content.name,
            description: content.description,
            source: entry.source,
            slug: entry.slug,
            installedAt: Date()
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: skillDir.appendingPathComponent("meta.json"))

        Self.logger.info("Installed skill '\(content.name)' (\(files.count) files) to \(skillDir.path)")

        // Scan for scripts and references
        let scripts = scanScripts(in: skillDir)
        let references = scanReferences(in: skillDir)

        return Skill(
            id: "skills-sh-\(content.name)",
            name: content.name,
            description: content.description,
            instructions: content.instructions,
            scripts: scripts,
            allowedTools: content.allowedTools,
            references: references,
            source: entry.source,
            localPath: skillDir
        )
    }

    /// Create a skill locally from user-provided content.
    ///
    /// Builds a SKILL.md with YAML frontmatter and saves it alongside a
    /// `meta.json` with `source: "local"`.
    ///
    /// - Parameters:
    ///   - name: Skill name.
    ///   - description: Short description.
    ///   - instructions: Markdown instructions (the SKILL.md body).
    ///   - allowedTools: Optional list of allowed tool IDs.
    /// - Returns: The created `Skill`.
    public func createLocal(
        name: String,
        description: String,
        instructions: String,
        allowedTools: [String]? = nil
    ) throws -> Skill {
        let skillDir = skillsDirectory.appendingPathComponent(sanitizeName(name))
        let fm = FileManager.default
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        // Build SKILL.md with frontmatter
        var frontmatter = "---\nname: \(name)\ndescription: \(description)\n"
        if let tools = allowedTools, !tools.isEmpty {
            frontmatter += "allowed-tools: \(tools.joined(separator: ", "))\n"
        }
        frontmatter += "---\n\n"

        let skillContent = frontmatter + instructions
        let skillFile = skillDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillFile, atomically: true, encoding: .utf8)

        // Save metadata
        let meta = SkillsShMeta(
            name: name,
            description: description,
            source: "local",
            slug: sanitizeName(name),
            installedAt: Date()
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: skillDir.appendingPathComponent("meta.json"))

        let scripts = scanScripts(in: skillDir)
        let references = scanReferences(in: skillDir)

        Self.logger.info("Created local skill '\(name)' at \(skillDir.path)")

        return Skill(
            id: "skills-sh-\(name)",
            name: name,
            description: description,
            instructions: instructions,
            scripts: scripts,
            allowedTools: allowedTools,
            references: references,
            source: "local",
            localPath: skillDir
        )
    }

    // MARK: - Baseline Skills

    /// Seed baseline skills on first launch.
    ///
    /// Writes built-in SKILL.md files to the skills directory. Skips any
    /// skill whose directory already exists so user modifications are preserved.
    public func seedBaselineSkills() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)

        for definition in Self.baselineSkills {
            let dirName = sanitizeName(definition.name)
            let skillDir = skillsDirectory.appendingPathComponent(dirName)
            guard !fm.fileExists(atPath: skillDir.path) else { continue }

            _ = try createLocal(
                name: definition.name,
                description: definition.description,
                instructions: definition.instructions,
                allowedTools: definition.allowedTools
            )
            Self.logger.info("Seeded baseline skill '\(definition.name)'")
        }
    }

    private struct BaselineSkillDefinition {
        let name: String
        let description: String
        let instructions: String
        let allowedTools: [String]?
    }

    // swiftlint:disable line_length
    private static let baselineSkills: [BaselineSkillDefinition] = [
        BaselineSkillDefinition(
            name: "email-triage",
            description: "Scans your inbox, scores urgency, flags important messages and creates reminders for action items.",
            instructions: """
            You are an email triage assistant. Your job is to process the user's unread emails and help them focus on what matters.

            ## Workflow

            1. **Fetch unread emails** using the email tool's `getUnread` action.
            2. **For each email**, analyze:
               - **Urgency**: Use sentiment analysis to detect tone (angry, urgent, casual).
               - **Key entities**: Extract people, organizations, dates, and deadlines with entity extraction.
               - **Action required?**: Determine if the email needs a reply, a task, or is purely informational.
            3. **Score and rank** emails by priority:
               - **High**: Negative sentiment + contains deadlines or requests → flag it.
               - **Medium**: Neutral tone + contains action items → note it.
               - **Low**: Positive/informational with no action needed → skip.
            4. **For high-priority emails**, create a reminder with the deadline (or "end of day" if none specified).
            5. **Present a summary** grouped by priority, with one-line descriptions and recommended actions.

            ## Output Format

            ```
            📬 Email Triage Summary
            ━━━━━━━━━━━━━━━━━━━━━

            🔴 HIGH PRIORITY (action needed)
            • [Sender] — Subject — "Key quote" → Suggested action
              ⏰ Reminder set for [time]

            🟡 MEDIUM (review when possible)
            • [Sender] — Subject — Brief note

            🟢 LOW (informational)
            • [Sender] — Subject
            ```

            ## Rules
            - Never mark anything as high priority unless it clearly requires action.
            - If you can't determine urgency, default to medium.
            - Keep summaries concise — one line per email.
            - Always tell the user how many emails were processed.
            """,
            allowedTools: ["email", "sentiment", "entity-extraction", "reminders"]
        ),

        BaselineSkillDefinition(
            name: "daily-briefing",
            description: "Morning snapshot: unread emails, today's calendar, due reminders — all in one summary.",
            instructions: """
            You are a daily briefing assistant. When invoked, produce a concise morning overview of the user's day.

            ## Workflow

            1. **Calendar**: Fetch today's events. List them chronologically with times, titles, and locations.
            2. **Reminders**: Fetch reminders due today or overdue. List them with due times.
            3. **Email**: Fetch unread emails. Summarize the count and highlight the top 3 most relevant (use sentiment to detect urgency).
            4. **Compile** everything into a single briefing.

            ## Output Format

            ```
            ☀️ Daily Briefing — [Today's Date]
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            📅 Schedule ([N] events)
            • [Time] — Event title (Location)
            • [Time] — Event title

            ✅ Reminders ([N] due)
            • Reminder title — due [time]
            • ⚠️ OVERDUE: Reminder title — was due [date]

            📬 Inbox ([N] unread)
            • Top emails with one-line summaries
            • "See email-triage for full processing"

            💡 Heads Up
            • Any scheduling conflicts
            • Back-to-back meetings
            • Overdue items that need attention
            ```

            ## Rules
            - Keep it scannable — this is a 30-second read, not a report.
            - Flag conflicts (overlapping events) explicitly.
            - If there are no events, reminders, or emails, say so briefly.
            - Always include today's date at the top.
            """,
            allowedTools: ["calendar", "reminders", "email", "sentiment"]
        ),

        BaselineSkillDefinition(
            name: "writing-coach",
            description: "Analyzes writing for tone, readability, and consistency. Suggests improvements.",
            instructions: """
            You are a writing coach. Analyze the user's text and provide actionable feedback to improve clarity, tone, and impact.

            ## Analysis Steps

            1. **Language detection** — Identify the language so feedback is appropriate.
            2. **Sentiment analysis** — Assess the overall tone. Is it what the user likely intends?
            3. **Entity extraction** — Find names, organizations, and terms. Check for consistency (e.g., "OpenAI" vs "Open AI").
            4. **Tokenization** — Break into sentences to evaluate:
               - Average sentence length (flag if consistently > 25 words).
               - Variety in sentence structure.
               - Paragraph balance.

            ## Feedback Format

            ```
            ✍️ Writing Analysis
            ━━━━━━━━━━━━━━━━━━

            📊 Overview
            • Language: [detected]
            • Tone: [sentiment reading + interpretation]
            • Word count: [N] | Sentences: [N] | Avg sentence length: [N]

            🎯 Strengths
            • What works well (be specific, quote examples)

            ⚡ Suggestions
            1. [Issue] — "Original quote" → Suggested revision + why
            2. [Issue] — "Original quote" → Suggested revision + why

            🔤 Consistency
            • Entity inconsistencies found (if any)
            • Terminology suggestions

            📈 Readability
            • Sentence length distribution assessment
            • Suggestions for rhythm and flow
            ```

            ## Rules
            - Be encouraging. Lead with strengths before suggestions.
            - Limit suggestions to the top 5 most impactful changes.
            - Always explain *why* a change improves the writing, not just *what* to change.
            - Respect the author's voice — suggest, don't rewrite wholesale.
            - If the text is already strong, say so and offer only minor polish.
            """,
            allowedTools: ["sentiment", "entity-extraction", "tokenization", "language-detection"]
        ),

        BaselineSkillDefinition(
            name: "translate-localizer",
            description: "Translates content while preserving technical terms, code blocks, and formatting.",
            instructions: """
            You are a translation and localization specialist. Translate user content between languages while preserving structure and meaning.

            ## Workflow

            1. **Detect source language** using language detection.
            2. **Ask for target language** if not specified by the user.
            3. **Tokenize** the content into logical segments (paragraphs/sentences).
            4. **Translate** each segment, preserving:
               - Code blocks (``` ... ```) — never translate code.
               - Technical terms, brand names, and proper nouns — keep original or note both.
               - Markdown formatting, links, and structure.
               - Placeholder variables like `{name}` or `%s`.
            5. **Present** the translation with the original for reference.

            ## Output Format

            ```
            🌐 Translation: [Source Language] → [Target Language]
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            [Translated content with preserved formatting]

            📝 Notes
            • Terms kept in original: [list]
            • Localization choices: [any cultural adaptations made]
            ```

            ## Rules
            - Preserve the author's tone and register (formal stays formal, casual stays casual).
            - Never translate code, CLI commands, file paths, or URLs.
            - For ambiguous terms, provide the translation with the original in parentheses on first use.
            - If a passage is already in the target language, skip it and note this.
            - For UI strings, prefer concise translations that fit similar visual space.
            """,
            allowedTools: ["translation", "language-detection", "tokenization"]
        ),

        BaselineSkillDefinition(
            name: "meeting-prep",
            description: "Pulls today's calendar, researches context, and creates a briefing with talking points.",
            instructions: """
            You are a meeting preparation assistant. Help the user prepare for upcoming meetings with context and talking points.

            ## Workflow

            1. **Fetch calendar events** — Get today's (or specified day's) meetings.
            2. **For each meeting**, gather context:
               - Extract attendee names and organizations via entity extraction.
               - If the user provides notes or prior context, analyze sentiment and key themes.
               - Fetch relevant background via web if the user requests it.
            3. **Create a prep briefing** for each meeting.

            ## Output Format

            ```
            📋 Meeting Prep
            ━━━━━━━━━━━━━━

            🗓️ [Meeting Title]
            ⏰ [Time] | 📍 [Location/Link]
            👥 Attendees: [Names]

            🎯 Objective
            • What this meeting is likely about (based on title + context)

            📌 Talking Points
            1. [Point with brief context]
            2. [Point with brief context]
            3. [Point with brief context]

            ❓ Questions to Raise
            • [Relevant question based on context]

            📎 Context
            • [Any relevant background gathered]

            ━━━━━━━━━━━━━━
            [Repeat for next meeting]
            ```

            ## Rules
            - Focus on the next 2-3 meetings unless the user asks for more.
            - If no meetings are found, say so and offer to look at a different day.
            - Keep talking points actionable and specific, not generic.
            - If you have no context beyond the meeting title, generate reasonable questions to ask.
            - Create a reminder 15 minutes before each meeting if the user asks for it.
            """,
            allowedTools: ["calendar", "reminders", "entity-extraction", "web-fetch", "sentiment"]
        ),

        BaselineSkillDefinition(
            name: "research-digest",
            description: "Multi-step web research: fetches sources, extracts entities, cross-references, and summarizes with citations.",
            instructions: """
            You are a research assistant. Conduct thorough research on a topic and produce a well-sourced digest.

            ## Workflow

            1. **Understand the query** — Clarify the research topic. Identify key entities and concepts.
            2. **Fetch sources** — Use web fetch to gather 3-5 relevant pages. Prioritize authoritative sources.
            3. **Extract and analyze** each source:
               - Entity extraction for key people, organizations, dates, and figures.
               - Sentiment analysis to detect bias or framing.
               - Language detection if sources are multilingual.
            4. **Cross-reference** — Identify where sources agree, disagree, or add unique information.
            5. **Synthesize** into a structured digest.

            ## Output Format

            ```
            🔬 Research Digest: [Topic]
            ━━━━━━━━━━━━━━━━━━━━━━━━━

            📋 Summary
            [2-3 paragraph overview of findings]

            🔑 Key Findings
            1. [Finding] — supported by [Source A, Source B]
            2. [Finding] — supported by [Source C]
            3. [Finding] — noted only in [Source D], needs verification

            👥 Key Entities
            • [Person/Org] — Role/relevance to topic

            ⚖️ Perspectives
            • [Viewpoint A] — Sources: [list], Sentiment: [tone]
            • [Viewpoint B] — Sources: [list], Sentiment: [tone]

            ❓ Open Questions
            • [What remains unclear or disputed]

            📚 Sources
            1. [Title] — [URL] — [Brief note on reliability]
            2. [Title] — [URL] — [Brief note on reliability]
            ```

            ## Rules
            - Always cite which source supports each claim.
            - Flag single-source claims as needing verification.
            - Note sentiment bias when detected (e.g., "this source frames X positively").
            - If sources conflict, present both sides rather than picking one.
            - Limit to 5 sources unless the user asks for more depth.
            - Never present a web fetch failure as "no information exists" — note the failure and suggest alternatives.
            """,
            allowedTools: ["web-fetch", "entity-extraction", "sentiment", "language-detection"]
        ),

        BaselineSkillDefinition(
            name: "mac-automator",
            description: "Builds and runs AppleScript and Shortcuts sequences from natural language requests.",
            instructions: """
            You are a macOS automation expert. Convert natural language requests into AppleScript or Shortcuts sequences and execute them.

            ## Workflow

            1. **Understand the request** — What does the user want automated?
            2. **Choose the right tool**:
               - **AppleScript**: For app-specific automation (Finder, Safari, Mail, System Preferences, etc.)
               - **Shortcuts**: For existing user shortcuts or system actions.
               - **Shell**: For file operations, process management, or CLI tools.
               - Combine tools for complex workflows.
            3. **Build the automation** step by step.
            4. **Explain what it will do** before running.
            5. **Execute** and report results.

            ## Safety Rules
            - **Always explain** what the automation will do before executing.
            - **Never** delete files without explicit confirmation.
            - **Never** send messages or emails without showing the content first.
            - **Never** modify system settings without explaining the change.
            - For destructive operations, list exactly what will be affected.

            ## AppleScript Patterns

            Use these common patterns:
            - `tell application "Finder" to ...` for file operations.
            - `tell application "System Events" to ...` for UI automation.
            - `do shell script "..."` for embedding shell commands.
            - `display dialog "..."` for user confirmations.

            ## Output Format

            ```
            ⚙️ Automation: [What it does]
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            📝 Plan
            1. [Step 1 — what it does and why]
            2. [Step 2 — what it does and why]

            🔧 Executing...
            [Results of each step]

            ✅ Done
            • [Summary of what was accomplished]
            ```

            ## Rules
            - Start simple. Don't over-engineer a one-step task.
            - If a Shortcut exists for the task, prefer it over AppleScript.
            - If the task involves multiple apps, chain steps clearly.
            - On failure, explain what went wrong and suggest alternatives.
            - Offer to save complex automations as reusable Shortcuts.
            """,
            allowedTools: ["applescript", "shortcuts", "shell"]
        ),
    ]
    // swiftlint:enable line_length

    /// Uninstall a skill by name.
    public func uninstall(name: String) throws {
        let skillDir = skillsDirectory.appendingPathComponent(sanitizeName(name))
        let fm = FileManager.default
        if fm.fileExists(atPath: skillDir.path) {
            try fm.removeItem(at: skillDir)
        }
    }

    /// List all locally installed skills.sh skills.
    public func listInstalled() throws -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDirectory.path) else { return [] }

        let contents = try fm.contentsOfDirectory(at: skillsDirectory, includingPropertiesForKeys: nil)
        var skills: [Skill] = []

        for dir in contents {
            let metaFile = dir.appendingPathComponent("meta.json")
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: metaFile.path),
                  fm.fileExists(atPath: skillFile.path) else { continue }

            do {
                let metaData = try Data(contentsOf: metaFile)
                let meta = try JSONDecoder().decode(SkillsShMeta.self, from: metaData)
                let content = try String(contentsOf: skillFile, encoding: .utf8)
                let parsed = parseSkillMD(content, name: meta.name)

                let scripts = scanScripts(in: dir)
                let references = scanReferences(in: dir)

                skills.append(Skill(
                    id: "skills-sh-\(parsed.name)",
                    name: parsed.name,
                    description: parsed.description,
                    instructions: parsed.instructions,
                    scripts: scripts,
                    allowedTools: parsed.allowedTools,
                    references: references,
                    source: meta.source,
                    localPath: dir
                ))
            } catch {
                Self.logger.error("Failed to load installed skill at \(dir.path): \(error)")
            }
        }

        return skills
    }

    // MARK: - SKILL.md Parser

    /// Parse a SKILL.md file with YAML frontmatter.
    ///
    /// Format:
    /// ```
    /// ---
    /// name: my-skill
    /// description: What this skill does
    /// metadata:
    ///   key: value
    /// ---
    ///
    /// # Instructions body (markdown)
    /// ```
    private func parseSkillMD(_ raw: String, name fallbackName: String, resolvedPath: String? = nil, resolvedBranch: String? = nil) -> SkillsShContent {
        // Split frontmatter from body
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return SkillsShContent(
                name: fallbackName,
                description: "",
                instructions: raw,
                rawContent: raw,
                allowedTools: nil,
                resolvedPath: resolvedPath,
                resolvedBranch: resolvedBranch
            )
        }

        let afterFirst = trimmed.dropFirst(3)
        guard let endIdx = afterFirst.range(of: "\n---") else {
            return SkillsShContent(
                name: fallbackName,
                description: "",
                instructions: raw,
                rawContent: raw,
                allowedTools: nil,
                resolvedPath: resolvedPath,
                resolvedBranch: resolvedBranch
            )
        }

        let yaml = String(afterFirst[afterFirst.startIndex..<endIdx.lowerBound])
        let body = String(afterFirst[endIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse simple YAML key: value pairs
        var frontmatter: [String: String] = [:]
        for line in yaml.components(separatedBy: .newlines) {
            let trimLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimLine.isEmpty, !trimLine.hasPrefix("#") else { continue }
            // Skip nested keys (indented lines)
            guard !line.hasPrefix(" ") && !line.hasPrefix("\t") else { continue }
            if let colonIdx = trimLine.firstIndex(of: ":") {
                let key = String(trimLine[trimLine.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimLine[trimLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    frontmatter[key] = value
                }
            }
        }

        // Parse allowed-tools (comma-separated)
        let allowedTools: [String]? = frontmatter["allowed-tools"]?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return SkillsShContent(
            name: frontmatter["name"] ?? fallbackName,
            description: frontmatter["description"] ?? "",
            instructions: body,
            rawContent: raw,
            allowedTools: allowedTools,
            resolvedPath: resolvedPath,
            resolvedBranch: resolvedBranch
        )
    }

    // MARK: - File Scanning

    /// Scan a skill directory for executable scripts.
    private func scanScripts(in directory: URL) -> [SkillScript] {
        let fm = FileManager.default
        let scriptExtensions = ["sh", "bash", "py", "js", "mjs"]
        var scripts: [SkillScript] = []

        // Check scripts/ subdirectory first, then top-level
        let searchDirs = [directory.appendingPathComponent("scripts"), directory]
        for dir in searchDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let ext = file.pathExtension.lowercased()
                if scriptExtensions.contains(ext) {
                    scripts.append(SkillScript(
                        name: file.lastPathComponent,
                        language: ScriptLanguage(filename: file.lastPathComponent),
                        localPath: file
                    ))
                }
            }
        }

        return scripts
    }

    /// Scan a skill directory for reference documents.
    private func scanReferences(in directory: URL) -> [SkillReference] {
        let fm = FileManager.default
        let refExtensions = ["md", "txt", "json", "yaml", "yml"]
        let skipFiles: Set<String> = ["SKILL.md", "meta.json"]
        var references: [SkillReference] = []

        // Check references/ subdirectory first, then top-level markdown
        let searchDirs = [directory.appendingPathComponent("references"), directory]
        for dir in searchDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let name = file.lastPathComponent
                let ext = file.pathExtension.lowercased()
                guard refExtensions.contains(ext), !skipFiles.contains(name) else { continue }
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    references.append(SkillReference(name: name, content: content))
                }
            }
        }

        return references
    }

    private func sanitizeName(_ name: String) -> String {
        let lowered = name.lowercased()
        let sanitized = lowered.unicodeScalars.map { char -> Character in
            if CharacterSet.alphanumerics.contains(char) || char == "." || char == "_" {
                return Character(char)
            }
            return "-"
        }
        return String(sanitized)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            .prefix(255)
            .description
    }
}

// MARK: - Data Types

/// A skill entry from the skills.sh search API.
public struct SkillsShEntry: Sendable, Codable, Equatable, Identifiable, Hashable {
    /// Full identifier (e.g. "vercel-labs/agent-skills/skill-name").
    public let id: String
    /// Skill name.
    public let name: String
    /// GitHub source (owner/repo format).
    public let source: String
    /// Install count.
    public let installs: Int

    /// URL-safe slug for skills.sh page.
    public var slug: String { id }

    /// Browsable URL on skills.sh.
    public var webURL: URL? {
        URL(string: "https://skills.sh/\(id)")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Response from the skills.sh search API.
struct SkillsShSearchResponse: Codable {
    let skills: [SkillsShEntry]
}

/// Parsed content of a SKILL.md file.
public struct SkillsShContent: Sendable {
    public let name: String
    public let description: String
    public let instructions: String
    public let rawContent: String
    /// Tool restrictions from `allowed-tools` frontmatter.
    public let allowedTools: [String]?
    /// The resolved GitHub directory path (e.g. "skills/my-skill") for fetching sibling files.
    public let resolvedPath: String?
    /// The resolved branch (e.g. "main" or "master").
    public let resolvedBranch: String?
}

/// A file discovered in a skill's GitHub directory.
public struct SkillsShFile: Sendable, Identifiable, Hashable {
    public let name: String
    public let path: String
    public let size: Int
    public let downloadURL: String?

    public var id: String { path }
}

/// Local metadata for an installed skills.sh skill.
struct SkillsShMeta: Codable {
    let name: String
    let description: String
    let source: String
    let slug: String
    let installedAt: Date
}

/// Errors from the skills.sh client.
public enum SkillsShError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(status: Int)
    case skillNotFound(name: String, source: String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid skills.sh API URL"
        case .invalidResponse:
            return "Invalid response from skills.sh"
        case .httpError(let status):
            return "skills.sh returned HTTP \(status)"
        case .skillNotFound(let name, let source):
            return "Could not find SKILL.md for '\(name)' in \(source)"
        case .parseFailed(let reason):
            return "Failed to parse SKILL.md: \(reason)"
        }
    }
}
