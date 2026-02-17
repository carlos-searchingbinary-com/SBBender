import Foundation
import os
import Synchronization

#if canImport(Containerization)
import Containerization
#endif

/// A skill that executes inside an Apple Containerization sandbox.
///
/// All OpenClaw community skills run through this type. The skill directory is mounted
/// **read-only** into the container, and execution is subject to the approved
/// ``SkillPermissions`` (env vars, network, timeout, output limits).
///
/// ## Security Invariants
/// - Skill files mounted **read-only** via virtiofs
/// - Network **blocked by default** (no NATInterface unless approved)
/// - Environment variables **allowlisted** — only manifest-declared AND user-approved
/// - Timeout enforced via `TaskGroup` race + container kill
/// - Output truncated to `maxOutputBytes`
@available(macOS 26, *)
public struct ContainerizedSkill: NativeTool {
    public let id: String
    public let name: String
    public let description: String
    public let manifest: SkillManifest
    public let permissions: SkillPermissions
    public let profile: ContainerProfile
    private let pool: ContainerPool

    public init(
        manifest: SkillManifest,
        permissions: SkillPermissions,
        pool: ContainerPool
    ) {
        self.manifest = manifest
        self.permissions = permissions
        self.profile = ContainerProfile.from(manifest: manifest)
        self.pool = pool
        self.id = "openclaw-\(manifest.slug)"
        self.name = manifest.name
        self.description = manifest.description
    }

    public var isAvailable: Bool {
        get async { true }
    }

    /// Execute the skill inside a sandboxed container.
    ///
    /// 1. Acquire container from pool
    /// 2. Mount skill directory read-only at `/skill`
    /// 3. Detect main script (`run.sh` > `main.mjs` > `main.py`)
    /// 4. Pipe input via stdin
    /// 5. Inject only approved env vars
    /// 6. Race execution vs timeout
    /// 7. Capture stdout/stderr and return as NativeToolResult
    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        let startTime = Date()

        #if canImport(Containerization)
        return try await executeInContainer(input: input, startTime: startTime)
        #else
        throw SBBenderError.containerNotAvailable("Containerization framework not available on this platform")
        #endif
    }

    // MARK: - Tool Bridge

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("The input text to pass to the skill via stdin"),
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
            struct Args: Decodable { let input: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: .text(args.input))
            return result.output
        }
    }

    // MARK: - Container Execution

    #if canImport(Containerization)
    private func executeInContainer(input: NativeToolInput, startTime: Date) async throws -> NativeToolResult {
        let container = try await pool.acquire(profile: profile)
        defer {
            Task { await pool.release(container) }
        }

        let command = buildCommand()
        let envVars = buildEnvironmentVariables()
        let inputText = input.text ?? ""

        Log.container.info("Executing skill '\(manifest.slug)' in container \(container.id)")
        Log.container.debug("Command: \(command.joined(separator: " "))")

        // Race execution against timeout
        let result: (stdout: String, stderr: String, exitCode: Int32)
        do {
            result = try await withThrowingTaskGroup(of: (String, String, Int32).self) { group in
                group.addTask {
                    try await self.runProcess(
                        in: container,
                        command: command,
                        env: envVars,
                        stdin: inputText
                    )
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(self.permissions.timeoutSeconds))
                    throw SBBenderError.containerTimeout(
                        skill: self.manifest.slug,
                        seconds: self.permissions.timeoutSeconds
                    )
                }

                // First to complete wins
                let value = try await group.next()!
                group.cancelAll()
                return value
            }
        } catch let error as SBBenderError {
            if case .containerTimeout = error {
                Log.container.warning("Skill '\(manifest.slug)' timed out after \(permissions.timeoutSeconds)s")
                // Kill the container on timeout
                try? await container.container?.kill(9)
            }
            throw error
        }

        let latency = Date().timeIntervalSince(startTime)

        // Check exit code
        if result.exitCode != 0 {
            Log.container.warning("Skill '\(manifest.slug)' exited with code \(result.exitCode)")
            throw SBBenderError.containerExecFailed(
                skill: manifest.slug,
                exitCode: result.exitCode,
                stderr: String(result.stderr.prefix(1024))
            )
        }

        // Truncate output if needed
        var output = result.stdout
        if output.utf8.count > permissions.maxOutputBytes {
            let truncated = String(output.utf8.prefix(permissions.maxOutputBytes))!
            output = truncated + "\n[output truncated at \(permissions.maxOutputBytes) bytes]"
        }

        Log.container.info("Skill '\(manifest.slug)' completed in \(String(format: "%.2f", latency))s")

        return NativeToolResult(
            output: output,
            structuredData: result.stderr.isEmpty ? [:] : ["stderr": String(result.stderr.prefix(1024))],
            latency: latency
        )
    }

    private func runProcess(
        in container: ManagedContainer,
        command: [String],
        env: [String],
        stdin: String
    ) async throws -> (String, String, Int32) {
        // Configure process execution
        var config = LinuxProcessConfiguration()
        config.arguments = command
        config.environmentVariables = env
        config.workingDirectory = "/skill"

        // Set up stdout/stderr capture
        let stdoutCollector = OutputCollector(maxBytes: permissions.maxOutputBytes)
        let stderrCollector = OutputCollector(maxBytes: 4096)
        config.stdout = stdoutCollector
        config.stderr = stderrCollector

        // Set up stdin if needed
        if !stdin.isEmpty {
            config.stdin = InputProvider(data: Data(stdin.utf8))
        }

        let processId = "exec-\(UUID().uuidString.prefix(8))"
        guard let linuxContainer = container.container else {
            throw SBBenderError.containerNotAvailable("No Linux container available")
        }
        let process = try await linuxContainer.exec(processId, configuration: config)
        try await process.start()

        let exitStatus = try await process.wait(timeoutInSeconds: Int64(permissions.timeoutSeconds))
        try await process.delete()

        return (stdoutCollector.output, stderrCollector.output, exitStatus.exitCode)
    }
    #endif

    // MARK: - Helpers

    /// Detect the main script to execute in the skill directory.
    func buildCommand() -> [String] {
        let files = manifest.supportingFiles

        // Priority: run.sh > main.mjs > main.py > main.sh
        if files.contains("run.sh") {
            return ["/bin/sh", "/skill/run.sh"]
        }
        if files.contains("main.mjs") {
            return ["/usr/local/bin/node", "/skill/main.mjs"]
        }
        if files.contains("main.js") {
            return ["/usr/local/bin/node", "/skill/main.js"]
        }
        if files.contains("main.py") {
            return ["/usr/local/bin/python3", "/skill/main.py"]
        }
        if files.contains("main.sh") {
            return ["/bin/sh", "/skill/main.sh"]
        }

        // Fallback: first executable-looking file
        for file in files {
            let ext = (file as NSString).pathExtension
            switch ext {
            case "sh", "bash": return ["/bin/sh", "/skill/\(file)"]
            case "mjs", "js": return ["/usr/local/bin/node", "/skill/\(file)"]
            case "py": return ["/usr/local/bin/python3", "/skill/\(file)"]
            default: continue
            }
        }

        // Last resort
        return ["/bin/sh", "-c", "echo 'No executable script found in skill'"]
    }

    /// Build the environment variable list for the container process.
    func buildEnvironmentVariables() -> [String] {
        var env = [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "HOME=/root",
            "LANG=C.UTF-8",
        ]

        // Only inject user-approved env vars
        for (key, value) in permissions.approvedEnvVars {
            // Double-check against manifest-declared vars
            if manifest.requirements.env.contains(key) {
                env.append("\(key)=\(value)")
            }
        }

        return env
    }
}

// MARK: - I/O Helpers

#if canImport(Containerization)

/// Collects output from a container process stdout/stderr stream.
@available(macOS 26, *)
final class OutputCollector: Writer, @unchecked Sendable {
    private let mutex = Mutex<Data>(Data())
    private let maxBytes: Int

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func write(_ data: Data) throws {
        mutex.withLock { buffer in
            if buffer.count < maxBytes {
                let remaining = maxBytes - buffer.count
                buffer.append(data.prefix(remaining))
            }
        }
    }

    func close() throws {
        // No-op — output is collected via `output` property
    }

    var output: String {
        mutex.withLock { buffer in
            String(data: buffer, encoding: .utf8) ?? ""
        }
    }
}

/// Provides input data to a container process stdin as an AsyncStream.
@available(macOS 26, *)
final class InputProvider: ReaderStream, @unchecked Sendable {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func stream() -> AsyncStream<Data> {
        let data = self.data
        return AsyncStream { continuation in
            if !data.isEmpty {
                continuation.yield(data)
            }
            continuation.finish()
        }
    }
}

#endif
