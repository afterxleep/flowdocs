import Foundation

/// Mode represents the operating mode for flowdocs index
enum Mode: String, Codable, Sendable {
    case project
    case system
}

/// Document represents a stored document in SQLite
struct Document: Sendable {
    let path: String
    let title: String
    let content: String
    let contentHash: String  // SHA-256 (64 hex characters)
    let updatedAt: Date
}

/// SearchResult returned from search operations
struct SearchResult: Sendable {
    let path: String
    let title: String
    var score: Double  // normalized 0-1
    var snippet: String?
}

/// IndexStatus provides status information about the index
struct IndexStatus: Sendable {
    let mode: Mode
    let indexPath: String
    let documentCount: Int
    let embeddedCount: Int
    var lastUpdated: Date?
}

/// ProjectConfig holds configuration for the index
struct ProjectConfig: Sendable {
    let mode: Mode
    let indexPath: String
    var projectRoot: String?  // only used in project mode
}
