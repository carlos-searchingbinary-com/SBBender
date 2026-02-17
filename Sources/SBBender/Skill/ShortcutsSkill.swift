import Foundation

/// Runs macOS Shortcuts via the `shortcuts` CLI.
///
/// Can list available shortcuts, run a specific shortcut by name,
/// and optionally pipe input text into it.
///
/// Latency: Varies by shortcut complexity.
public struct ShortcutsSkill: NativeTool {
    public let id = "shortcuts"
    public let name = "runShortcut"
    public let description = "Run a macOS Shortcut by name, or list available shortcuts"

    public init() {}

    public var isAvailable: Bool {
        get async {
            FileManager.default.fileExists(atPath: "/usr/bin/shortcuts")
        }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Name of the shortcut to run, or 'list' to list all available shortcuts"),
                "stdin": .string("Optional text input to pipe into the shortcut"),
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
            struct Args: Decodable { let input: String; let stdin: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: NativeToolInput(
                text: args.input,
                parameters: args.stdin.map { ["stdin": $0] } ?? [:]
            ))
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let name = input.text, !name.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: self.name, reason: "No shortcut name provided")
        }

        let start = CFAbsoluteTimeGetCurrent()

        if name.lowercased() == "list" {
            return try await listShortcuts(start: start)
        }

        return try await runShortcut(name: name, stdin: input.parameters["stdin"], start: start)
    }

    private func listShortcuts(start: CFAbsoluteTime) async throws -> NativeToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let stdout = Pipe()
        process.standardOutput = stdout

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let shortcuts = output.split(separator: "\n").map(String.init)

        return NativeToolResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredData: ["count": String(shortcuts.count), "action": "list"],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }

    private func runShortcut(name: String, stdin: String?, start: CFAbsoluteTime) async throws -> NativeToolResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdinText = stdin {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(Data(stdinText.utf8))
            stdinPipe.fileHandleForWriting.closeFile()
        }

        try process.run()
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        let exitCode = process.terminationStatus

        if exitCode != 0 {
            return NativeToolResult(
                output: "Shortcut '\(name)' failed (exit \(exitCode)): \(errorOutput.isEmpty ? output : errorOutput)",
                structuredData: ["exitCode": String(exitCode), "action": "run", "shortcut": name],
                confidence: 1.0,
                latency: CFAbsoluteTimeGetCurrent() - start
            )
        }

        return NativeToolResult(
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredData: ["exitCode": "0", "action": "run", "shortcut": name],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}
