import Foundation

#if os(macOS)

/// Reads, searches, and sends emails via Mail.app using AppleScript.
///
/// Actions:
/// - `getUnread` — List unread messages from inbox (default, max 20)
/// - `search` — Search messages by keyword in subject/sender
/// - `flag` — Flag a message by subject line match
/// - `getDetail` — Get full body of a message by subject line match
/// - `send` — Compose and send an email (input = body, requires `to` and `subject` params)
///
/// Latency: 100ms–2s depending on mailbox size.
public struct EmailSkill: NativeTool {
    public let id = "email"
    public let name = "readEmail"
    public let description = "Read, search, and send emails via Mail.app. Actions: getUnread, search, flag, getDetail, send."

    public init() {}

    public var isAvailable: Bool {
        get async {
            // Mail.app exists on all macOS installs
            FileManager.default.fileExists(atPath: "/System/Applications/Mail.app")
        }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Search query, subject to match, or email body (for send action). Use 'all' with getUnread to list all unread."),
                "action": .string("Action: 'getUnread' (default), 'search', 'flag', 'getDetail', or 'send'."),
                "limit": .string("Max number of messages to return. Defaults to '10'."),
                "to": .string("Recipient email address (required for 'send' action)."),
                "subject": .string("Email subject line (required for 'send' action)."),
            ],
            required: ["input"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters,
            requiresConfirmation: true
        ) { arguments, _ in
            struct Args: Decodable {
                let input: String
                let action: String?
                let limit: String?
                let to: String?
                let subject: String?
            }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            var params: [String: String] = [
                "action": args.action ?? "getUnread",
                "limit": args.limit ?? "10",
            ]
            if let to = args.to { params["to"] = to }
            if let subject = args.subject { params["subject"] = subject }
            let result = try await skill.execute(input: NativeToolInput(
                text: args.input,
                parameters: params
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let text = input.text, !text.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No input provided")
        }

        let action = input.parameters["action"] ?? "getUnread"
        let limit = Int(input.parameters["limit"] ?? "10") ?? 10

        switch action {
        case "getUnread":
            return try await getUnread(limit: limit)
        case "search":
            return try await searchMessages(query: text, limit: limit)
        case "flag":
            return try await flagMessage(subject: text)
        case "getDetail":
            return try await getDetail(subject: text)
        case "send":
            let to = input.parameters["to"] ?? ""
            let subject = input.parameters["subject"] ?? ""
            return try await sendEmail(to: to, subject: subject, body: text)
        default:
            return try await getUnread(limit: limit)
        }
    }

    // MARK: - Actions

    private func getUnread(limit: Int) async throws -> NativeToolResult {
        let script = """
        tell application "Mail"
            set output to ""
            set msgs to (every message of inbox whose read status is false)
            set msgCount to count of msgs
            if msgCount > \(limit) then set msgCount to \(limit)
            repeat with i from 1 to msgCount
                set msg to item i of msgs
                set msgSender to sender of msg
                set msgSubject to subject of msg
                set msgDate to date received of msg as string
                set output to output & "From: " & msgSender & linefeed & "Subject: " & msgSubject & linefeed & "Date: " & msgDate & linefeed & "---" & linefeed
            end repeat
            if output is "" then
                return "No unread messages in inbox."
            end if
            return output
        end tell
        """
        return try await runAppleScript(script, actionName: "getUnread")
    }

    private func searchMessages(query: String, limit: Int) async throws -> NativeToolResult {
        // Escape the query for AppleScript string
        let escaped = query.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            set output to ""
            set searchQuery to "\(escaped)"
            set msgs to (every message of inbox whose subject contains searchQuery) & \
                         (every message of inbox whose sender contains searchQuery)
            -- Deduplicate by only processing unique message IDs
            set seen to {}
            set msgCount to 0
            repeat with msg in msgs
                if msgCount ≥ \(limit) then exit repeat
                set msgID to id of msg
                if msgID is not in seen then
                    set end of seen to msgID
                    set msgSender to sender of msg
                    set msgSubject to subject of msg
                    set msgDate to date received of msg as string
                    set msgRead to read status of msg
                    set readLabel to "unread"
                    if msgRead then set readLabel to "read"
                    set output to output & "From: " & msgSender & linefeed & "Subject: " & msgSubject & linefeed & "Date: " & msgDate & " [" & readLabel & "]" & linefeed & "---" & linefeed
                    set msgCount to msgCount + 1
                end if
            end repeat
            if output is "" then
                return "No messages found matching '" & searchQuery & "'."
            end if
            return output
        end tell
        """
        return try await runAppleScript(script, actionName: "search")
    }

    private func flagMessage(subject: String) async throws -> NativeToolResult {
        let escaped = subject.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            set msgs to (every message of inbox whose subject contains "\(escaped)")
            set flagged to 0
            repeat with msg in msgs
                set flagged status of msg to true
                set flagged to flagged + 1
            end repeat
            return "Flagged " & flagged & " message(s) matching '\(escaped)'."
        end tell
        """
        return try await runAppleScript(script, actionName: "flag")
    }

    private func getDetail(subject: String) async throws -> NativeToolResult {
        let escaped = subject.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            set msgs to (every message of inbox whose subject contains "\(escaped)")
            if (count of msgs) is 0 then
                return "No message found with subject containing '\(escaped)'."
            end if
            set msg to item 1 of msgs
            set msgSender to sender of msg
            set msgSubject to subject of msg
            set msgDate to date received of msg as string
            set msgContent to content of msg
            -- Truncate very long emails
            if (count of msgContent) > 2000 then
                set msgContent to (text 1 thru 2000 of msgContent) & "... [truncated]"
            end if
            return "From: " & msgSender & linefeed & "Subject: " & msgSubject & linefeed & "Date: " & msgDate & linefeed & linefeed & msgContent
        end tell
        """
        return try await runAppleScript(script, actionName: "getDetail")
    }

    private func sendEmail(to recipient: String, subject: String, body: String) async throws -> NativeToolResult {
        guard !recipient.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No recipient ('to') provided for send action.")
        }
        guard !subject.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No subject provided for send action.")
        }
        let escapedTo = recipient.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedSubject = subject.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\" & linefeed & \"")
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(escapedSubject)", content:"\(escapedBody)", visible:true}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(escapedTo)"}
            end tell
            send newMessage
            return "Email sent to \(escapedTo) with subject '\(escapedSubject)'."
        end tell
        """
        return try await runAppleScript(script, actionName: "send")
    }

    // MARK: - AppleScript Runner

    private func runAppleScript(_ source: String, actionName: String) async throws -> NativeToolResult {
        let start = CFAbsoluteTimeGetCurrent()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: source)
                let result = appleScript?.executeAndReturnError(&error)

                let latency = CFAbsoluteTimeGetCurrent() - start

                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    // If Mail.app isn't running or no permission, give a helpful message
                    if errorMessage.contains("not allowed") || errorMessage.contains("assistive") {
                        continuation.resume(throwing: SBBenderError.skillExecutionFailed(
                            skill: "readEmail",
                            reason: "Mail.app access denied. Grant access in System Settings > Privacy & Security > Automation."
                        ))
                    } else {
                        continuation.resume(throwing: SBBenderError.skillExecutionFailed(
                            skill: "readEmail", reason: errorMessage
                        ))
                    }
                } else {
                    let output = result?.stringValue ?? "OK"
                    continuation.resume(returning: NativeToolResult(
                        output: output,
                        structuredData: ["action": actionName],
                        confidence: 1.0,
                        latency: latency
                    ))
                }
            }
        }
    }
}

#endif
