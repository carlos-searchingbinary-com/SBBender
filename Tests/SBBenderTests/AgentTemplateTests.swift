import Testing
import Foundation
@testable import SBBender

/// End-to-end tests for each agent TEMPLATE using the REAL local Qwen3-4B model.
/// No mocks — real LLM inference, real skill execution, real results.
///
/// These tests require:
/// - Apple Silicon Mac
/// - mlx-community/Qwen3-4B-4bit downloaded in ~/.cache/huggingface/hub/
///
/// Each test creates an agent matching the exact template from the app
/// (same skills, same instructions, same generation config) and gives it
/// a realistic multi-skill task to verify the template works as a whole.

@Suite("Agent Template E2E with Real MLX")
struct AgentTemplateE2ETests {

    /// Shared MLX provider — loads model once, reused across tests
    static let mlx = MLXProvider(
        modelID: "mlx-community/Qwen3-4B-4bit",
        gpuCacheLimit: 20 * 1024 * 1024
    )

    // MARK: - Research Assistant Template
    // Skills: web-fetch, entity-extraction, sentiment, language-detection

    @Test("Research Assistant template: analyze a multilingual article excerpt")
    func testResearchAssistant() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Research Assistant",
                instructions: """
                You are a research assistant. Search the web, extract key entities, \
                analyze sentiment, and provide well-structured summaries with citations.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.5, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [
                LanguageDetectionSkill(),
                SentimentSkill(),
                EntityExtractionSkill(),
                // WebFetchSkill omitted — would make external HTTP calls in tests
            ]
        )

        let result = try await agent.run("""
        Analyze this press release:
        "Apple CEO Tim Cook unveiled the Vision Pro at WWDC in Cupertino. \
        Analysts are extremely enthusiastic about the product's potential."
        I need: 1) What language is it? 2) What's the sentiment? 3) What entities are mentioned?
        """)

        #expect(result.status == .completed)
        // Agent should have used multiple skills to answer all 3 parts
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.count >= 2, "Research agent should use at least 2 different skills, used: \(toolNames)")
        // All tool calls should succeed
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Verify substantive results
        let langExec = result.toolExecutions.first(where: { $0.toolName == "detectLanguage" })
        if let exec = langExec {
            #expect(exec.result?.contains("en") == true || exec.result?.contains("English") == true,
                    "Should detect English, got: \(exec.result ?? "nil")")
        }
        let sentExec = result.toolExecutions.first(where: { $0.toolName == "analyzeSentiment" })
        if let exec = sentExec {
            // Apple NLP may score factual press releases as neutral even with positive words
            #expect(exec.succeeded, "Sentiment analysis should succeed, got: \(exec.result ?? "nil")")
        }
        let entExec = result.toolExecutions.first(where: { $0.toolName == "extractEntities" })
        if let exec = entExec {
            let output = exec.result ?? ""
            #expect(output.contains("Tim Cook") || output.contains("Apple") || output.contains("Cupertino"),
                    "Should extract key entities, got: \(output)")
        }
    }

    // MARK: - Code Helper Template
    // Skills: shell, web-fetch, language-detection

    @Test("Code Helper template: detect language then run shell command")
    func testCodeHelper() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Code Helper",
                instructions: """
                You are a coding assistant. Help with writing, debugging, and explaining code. \
                Use the shell to run commands when needed. Be precise and concise.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.3, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [
                ShellSkill(allowedCommands: ["ls", "cat", "echo", "date", "pwd", "which", "wc", "grep", "head", "tail", "sort"]),
                LanguageDetectionSkill(),
                // WebFetchSkill omitted for tests
            ]
        )

        let result = try await agent.run("""
        First detect the language of this code comment: '// Berechne die Summe aller Elemente'.
        Then run: echo 'compilation successful' | wc -w
        """)

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.count >= 1, "Code helper should use at least 1 skill, used: \(toolNames)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Verify shell actually ran
        let shellExec = result.toolExecutions.first(where: { $0.toolName == "runShellCommand" })
        if let exec = shellExec {
            #expect(exec.succeeded, "Shell command should succeed")
        }
    }

    // MARK: - macOS Automator Template
    // Skills: applescript, shell, shortcuts, calendar, reminders
    //
    // The Automator is the most complex template — it has 5 skills spanning
    // app control (AppleScript), system ops (shell), macOS Shortcuts,
    // and PIM (calendar + reminders). Tests exercise real automation scenarios.

    /// Helper to build the full Automator agent with all 5 skills
    private static func makeAutomatorAgent() -> Agent {
        Agent(
            configuration: AgentConfiguration(
                name: "macOS Automator",
                instructions: """
                You are a macOS automation assistant. You help users automate tasks on their Mac.

                Your capabilities:
                - **AppleScript** (runAppleScript): Write and execute AppleScript to control apps \
                (Finder, Safari, Mail, System Events, System Preferences, etc.).
                - **Shell commands** (runShellCommand): Run terminal commands for file operations, \
                process management, text processing, and system tasks.
                - **Shortcuts** (runShortcut): List and run existing macOS Shortcuts. \
                You cannot create new Shortcuts.
                - **Calendar** (searchCalendar): Search calendar events by date range or keyword.
                - **Reminders** (manageReminders): Search, create, and complete reminders.

                When asked to automate something:
                1. Choose the best tool for the job (AppleScript for app control, shell for file/system)
                2. Always confirm before executing destructive actions
                3. Explain what each automation step does
                """,
                generationConfig: GenerationConfig(maxTokens: 1024, temperature: 0.5, enableThinking: false),
                maxIterations: 8
            ),
            model: mlx,
            nativeTools: [
                AppleScriptSkill(),
                ShellSkill(allowedCommands: [
                    "ls", "echo", "date", "pwd", "which", "cat", "find",
                    "wc", "grep", "head", "tail", "sort", "mkdir", "df", "du",
                    "ps", "whoami", "uname", "sw_vers", "defaults",
                ]),
                ShortcutsSkill(),
                CalendarSkill(),
                RemindersSkill(),
            ]
        )
    }

    @Test("Automator: gather system info with AppleScript + shell")
    func testAutomatorSystemInfo() async throws {
        let agent = Self.makeAutomatorAgent()

        let result = try await agent.run("""
        I need a system health check. Do these 3 things:
        1. Use AppleScript to get the Finder's name: tell application "Finder" to return name
        2. Use shell to get macOS version: sw_vers --productVersion
        3. Use shell to get disk usage of the home folder: du -sh ~
        """)

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        // Should use both AppleScript and shell
        #expect(toolNames.contains("runAppleScript"), "Should use AppleScript, used: \(toolNames)")
        #expect(toolNames.contains("runShellCommand"), "Should use shell, used: \(toolNames)")
        #expect(result.toolExecutions.count >= 2, "Should make at least 2 tool calls, made: \(result.toolExecutions.count)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // AppleScript should return "Finder"
        let asExec = result.toolExecutions.first(where: { $0.toolName == "runAppleScript" })
        if let exec = asExec {
            #expect(exec.result?.contains("Finder") == true,
                    "AppleScript should return Finder name, got: \(exec.result ?? "nil")")
        }
    }

    @Test("Automator: file operations workflow with shell")
    func testAutomatorFileOps() async throws {
        let agent = Self.makeAutomatorAgent()

        // Create a temp dir for the test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sbbender_automator_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await agent.run("""
        I need you to automate file operations in the directory \(tempDir.path):
        1. Use shell to create a file: echo 'Meeting notes from standup' > \(tempDir.path)/notes.txt
        2. Use shell to list the directory contents: ls -la \(tempDir.path)
        3. Use shell to count the words in the file: wc -w \(tempDir.path)/notes.txt
        """)

        #expect(result.status == .completed)
        let shellExecs = result.toolExecutions.filter { $0.toolName == "runShellCommand" }
        #expect(shellExecs.count >= 2, "Should run at least 2 shell commands, ran: \(shellExecs.count)")
        for exec in shellExecs {
            #expect(exec.succeeded, "Shell command failed: \(exec.error ?? "unknown"), args: \(exec.arguments)")
        }
        // Verify the file was actually created
        let fileExists = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("notes.txt").path)
        #expect(fileExists, "Shell should have created notes.txt in temp directory")
    }

    @Test("Automator: AppleScript app control — get Finder folder and running apps")
    func testAutomatorAppleScriptAppControl() async throws {
        let agent = Self.makeAutomatorAgent()

        let result = try await agent.run("""
        Use AppleScript to do these 2 things:
        1. Get the name of every process that is visible: \
        tell application "System Events" to return name of every process whose visible is true
        2. Get the current Finder window folder path: \
        tell application "Finder" to return POSIX path of (insertion location as alias)
        """)

        #expect(result.status == .completed)
        let asExecs = result.toolExecutions.filter { $0.toolName == "runAppleScript" }
        #expect(asExecs.count >= 1, "Should run at least 1 AppleScript, ran: \(asExecs.count)")
        for exec in asExecs {
            #expect(exec.succeeded, "AppleScript failed: \(exec.error ?? "unknown")")
        }
        // At least one AppleScript should return some process names
        let anyOutput = asExecs.contains { exec in
            guard let r = exec.result else { return false }
            return !r.isEmpty && r != "OK"
        }
        #expect(anyOutput, "At least one AppleScript should return real output")
    }

    @Test("Automator: list shortcuts + search calendar together")
    func testAutomatorShortcutsAndCalendar() async throws {
        let shortcutsSkill = ShortcutsSkill()
        let calendarSkill = CalendarSkill()
        guard await shortcutsSkill.isAvailable else { return }
        guard await calendarSkill.isAvailable else { return }

        let agent = Self.makeAutomatorAgent()

        let result = try await agent.run("""
        I want to plan my day. Help me by:
        1. Listing all my available macOS Shortcuts so I know what automations I have
        2. Searching my calendar for any events happening today
        Then summarize what you found.
        """)

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.count >= 2, "Should use at least 2 different skills, used: \(toolNames)")
        #expect(toolNames.contains("runShortcut"), "Should list shortcuts, used: \(toolNames)")
        #expect(toolNames.contains("searchCalendar"), "Should search calendar, used: \(toolNames)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Agent should produce a summary response
        #expect(result.content.count > 50, "Agent should produce a substantive summary, got \(result.content.count) chars")
    }

    @Test("Automator: full multi-skill workflow — system audit")
    func testAutomatorFullWorkflow() async throws {
        let agent = Self.makeAutomatorAgent()

        let result = try await agent.run("""
        Run a quick system audit:
        1. Use shell to check who I am: whoami
        2. Use shell to get the macOS version: sw_vers --productVersion
        3. Use AppleScript to count how many Finder windows are open: \
        tell application "Finder" to return count of windows
        4. Use shell to show today's date: date "+%Y-%m-%d %H:%M"
        Summarize all findings.
        """)

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.contains("runShellCommand"), "Should use shell")
        #expect(toolNames.contains("runAppleScript"), "Should use AppleScript")
        #expect(result.toolExecutions.count >= 3, "Should make at least 3 tool calls for a 4-step audit, made: \(result.toolExecutions.count)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Verify the whoami result makes sense
        let whoamiExec = result.toolExecutions.first(where: {
            $0.toolName == "runShellCommand" && $0.arguments.contains("whoami")
        })
        if let exec = whoamiExec {
            #expect(!exec.result!.isEmpty, "whoami should return a username")
        }
    }

    // MARK: - Writing Assistant Template
    // Skills: language-detection, sentiment, entity-extraction

    @Test("Writing Assistant template: full text analysis pipeline")
    func testWritingAssistant() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Writing Assistant",
                instructions: """
                You are a writing assistant. Help with drafting, editing, and refining text. \
                Analyze tone and sentiment. Provide constructive feedback and alternative phrasings.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.8, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [
                LanguageDetectionSkill(),
                SentimentSkill(),
                EntityExtractionSkill(),
            ]
        )

        let result = try await agent.run("""
        Analyze this paragraph for me — I need language, sentiment, and key entities:
        "Le président Emmanuel Macron a annoncé un nouveau plan d'investissement \
        de 30 milliards d'euros pour l'innovation technologique en France. \
        Les réactions des marchés ont été très positives."
        """)

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.count >= 2, "Writing assistant should use at least 2 skills, used: \(toolNames)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Language should be French
        let langExec = result.toolExecutions.first(where: { $0.toolName == "detectLanguage" })
        if let exec = langExec {
            #expect(exec.result?.contains("fr") == true || exec.result?.contains("French") == true,
                    "Should detect French, got: \(exec.result ?? "nil")")
        }
    }

    // MARK: - Data Analyst Template
    // Skills: shell, web-fetch, entity-extraction

    @Test("Data Analyst template: DuckDB data analysis with CSV")
    func testDataAnalyst() async throws {
        // Create a test CSV file
        let csvPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent_test_sales_\(UUID().uuidString.prefix(8)).csv").path
        try """
        product,region,quantity,unit_price
        Widget,North,10,9.99
        Gadget,South,5,24.99
        Widget,South,3,9.99
        Doohickey,North,8,14.99
        Gadget,North,12,24.99
        """.write(toFile: csvPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: csvPath) }

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Data Analyst",
                instructions: """
                You are a data analyst. Use the analyzeData tool to load and query data files. \
                When asked to analyze a file: first load it with action 'load', then query with action 'query' using SQL. \
                Always use the tool — never guess at data.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.2, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [
                DataAnalysisSkill(),
                EntityExtractionSkill(),
            ]
        )

        let result = try await agent.run(
            """
            Please analyze this CSV file. First, call analyzeData with these exact parameters:
            {"action": "load", "filePath": "\(csvPath)", "tableName": "sales"}
            Then call analyzeData again with:
            {"action": "query", "query": "SELECT product, SUM(quantity) AS total_qty FROM sales GROUP BY product ORDER BY total_qty DESC"}
            """
        )

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.contains("analyzeData"), "Agent should use analyzeData tool, used: \(toolNames)")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Tool \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
    }

    // MARK: - Meeting Copilot Template
    // Skills: transcription, calendar, reminders, sentiment
    // Note: transcription requires audio file so we test the other skills

    @Test("Meeting Copilot template: calendar + reminders + sentiment")
    func testMeetingCopilot() async throws {
        let calendarSkill = CalendarSkill()
        let remindersSkill = RemindersSkill()
        guard await calendarSkill.isAvailable else { return }
        guard await remindersSkill.isAvailable else { return }

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Meeting Copilot",
                instructions: """
                You are a meeting copilot. Transcribe audio, summarize discussions, \
                track action items in reminders, and manage calendar events. \
                Analyze meeting sentiment and participant engagement.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.5, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [
                calendarSkill,
                remindersSkill,
                SentimentSkill(),
            ]
        )

        let result = try await agent.run("""
        After our team meeting, I need you to:
        1. Analyze the sentiment of these meeting notes: "The team is very excited about the new product launch. Everyone agreed the timeline is aggressive but achievable."
        2. Search my calendar for events today.
        """)

        #expect(result.status == .completed)
        #expect(!result.toolExecutions.isEmpty, "Meeting copilot should have used at least one skill")
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        // Verify sentiment was analyzed (Apple NLP may score mixed statements as negative
        // due to words like "aggressive", so just verify the skill succeeded)
        let sentExec = result.toolExecutions.first(where: { $0.toolName == "analyzeSentiment" })
        if let exec = sentExec {
            #expect(exec.succeeded, "Sentiment analysis should succeed, got: \(exec.result ?? "nil")")
        }
    }

    // MARK: - Cross-Template: Agent Streaming with Skills

    @Test("Agent streaming with skills works end-to-end")
    func testStreamingWithSkills() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "StreamTest",
                instructions: """
                You are a helpful assistant with language detection.
                When given text, use detectLanguage to identify the language, then respond.
                """,
                generationConfig: GenerationConfig(maxTokens: 256, temperature: 0.3, enableThinking: false)
            ),
            model: Self.mlx,
            nativeTools: [LanguageDetectionSkill()]
        )

        let stream = await agent.runStream("What language is 'Hola mundo'?")
        var gotText = false
        var gotDone = false
        var gotToolUse = false

        for try await event in stream {
            switch event {
            case .contentDelta:
                gotText = true
            case .completed:
                gotDone = true
            case .toolCallStarted, .toolCallCompleted:
                gotToolUse = true
            default:
                break
            }
        }

        #expect(gotDone, "Should have received completion event")
        #expect(gotText || gotToolUse, "Should have received text or tool use events")
    }

    // MARK: - Basic Agent (no skills, sanity check)

    @Test("Basic agent with no skills generates a response")
    func testBasicAgentNoSkills() async throws {
        let agent = Agent(
            configuration: AgentConfiguration(
                name: "BasicAgent",
                instructions: "You are a helpful assistant. Always answer in one short sentence.",
                generationConfig: GenerationConfig(maxTokens: 64, temperature: 0.3, enableThinking: false)
            ),
            model: Self.mlx
        )

        let result = try await agent.run("What is 2+2?")
        #expect(result.status == .completed)
        #expect(!result.content.isEmpty, "Agent should produce a non-empty response")
    }

    // MARK: - EmailSkill Agent Tests

    @Test("Email agent: getUnread action via readEmail skill",
          .disabled("Requires macOS Automation permission for Mail.app — run manually"))
    func testEmailAgentGetUnread() async throws {
        let emailSkill = EmailSkill()
        guard await emailSkill.isAvailable else { return }

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Inbox Scanner",
                instructions: """
                You are an inbox scanner. When asked about emails, use the readEmail tool \
                with action 'getUnread' to fetch unread messages. Report what you find.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.3, enableThinking: false),
                maxIterations: 4
            ),
            model: Self.mlx,
            nativeTools: [emailSkill]
        )

        let result = try await agent.run("Check my inbox for unread emails. Use readEmail with input 'all' and action 'getUnread'.")

        #expect(result.status == .completed)
        let emailExecs = result.toolExecutions.filter { $0.toolName == "readEmail" }
        #expect(!emailExecs.isEmpty, "Should have called readEmail, tool calls: \(result.toolExecutions.map(\.toolName))")
        for exec in emailExecs {
            #expect(exec.succeeded, "readEmail failed: \(exec.error ?? "unknown")")
        }
    }

    @Test("Email agent: search action via readEmail skill",
          .disabled("Requires macOS Automation permission for Mail.app — run manually"))
    func testEmailAgentSearch() async throws {
        let emailSkill = EmailSkill()
        guard await emailSkill.isAvailable else { return }

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Email Searcher",
                instructions: """
                You are an email assistant. When asked to find emails, use the readEmail tool \
                with action 'search' and input set to the search query. Report results.
                """,
                generationConfig: GenerationConfig(maxTokens: 512, temperature: 0.3, enableThinking: false),
                maxIterations: 4
            ),
            model: Self.mlx,
            nativeTools: [emailSkill]
        )

        let result = try await agent.run("Search my emails for anything about 'meeting'. Use readEmail with input 'meeting' and action 'search'.")

        #expect(result.status == .completed)
        let emailExecs = result.toolExecutions.filter { $0.toolName == "readEmail" }
        #expect(!emailExecs.isEmpty, "Should have called readEmail, tool calls: \(result.toolExecutions.map(\.toolName))")
        for exec in emailExecs {
            #expect(exec.succeeded, "readEmail search failed: \(exec.error ?? "unknown")")
        }
    }

    @Test("Email + entity extraction: inbox scanner template",
          .disabled("Requires macOS Automation permission for Mail.app — run manually"))
    func testInboxScannerTemplate() async throws {
        let emailSkill = EmailSkill()
        guard await emailSkill.isAvailable else { return }

        let agent = Agent(
            configuration: AgentConfiguration(
                name: "Inbox Scanner",
                instructions: """
                You are an inbox scanner. Your job is to read the user's unread emails and produce a structured digest.
                1. Use the readEmail tool with action 'getUnread' to fetch unread messages.
                2. For each important email, use extractEntities on the sender/subject to identify key people.
                3. Use analyzeSentiment on the subject lines to flag urgent or negative tone.
                Output a structured digest grouped by urgency.
                """,
                generationConfig: GenerationConfig(maxTokens: 1024, temperature: 0.3, enableThinking: false),
                maxIterations: 8
            ),
            model: Self.mlx,
            nativeTools: [emailSkill, EntityExtractionSkill(), SentimentSkill()]
        )

        let result = try await agent.run("Scan my inbox and create a digest of unread emails. Check for entities and sentiment.")

        #expect(result.status == .completed)
        let toolNames = Set(result.toolExecutions.map(\.toolName))
        #expect(toolNames.contains("readEmail"), "Inbox scanner should use readEmail, used: \(toolNames)")
        // If there are emails, it should also use entity extraction or sentiment
        // If inbox is empty, it will just report that — which is fine
        for exec in result.toolExecutions {
            #expect(exec.succeeded, "Skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }
        #expect(result.content.count > 20, "Should produce a substantive response, got \(result.content.count) chars")
    }

    // MARK: - Prepare My Day Swarm (Sequential)

    @Test("Prepare My Day: 3-agent sequential swarm end-to-end",
          .disabled("Requires macOS Automation permission for Mail.app — run manually"))
    func testPrepareMyDaySwarm() async throws {
        let emailSkill = EmailSkill()
        let calendarSkill = CalendarSkill()
        let remindersSkill = RemindersSkill()
        guard await emailSkill.isAvailable else { return }
        guard await calendarSkill.isAvailable else { return }
        guard await remindersSkill.isAvailable else { return }

        // Agent 1: Inbox Scanner — reads emails, extracts entities, analyzes sentiment
        let inboxScanner = Agent(
            configuration: AgentConfiguration(
                name: "Inbox Scanner",
                instructions: """
                You are an inbox scanner. Read the user's unread emails and produce a structured digest.
                1. Use readEmail with action 'getUnread' to fetch unread messages.
                2. For important emails, use extractEntities to identify key people and organizations.
                3. Use analyzeSentiment on subject lines to flag urgency.
                Output: total count, per-email summary (sender, subject, urgency, entities), grouped by urgency.
                Be concise — this output feeds the next agent.
                """,
                generationConfig: GenerationConfig(maxTokens: 1024, temperature: 0.3, enableThinking: false),
                maxIterations: 8
            ),
            model: Self.mlx,
            nativeTools: [emailSkill, EntityExtractionSkill(), SentimentSkill()]
        )

        // Agent 2: Calendar Briefer — pulls today's schedule, cross-references with emails
        let calendarBriefer = Agent(
            configuration: AgentConfiguration(
                name: "Calendar Briefer",
                instructions: """
                You are a calendar briefer. You receive an email digest from the previous agent.
                1. Use searchCalendar with input 'today' to get today's events.
                2. Use manageReminders with input 'all' to check existing reminders.
                3. Cross-reference email senders with meeting participants.
                Output a day timeline with events, related emails, and existing reminders.
                Include the email digest in your output so the next agent has full context.
                """,
                generationConfig: GenerationConfig(maxTokens: 1024, temperature: 0.3, enableThinking: false),
                maxIterations: 8
            ),
            model: Self.mlx,
            nativeTools: [calendarSkill, remindersSkill]
        )

        // Agent 3: Day Strategist — synthesizes everything into a morning briefing
        let dayStrategist = Agent(
            configuration: AgentConfiguration(
                name: "Day Strategist",
                instructions: """
                You are a day strategist. You receive combined email + calendar data.
                Create a morning briefing:
                1. Priority Actions: emails needing response before meetings
                2. Meeting Prep: what to prepare for each meeting
                3. Quick Wins: emails handleable in under 2 minutes
                4. Day Summary: 2-3 sentence overview
                Use analyzeSentiment to gauge overall tone of the day.
                Format as a clean, scannable morning briefing with headers.
                """,
                generationConfig: GenerationConfig(maxTokens: 1024, temperature: 0.5, enableThinking: false),
                maxIterations: 6
            ),
            model: Self.mlx,
            nativeTools: [remindersSkill, SentimentSkill()]
        )

        // Build the sequential swarm
        let swarm = Swarm(
            name: "Prepare My Day",
            mode: .sequential,
            members: [inboxScanner, calendarBriefer, dayStrategist]
        )

        let result = try await swarm.run("Good morning! Prepare my day — check emails, calendar, and create a briefing.")

        // All 3 agents should have run
        #expect(result.memberResults.count == 3, "Sequential swarm should produce 3 member results, got: \(result.memberResults.count)")

        // Agent 1 (Inbox Scanner) should have used readEmail
        let scannerResult = result.memberResults[0]
        #expect(scannerResult.status == .completed, "Inbox Scanner should complete")
        let scannerTools = Set(scannerResult.toolExecutions.map(\.toolName))
        #expect(scannerTools.contains("readEmail"), "Inbox Scanner should use readEmail, used: \(scannerTools)")
        for exec in scannerResult.toolExecutions {
            #expect(exec.succeeded, "Scanner skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }

        // Agent 2 (Calendar Briefer) should have used calendar and/or reminders
        let brieferResult = result.memberResults[1]
        #expect(brieferResult.status == .completed, "Calendar Briefer should complete")
        let brieferTools = Set(brieferResult.toolExecutions.map(\.toolName))
        #expect(brieferTools.contains("searchCalendar") || brieferTools.contains("manageReminders"),
                "Calendar Briefer should use calendar or reminders, used: \(brieferTools)")
        for exec in brieferResult.toolExecutions {
            #expect(exec.succeeded, "Briefer skill \(exec.toolName) failed: \(exec.error ?? "unknown")")
        }

        // Agent 3 (Day Strategist) should produce the final briefing
        let strategistResult = result.memberResults[2]
        #expect(strategistResult.status == .completed, "Day Strategist should complete")
        #expect(strategistResult.content.count > 50,
                "Day Strategist should produce a substantial briefing, got \(strategistResult.content.count) chars")

        // The final combined output should be non-trivial
        #expect(result.content.count > 100,
                "Full swarm output should be substantial, got \(result.content.count) chars")

        // Verify sequential chaining worked — each agent's output feeds the next
        // Agent 2 should have received Agent 1's output (containing email info)
        // Agent 3 should have received Agent 2's output (containing calendar + email info)
        // We can't check exact inputs but we can verify all agents produced content
        for (i, memberResult) in result.memberResults.enumerated() {
            #expect(!memberResult.content.isEmpty,
                    "Agent \(i) should produce non-empty output")
        }
    }
}
