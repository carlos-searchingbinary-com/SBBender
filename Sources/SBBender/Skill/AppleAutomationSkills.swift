import Foundation

// MARK: - AppleScript Skill

/// Executes AppleScript code for macOS automation.
///
/// Enables agents to control any scriptable macOS application — Finder,
/// Mail, Safari, Music, System Events, etc.
///
/// Latency: Varies by script complexity.
public struct AppleScriptSkill: NativeTool {
    public let id = "applescript"
    public let name = "runAppleScript"
    public let description = "Execute AppleScript code to automate macOS applications (Finder, Mail, Safari, etc.)"

    public var isAvailable: Bool {
        get async {
            #if os(macOS)
            return true
            #else
            return false
            #endif
        }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The AppleScript code to execute"),
            ],
            required: ["input"]
        )
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let script = input.text, !script.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No AppleScript provided")
        }

        #if os(macOS)
        let start = CFAbsoluteTimeGetCurrent()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                let result = appleScript?.executeAndReturnError(&error)

                let latency = CFAbsoluteTimeGetCurrent() - start

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(throwing: SBBenderError.skillExecutionFailed(
                        skill: "runAppleScript", reason: errorMessage
                    ))
                } else {
                    let output = result?.stringValue ?? "OK"
                    continuation.resume(returning: NativeToolResult(
                        output: output,
                        structuredData: ["status": "success"],
                        confidence: 1.0,
                        latency: latency
                    ))
                }
            }
        }
        #else
        throw SBBenderError.skillNotAvailable("AppleScript is only available on macOS")
        #endif
    }
}

// MARK: - Shell Command Skill

/// Executes shell commands for system automation.
///
/// Use with caution — this gives the agent the ability to run arbitrary commands.
/// Configure `allowedCommands` to restrict what can be executed.
public struct ShellSkill: NativeTool {
    public let id = "shell"
    public let name = "runShellCommand"
    public let description = "Execute a shell command and return its output"

    public let allowedCommands: [String]?

    public var isAvailable: Bool {
        get async { true }
    }

    /// Create a ShellSkill.
    ///
    /// - Parameter allowedCommands: If set, only these command prefixes are allowed.
    ///   For example: `["ls", "cat", "echo"]`. If nil, all commands are allowed.
    public init(allowedCommands: [String]? = nil) {
        self.allowedCommands = allowedCommands
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The shell command to execute"),
            ],
            required: ["input"]
        )
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let command = input.text, !command.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No command provided")
        }

        // Check if command is allowed
        if let allowed = allowedCommands {
            let cmdBase = command.split(separator: " ").first.map(String.init) ?? command
            guard allowed.contains(where: { command.hasPrefix($0) }) else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Command '\(cmdBase)' is not in the allowed list: \(allowed.joined(separator: ", "))"
                )
            }
        }

        let start = CFAbsoluteTimeGetCurrent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        let exitCode = process.terminationStatus
        let latency = CFAbsoluteTimeGetCurrent() - start

        if exitCode != 0 {
            return NativeToolResult(
                output: "Exit code \(exitCode): \(errorOutput.isEmpty ? output : errorOutput)",
                structuredData: [
                    "exitCode": String(exitCode),
                    "stderr": errorOutput,
                    "stdout": output,
                ],
                confidence: 1.0,
                latency: latency
            )
        }

        return NativeToolResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredData: [
                "exitCode": "0",
                "stdout": output,
            ],
            confidence: 1.0,
            latency: latency
        )
    }
}

// MARK: - Calendar Skill (EventKit)

#if canImport(EventKit)
import EventKit

/// Access and manage calendar events using EventKit.
///
/// Latency: <10ms for local calendars.
///
/// Permission: Requests full calendar access on first use if not already granted.
/// The macOS permission dialog will appear once; subsequent calls use the cached grant.
public struct CalendarSkill: @unchecked Sendable, NativeTool {
    public let id = "calendar"
    public let name = "searchCalendar"
    public let description = "Search calendar events by date range or keyword. Use input 'all' or 'today' to list all events."

    private let store = EKEventStore()

    public var isAvailable: Bool {
        get async {
            let status = EKEventStore.authorizationStatus(for: .event)
            return status == .fullAccess || status == .authorized || status == .notDetermined
        }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Search query (e.g. 'meeting', 'standup'), or 'all'/'today' to list all events"),
                "days": .string("Number of days to search forward from today. Defaults to '1' for today. Use '7' for the week."),
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
            struct Args: Decodable { let input: String; let days: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            var params: [String: String] = [:]
            if let days = args.days { params["days"] = days }
            let result = try await skill.execute(input: NativeToolInput(text: args.input, parameters: params))
            return result.output
        }
    }

    /// Request calendar access if not yet determined.
    private func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars."
                )
            }
        default:
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars."
            )
        }
    }

    /// Words that signal "show everything" rather than filter by keyword.
    private static let showAllKeywords: Set<String> = [
        "all", "today", "everything", "any", "schedule", "agenda",
        "activities", "events", "calendar", "what", "show", "list",
    ]

    /// Check if the query is asking for "all events" vs a specific keyword filter.
    private func isShowAllQuery(_ query: String) -> Bool {
        let words = Set(query.lowercased().split(separator: " ").map(String.init))
        // If every word in the query is a generic/show-all word, don't filter
        return words.allSatisfy { Self.showAllKeywords.contains($0) }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let query = input.text else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No query provided")
        }

        try await ensureAccess()

        let start = CFAbsoluteTimeGetCurrent()
        let daysForward = Int(input.parameters["days"] ?? "1") ?? 1

        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: daysForward, to: startDate)!

        let predicate = store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        let events = store.events(matching: predicate)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let filtered: [EKEvent]
        if isShowAllQuery(query) {
            filtered = events
        } else {
            // Filter by keyword match against title, location, or notes
            filtered = events.filter { event in
                event.title?.localizedCaseInsensitiveContains(query) == true ||
                event.location?.localizedCaseInsensitiveContains(query) == true ||
                event.notes?.localizedCaseInsensitiveContains(query) == true
            }
        }

        let eventLines = filtered.map { event in
            let time = formatter.string(from: event.startDate)
            let title = event.title ?? "Untitled"
            let location = event.location.map { " @ \($0)" } ?? ""
            return "- \(time): \(title)\(location)"
        }

        let dayLabel = daysForward == 1 ? "today" : "the next \(daysForward) days"
        let output = eventLines.isEmpty
            ? "No events found for \(dayLabel)."
            : "Events for \(dayLabel) (\(filtered.count)):\n" + eventLines.joined(separator: "\n")

        return NativeToolResult(
            output: output,
            structuredData: ["count": String(filtered.count), "days": String(daysForward)],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

/// Create and manage reminders using EventKit.
///
/// Latency: <10ms.
///
/// Permission: Requests full reminders access on first use if not already granted.
public struct RemindersSkill: @unchecked Sendable, NativeTool {
    public let id = "reminders"
    public let name = "manageReminders"
    public let description = "Search, create, and complete reminders. Use input 'all' to list all incomplete reminders."

    private let store = EKEventStore()

    public var isAvailable: Bool {
        get async {
            let status = EKEventStore.authorizationStatus(for: .reminder)
            return status == .fullAccess || status == .authorized || status == .notDetermined
        }
    }

    public init() {}

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The reminder title to search for, 'all' to list everything, or new reminder text to create"),
                "action": .string("Action to perform: 'search', 'create', or 'complete'. Defaults to 'search'."),
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
            struct Args: Decodable { let input: String; let action: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: NativeToolInput(
                text: args.input,
                parameters: ["action": args.action ?? "search"]
            ))
            return result.output
        }
    }

    /// Request reminders access if not yet determined.
    private func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .authorized:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToReminders()
            guard granted else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders."
                )
            }
        default:
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders."
            )
        }
    }

    /// Words that signal "show everything" rather than filter by keyword.
    private static let showAllKeywords: Set<String> = [
        "all", "everything", "any", "reminders", "tasks", "todos",
        "what", "show", "list", "my",
    ]

    /// Check if the query is asking for "all reminders" vs a specific keyword filter.
    private func isShowAllQuery(_ text: String) -> Bool {
        let words = Set(text.lowercased().split(separator: " ").map(String.init))
        return words.allSatisfy { Self.showAllKeywords.contains($0) }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No input provided")
        }

        try await ensureAccess()

        let start = CFAbsoluteTimeGetCurrent()
        let action = input.parameters["action"] ?? "search"

        switch action {
        case "create":
            let reminder = EKReminder(eventStore: store)
            reminder.title = text
            reminder.calendar = store.defaultCalendarForNewReminders()
            try store.save(reminder, commit: true)
            return NativeToolResult(
                output: "Created reminder: \(text)",
                structuredData: ["action": "create", "title": text],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        case "complete":
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            // EKReminder is not Sendable, but we need the actual objects to mutate them.
            // Safety: the continuation resumes once, and reminders are accessed serially
            // after await — no concurrent access occurs.
            let reminders: [EKReminder] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[EKReminder], Error>) in
                store.fetchReminders(matching: predicate) { result in
                    nonisolated(unsafe) let safeResult = result ?? []
                    continuation.resume(returning: safeResult)
                }
            }

            let matching = reminders.filter {
                $0.title?.localizedCaseInsensitiveContains(text) == true
            }

            for reminder in matching {
                reminder.isCompleted = true
                try store.save(reminder, commit: true)
            }

            return NativeToolResult(
                output: "Completed \(matching.count) reminder(s) matching '\(text)'",
                structuredData: ["action": "complete", "count": String(matching.count)],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )

        default: // search
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            // Extract only Sendable data (titles) inside the callback to avoid
            // passing non-Sendable EKReminder across concurrency boundaries.
            let titles: [String] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
                store.fetchReminders(matching: predicate) { result in
                    let extracted = (result ?? []).map { $0.title ?? "Untitled" }
                    continuation.resume(returning: extracted)
                }
            }

            let matching: [String]
            if isShowAllQuery(text) {
                matching = titles
            } else {
                matching = titles.filter {
                    $0.localizedCaseInsensitiveContains(text)
                }
            }

            let lines = matching.map { "- \($0)" }
            let output: String
            if lines.isEmpty {
                output = isShowAllQuery(text)
                    ? "No incomplete reminders found."
                    : "No reminders found matching '\(text)'"
            } else {
                output = "Reminders (\(matching.count)):\n" + lines.joined(separator: "\n")
            }

            return NativeToolResult(
                output: output,
                structuredData: ["action": "search", "count": String(matching.count)],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )
        }
    }
}
#endif
