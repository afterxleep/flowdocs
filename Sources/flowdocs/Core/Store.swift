import Foundation
import SQLite3
import CryptoKit

/// Input structure for adding documents (without hash/timestamp)
struct DocumentInput: Sendable {
    let path: String
    let title: String
    let content: String
}

/// Errors that can occur during Store operations
enum StoreError: Error, LocalizedError {
    case databaseNotOpen
    case sqliteError(Int32, String)
    case preparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen:
            return "Database is not open"
        case .sqliteError(let code, let message):
            return "SQLite error (\(code)): \(message)"
        case .preparationFailed(let sql):
            return "Failed to prepare statement: \(sql)"
        }
    }
}

/// SQLite-based document store with FTS5 full-text search.
///
/// ## Thread Safety
///
/// This class is thread-safe. All public methods that access the database are protected
/// by an internal `NSLock`. The class is marked as `@unchecked Sendable` because it
/// manually manages thread safety rather than relying on Swift's concurrency checking.
///
/// **Implementation details:**
/// - All database operations acquire `lock` before accessing `db`
/// - The lock is always released via `defer` to ensure exception safety
/// - Internal helper methods suffixed with `Unlocked` assume the caller holds the lock
/// - WAL mode is enabled for better read/write concurrency at the SQLite level
final class Store: @unchecked Sendable {

    let dbPath: String
    private var db: OpaquePointer?
    private let lock = NSLock()

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    deinit {
        close()
    }

    // MARK: - Database Lifecycle

    /// Opens the database and creates schema if needed
    func open() throws {
        lock.lock()
        defer { lock.unlock() }

        var db: OpaquePointer?
        let result = sqlite3_open(dbPath, &db)

        if result != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw StoreError.sqliteError(result, message)
        }

        self.db = db

        // Set WAL mode for better concurrency
        try executeUnlocked("PRAGMA journal_mode = WAL")

        // Create schema
        try createSchemaUnlocked()
    }

    /// Closes the database connection
    func close() {
        lock.lock()
        defer { lock.unlock() }

        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Schema

    /// Creates schema - unlocked version for use within already-locked context
    private func createSchemaUnlocked() throws {
        // Main documents table
        try executeUnlocked("""
            CREATE TABLE IF NOT EXISTS documents (
                path TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
        """)

        // FTS5 virtual table for full-text search
        try executeUnlocked("""
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                path,
                title,
                content,
                content='documents',
                content_rowid='rowid'
            )
        """)

        // Triggers to keep FTS in sync with documents table
        try executeUnlocked("""
            CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN
                INSERT INTO documents_fts(rowid, path, title, content)
                VALUES (NEW.rowid, NEW.path, NEW.title, NEW.content);
            END
        """)

        try executeUnlocked("""
            CREATE TRIGGER IF NOT EXISTS documents_ad AFTER DELETE ON documents BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, path, title, content)
                VALUES ('delete', OLD.rowid, OLD.path, OLD.title, OLD.content);
            END
        """)

        try executeUnlocked("""
            CREATE TRIGGER IF NOT EXISTS documents_au AFTER UPDATE ON documents BEGIN
                INSERT INTO documents_fts(documents_fts, rowid, path, title, content)
                VALUES ('delete', OLD.rowid, OLD.path, OLD.title, OLD.content);
                INSERT INTO documents_fts(rowid, path, title, content)
                VALUES (NEW.rowid, NEW.path, NEW.title, NEW.content);
            END
        """)

        // Embeddings table (for future vector search)
        try executeUnlocked("""
            CREATE TABLE IF NOT EXISTS embeddings (
                path TEXT PRIMARY KEY,
                embedding BLOB,
                FOREIGN KEY (path) REFERENCES documents(path) ON DELETE CASCADE
            )
        """)

        // Index on content_hash for efficient lookups
        try executeUnlocked("CREATE INDEX IF NOT EXISTS idx_content_hash ON documents(content_hash)")
    }

    // MARK: - Document Operations

    /// Adds or updates a document
    func addDocument(_ input: DocumentInput) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else {
            throw StoreError.databaseNotOpen
        }

        let contentHash = sha256Hash(input.content)
        let updatedAt = Date().timeIntervalSince1970

        let sql = """
            INSERT INTO documents (path, title, content, content_hash, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                title = excluded.title,
                content = excluded.content,
                content_hash = excluded.content_hash,
                updated_at = excluded.updated_at
        """

        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.preparationFailed(sql)
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, input.path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, input.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, input.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, updatedAt)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            let message = String(cString: sqlite3_errmsg(db))
            throw StoreError.sqliteError(result, message)
        }
    }

    /// Gets a document by path
    func getDocument(path: String) -> Document? {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { return nil }

        let sql = "SELECT path, title, content, content_hash, updated_at FROM documents WHERE path = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return documentFromStatement(stmt)
        }

        return nil
    }

    /// Removes a document by path
    func removeDocument(path: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else {
            throw StoreError.databaseNotOpen
        }

        let sql = "DELETE FROM documents WHERE path = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.preparationFailed(sql)
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            let message = String(cString: sqlite3_errmsg(db))
            throw StoreError.sqliteError(result, message)
        }
    }

    /// Gets all documents
    func getAllDocuments() -> [Document] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { return [] }

        let sql = "SELECT path, title, content, content_hash, updated_at FROM documents"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(stmt) }

        var documents: [Document] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let doc = documentFromStatement(stmt) {
                documents.append(doc)
            }
        }

        return documents
    }

    // MARK: - FTS5 Search

    /// Searches documents using FTS5
    /// - Parameters:
    ///   - query: The search query string
    ///   - limit: Maximum number of results (clamped to 1-1000)
    /// - Returns: Array of search results
    func searchFTS(query: String, limit: Int) -> [SearchResult] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { return [] }

        // Validate and clamp limit parameter
        let safeLimit = max(1, min(limit, 1000))
        // Safe conversion to Int32 (1000 is well below Int32.max)
        let sqliteLimit = Int32(safeLimit)

        let sanitizedQuery = Search.sanitizeFTSQuery(query)
        if sanitizedQuery.isEmpty { return [] }

        let sql = """
            SELECT d.path, d.title, bm25(documents_fts) as score
            FROM documents_fts
            JOIN documents d ON documents_fts.path = d.path
            WHERE documents_fts MATCH ?
            ORDER BY score
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sanitizedQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, sqliteLimit)

        var results: [SearchResult] = []
        var rawScores: [Double] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            // NULL check for sqlite3_column_text to prevent crash
            guard let pathPtr = sqlite3_column_text(stmt, 0),
                  let titlePtr = sqlite3_column_text(stmt, 1) else {
                continue
            }

            let path = String(cString: pathPtr)
            let title = String(cString: titlePtr)
            let score = sqlite3_column_double(stmt, 2)

            results.append(SearchResult(
                path: path,
                title: title,
                score: score,  // Will be normalized later
                snippet: nil
            ))
            rawScores.append(score)
        }

        // Normalize scores to 0-1 range
        return normalizeScores(results, rawScores: rawScores)
    }

    /// Normalizes scores to 0-1 range using min-max scaling
    private func normalizeScores(_ results: [SearchResult], rawScores: [Double]) -> [SearchResult] {
        guard !results.isEmpty else { return results }

        // BM25 returns negative scores (lower is better)
        // Convert to positive and normalize
        let minScore = rawScores.min() ?? 0
        let maxScore = rawScores.max() ?? 0

        // Handle case where all scores are equal
        if minScore == maxScore {
            return results.map { result in
                var r = result
                r.score = 1.0
                return r
            }
        }

        return zip(results, rawScores).map { (result, rawScore) in
            var r = result
            // Invert because BM25 is lower-is-better (negative values)
            // Transform so highest relevance = 1.0, lowest = 0.0
            r.score = (maxScore - rawScore) / (maxScore - minScore)
            return r
        }
    }

    // MARK: - Statistics

    /// Gets document and embedding counts
    func getStats() -> (documentCount: Int, embeddedCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { return (0, 0) }

        var documentCount = 0
        var embeddedCount = 0

        // Count documents
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM documents", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                documentCount = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        // Count embeddings
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM embeddings WHERE embedding IS NOT NULL", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                embeddedCount = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        return (documentCount, embeddedCount)
    }

    // MARK: - Helpers

    /// Executes SQL - unlocked version for use within already-locked context
    private func executeUnlocked(_ sql: String) throws {
        guard let db = db else {
            throw StoreError.databaseNotOpen
        }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw StoreError.sqliteError(result, message)
        }
    }

    /// Parses a document from a SQLite statement
    /// Returns nil if any required column is NULL
    private func documentFromStatement(_ stmt: OpaquePointer?) -> Document? {
        guard let stmt = stmt else { return nil }

        // NULL check for all text columns to prevent crash
        guard let pathPtr = sqlite3_column_text(stmt, 0),
              let titlePtr = sqlite3_column_text(stmt, 1),
              let contentPtr = sqlite3_column_text(stmt, 2),
              let hashPtr = sqlite3_column_text(stmt, 3) else {
            return nil
        }

        let path = String(cString: pathPtr)
        let title = String(cString: titlePtr)
        let content = String(cString: contentPtr)
        let contentHash = String(cString: hashPtr)
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))

        return Document(
            path: path,
            title: title,
            content: content,
            contentHash: contentHash,
            updatedAt: updatedAt
        )
    }

    /// Computes SHA-256 hash of content
    private func sha256Hash(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// SQLITE_TRANSIENT constant for binding
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
