import Foundation
import GRDB
import SBBender

struct ToolParamConfig: Codable, Sendable, Equatable {
    var name: String
    var type: String          // "string", "integer", "boolean", "number"
    var description: String
    var required: Bool
}

struct ToolConfig: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var toolDescription: String
    var parameters: [ToolParamConfig]
    var executionType: String       // "shell", "http", "javascript", "applescript"
    var executionBody: String
    var requiresConfirmation: Bool
    var agentID: String?            // nil = global
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        toolDescription: String = "",
        parameters: [ToolParamConfig] = [],
        executionType: String = "shell",
        executionBody: String = "",
        requiresConfirmation: Bool = false,
        agentID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.toolDescription = toolDescription
        self.parameters = parameters
        self.executionType = executionType
        self.executionBody = executionBody
        self.requiresConfirmation = requiresConfirmation
        self.agentID = agentID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - GRDB Record

extension ToolConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "tool_configs"

    enum Columns: String, ColumnExpression {
        case id, name, toolDescription, parameters
        case executionType, executionBody, requiresConfirmation
        case agentID, createdAt, updatedAt
    }
}

// MARK: - Live Tool Conversion

extension ToolConfig {
    /// Interpolate `${paramName}` placeholders in the execution body with argument values.
    private static func interpolate(template: String, arguments: [String: Any]) -> String {
        var result = template
        for (key, value) in arguments {
            result = result.replacingOccurrences(of: "${\(key)}", with: "\(value)")
        }
        return result
    }

    private static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    func toLiveTool() -> Tool {
        let schema = JSONSchema(
            type: "object",
            properties: Dictionary(uniqueKeysWithValues: parameters.map { param in
                (param.name, PropertySchema(type: param.type, description: param.description))
            }),
            required: parameters.filter(\.required).map(\.name)
        )

        let body = executionBody
        let execType = executionType

        return Tool(
            name: name,
            description: toolDescription,
            parameters: schema,
            requiresConfirmation: requiresConfirmation
        ) { arguments, _ in
            let args = ToolConfig.parseArguments(arguments)
            let resolved = ToolConfig.interpolate(template: body, arguments: args)

            switch execType {
            case "shell":
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", resolved]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""

            case "http":
                guard let url = URL(string: resolved) else {
                    return "Invalid URL: \(resolved)"
                }
                let (data, _) = try await URLSession.shared.data(from: url)
                return String(data: data, encoding: .utf8) ?? ""

            case "applescript":
                #if canImport(AppKit)
                let script = NSAppleScript(source: resolved)
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)
                if let error {
                    return "AppleScript error: \(error)"
                }
                return result?.stringValue ?? ""
                #else
                return "AppleScript not available"
                #endif

            default:
                return "Unknown execution type: \(execType)"
            }
        }
    }
}
