import Foundation

/// Search mode options
enum SearchMode: Sendable {
    case keyword
    case vector
    case hybrid
}

/// Pre-compiled regexes for FTS query sanitization (performance optimization)
private let ftsOperatorRegexes: [NSRegularExpression] = {
    let operators = ["AND", "OR", "NOT", "NEAR"]
    return operators.compactMap { op in
        try? NSRegularExpression(pattern: "\\b\(op)\\b", options: [])
    }
}()

/// Search engine that combines keyword and vector search
final class Search: @unchecked Sendable {

    let store: Store

    init(store: Store) {
        self.store = store
    }

    // MARK: - Public Search API

    /// Performs a search with the specified mode
    /// - Parameters:
    ///   - query: The search query
    ///   - mode: The search mode (keyword, vector, or hybrid)
    ///   - limit: Maximum number of results
    /// - Returns: Array of search results sorted by relevance
    func search(query: String, mode: SearchMode = .hybrid, limit: Int = 10) -> [SearchResult] {
        switch mode {
        case .keyword:
            return keywordSearch(query: query, limit: limit)
        case .vector:
            // Vector search not yet implemented, fall back to keyword
            return keywordSearch(query: query, limit: limit)
        case .hybrid:
            return hybridSearch(query: query, limit: limit)
        }
    }

    /// Performs keyword-based FTS5 search
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results
    /// - Returns: Array of search results
    func keywordSearch(query: String, limit: Int) -> [SearchResult] {
        return store.searchFTS(query: query, limit: limit)
    }

    /// Performs hybrid search combining keyword and vector results
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results
    /// - Returns: Array of search results using Reciprocal Rank Fusion
    func hybridSearch(query: String, limit: Int) -> [SearchResult] {
        // Get keyword results
        let keywordResults = keywordSearch(query: query, limit: limit * 2)

        // Vector search not yet implemented
        // When implemented, would get vector results and fuse them
        // let vectorResults = vectorSearch(query: query, limit: limit * 2)
        // return reciprocalRankFusion([keywordResults, vectorResults], k: 60)

        // For now, just return keyword results
        return Array(Search.reciprocalRankFusion([keywordResults], k: 60).prefix(limit))
    }

    // MARK: - Reciprocal Rank Fusion

    /// Combines multiple result sets using Reciprocal Rank Fusion
    /// - Parameters:
    ///   - resultSets: Array of search result arrays to fuse
    ///   - k: The k parameter (default 60, standard RRF constant)
    /// - Returns: Fused results sorted by combined score
    static func reciprocalRankFusion(_ resultSets: [[SearchResult]], k: Int = 60) -> [SearchResult] {
        guard !resultSets.isEmpty else { return [] }

        // Track RRF scores and best result info per path
        var rrfScores: [String: Double] = [:]
        var resultInfo: [String: SearchResult] = [:]

        for resultSet in resultSets {
            for (rank, result) in resultSet.enumerated() {
                // RRF score: 1 / (k + rank), where rank is 1-indexed
                let score = 1.0 / Double(k + rank + 1)
                rrfScores[result.path, default: 0] += score

                // Keep track of the result info (use first occurrence)
                if resultInfo[result.path] == nil {
                    resultInfo[result.path] = result
                }
            }
        }

        // Build final results with fused scores
        var fusedResults: [SearchResult] = []

        for (path, rrfScore) in rrfScores {
            if var result = resultInfo[path] {
                result.score = rrfScore
                fusedResults.append(result)
            }
        }

        // Sort by score descending
        fusedResults.sort { $0.score > $1.score }

        // Normalize scores to 0-1 range
        return normalizeScores(fusedResults)
    }

    // MARK: - Score Normalization

    /// Normalizes scores to 0-1 range using min-max scaling
    /// - Parameter results: Array of search results with raw scores
    /// - Returns: Array of search results with normalized scores
    static func normalizeScores(_ results: [SearchResult]) -> [SearchResult] {
        guard !results.isEmpty else { return results }

        let scores = results.map { $0.score }
        let minScore = scores.min() ?? 0
        let maxScore = scores.max() ?? 0

        // Handle case where all scores are equal
        if minScore == maxScore {
            return results.map { result in
                var r = result
                r.score = 1.0
                return r
            }
        }

        // Min-max normalization
        return results.map { result in
            var r = result
            r.score = (result.score - minScore) / (maxScore - minScore)
            return r
        }
    }

    // MARK: - Query Sanitization

    /// Sanitizes a query string for FTS5
    /// - Parameter query: The raw query string
    /// - Returns: Sanitized query safe for FTS5
    static func sanitizeFTSQuery(_ query: String) -> String {
        var sanitized = query

        // Remove FTS5 special characters: * ^ ( ) { } [ ] :
        let specialChars = CharacterSet(charactersIn: "*^(){}[]:")
        sanitized = sanitized.unicodeScalars
            .filter { !specialChars.contains($0) }
            .map { String($0) }
            .joined()

        // Remove double quotes
        sanitized = sanitized.replacingOccurrences(of: "\"", with: "")

        // Remove boolean operators using pre-compiled regexes (case-sensitive in FTS5)
        for regex in ftsOperatorRegexes {
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: " "
            )
        }

        // Clean up whitespace
        sanitized = sanitized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return sanitized
    }
}
