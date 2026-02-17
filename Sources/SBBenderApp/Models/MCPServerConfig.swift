import Foundation
import GRDB

struct MCPServerConfig: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        command: String = "",
        arguments: [String] = [],
        environment: [String: String] = [:],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.enabled = enabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - GRDB Record

extension MCPServerConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "mcp_server_configs"

    enum Columns: String, ColumnExpression {
        case id, name, command, arguments, environment
        case enabled, createdAt, updatedAt
    }
}
