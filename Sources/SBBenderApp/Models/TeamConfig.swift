import Foundation
import GRDB

struct TeamConfig: Codable, Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var emoji: String
    var gradientHex: [String]
    var mode: String
    var memberIDs: [String]
    var leaderID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "New Team",
        emoji: String = "👥",
        gradientHex: [String] = ["#7209B7", "#B5179E"],
        mode: String = "sequential",
        memberIDs: [String] = [],
        leaderID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.gradientHex = gradientHex
        self.mode = mode
        self.memberIDs = memberIDs
        self.leaderID = leaderID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - GRDB Record

extension TeamConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "team_configs"

    enum Columns: String, ColumnExpression {
        case id, name, emoji, gradientHex, mode
        case memberIDs, leaderID, createdAt, updatedAt
    }
}
