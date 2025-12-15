import Testing
import Foundation
@testable import flowdocs

@Suite("Search Tests")
struct SearchTests {

    // Helper to create a temporary database path
    static func tempDbPath() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("flowdocs_search_test_\(UUID().uuidString).db").path
    }

    // Helper to create a search instance with test data
    static func createTestSearch() throws -> (Search, Store, String) {
        let dbPath = tempDbPath()
        let store = Store(dbPath: dbPath)
        try store.open()

        // Add test documents
        try store.addDocument(DocumentInput(
            path: "/swift/basics.md",
            title: "Swift Basics",
            content: "Swift is a powerful programming language. Swift offers type safety and modern features."
        ))
        try store.addDocument(DocumentInput(
            path: "/swift/advanced.md",
            title: "Advanced Swift",
            content: "Advanced Swift topics include generics, protocols, and concurrency. Swift is great."
        ))
        try store.addDocument(DocumentInput(
            path: "/python/intro.md",
            title: "Python Introduction",
            content: "Python is a versatile programming language. Python is easy to learn."
        ))
        try store.addDocument(DocumentInput(
            path: "/rust/guide.md",
            title: "Rust Guide",
            content: "Rust provides memory safety without garbage collection. Rust is fast."
        ))

        let search = Search(store: store)
        return (search, store, dbPath)
    }

    // MARK: - FTS5 Query Sanitization Tests

    @Suite("Query Sanitization")
    struct QuerySanitizationTests {

        @Test("sanitizeFTSQuery removes asterisk wildcard")
        func sanitizeAsterisk() {
            let result = Search.sanitizeFTSQuery("hello*world")
            #expect(!result.contains("*"))
        }

        @Test("sanitizeFTSQuery removes caret")
        func sanitizeCaret() {
            let result = Search.sanitizeFTSQuery("hello^world")
            #expect(!result.contains("^"))
        }

        @Test("sanitizeFTSQuery removes parentheses")
        func sanitizeParentheses() {
            let result = Search.sanitizeFTSQuery("(hello)")
            #expect(!result.contains("("))
            #expect(!result.contains(")"))
        }

        @Test("sanitizeFTSQuery removes braces")
        func sanitizeBraces() {
            let result = Search.sanitizeFTSQuery("{hello}")
            #expect(!result.contains("{"))
            #expect(!result.contains("}"))
        }

        @Test("sanitizeFTSQuery removes brackets")
        func sanitizeBrackets() {
            let result = Search.sanitizeFTSQuery("[hello]")
            #expect(!result.contains("["))
            #expect(!result.contains("]"))
        }

        @Test("sanitizeFTSQuery removes colon")
        func sanitizeColon() {
            let result = Search.sanitizeFTSQuery("title:hello")
            #expect(!result.contains(":"))
        }

        @Test("sanitizeFTSQuery removes double quotes")
        func sanitizeQuotes() {
            let result = Search.sanitizeFTSQuery("\"hello world\"")
            #expect(!result.contains("\""))
        }

        @Test("sanitizeFTSQuery removes AND operator")
        func sanitizeAND() {
            let result = Search.sanitizeFTSQuery("hello AND world")
            #expect(!result.contains("AND"))
        }

        @Test("sanitizeFTSQuery removes OR operator")
        func sanitizeOR() {
            let result = Search.sanitizeFTSQuery("hello OR world")
            #expect(!result.contains("OR"))
        }

        @Test("sanitizeFTSQuery removes NOT operator")
        func sanitizeNOT() {
            let result = Search.sanitizeFTSQuery("NOT hello")
            #expect(!result.contains("NOT"))
        }

        @Test("sanitizeFTSQuery removes NEAR operator")
        func sanitizeNEAR() {
            let result = Search.sanitizeFTSQuery("hello NEAR world")
            #expect(!result.contains("NEAR"))
        }

        @Test("sanitizeFTSQuery preserves lowercase 'and', 'or', 'not'")
        func preserveLowercaseOperators() {
            // FTS5 operators are case-sensitive, lowercase should be preserved
            let result1 = Search.sanitizeFTSQuery("this and that")
            #expect(result1.contains("and"))

            let result2 = Search.sanitizeFTSQuery("this or that")
            #expect(result2.contains("or"))
        }

        @Test("sanitizeFTSQuery cleans up whitespace")
        func cleanWhitespace() {
            let result = Search.sanitizeFTSQuery("  hello   world  ")
            #expect(result == "hello world")
        }

        @Test("sanitizeFTSQuery returns empty for all-special input")
        func emptyForSpecialInput() {
            let result = Search.sanitizeFTSQuery("***^^^()")
            #expect(result.isEmpty)
        }
    }

    // MARK: - Score Normalization Tests

    @Suite("Score Normalization")
    struct ScoreNormalizationTests {

        @Test("normalizeScores maps to 0-1 range")
        func normalizeToRange() {
            let results = [
                SearchResult(path: "/a.md", title: "A", score: 10.0, snippet: nil),
                SearchResult(path: "/b.md", title: "B", score: 5.0, snippet: nil),
                SearchResult(path: "/c.md", title: "C", score: 1.0, snippet: nil)
            ]

            let normalized = Search.normalizeScores(results)

            for result in normalized {
                #expect(result.score >= 0.0)
                #expect(result.score <= 1.0)
            }
        }

        @Test("normalizeScores highest relevance gets 1.0")
        func highestGetsOne() {
            // Standard positive scores (higher = more relevant)
            let results = [
                SearchResult(path: "/a.md", title: "A", score: 10.0, snippet: nil),  // Most relevant
                SearchResult(path: "/b.md", title: "B", score: 5.0, snippet: nil),
                SearchResult(path: "/c.md", title: "C", score: 1.0, snippet: nil)    // Least relevant
            ]

            let normalized = Search.normalizeScores(results)

            // First result should have highest score (normalized to 1.0)
            #expect(normalized[0].score == 1.0)
        }

        @Test("normalizeScores lowest relevance gets 0.0")
        func lowestGetsZero() {
            // Standard positive scores (higher = more relevant)
            let results = [
                SearchResult(path: "/a.md", title: "A", score: 10.0, snippet: nil),  // Most relevant
                SearchResult(path: "/b.md", title: "B", score: 5.0, snippet: nil),
                SearchResult(path: "/c.md", title: "C", score: 1.0, snippet: nil)    // Least relevant
            ]

            let normalized = Search.normalizeScores(results)

            // Last result should have lowest score (normalized to 0.0)
            #expect(normalized[2].score == 0.0)
        }

        @Test("normalizeScores handles all-equal scores")
        func handleEqualScores() {
            let results = [
                SearchResult(path: "/a.md", title: "A", score: 5.0, snippet: nil),
                SearchResult(path: "/b.md", title: "B", score: 5.0, snippet: nil),
                SearchResult(path: "/c.md", title: "C", score: 5.0, snippet: nil)
            ]

            let normalized = Search.normalizeScores(results)

            // All should have score 1.0 when equal
            for result in normalized {
                #expect(result.score == 1.0)
            }
        }

        @Test("normalizeScores handles empty array")
        func handleEmpty() {
            let results: [SearchResult] = []
            let normalized = Search.normalizeScores(results)
            #expect(normalized.isEmpty)
        }

        @Test("normalizeScores handles single result")
        func handleSingle() {
            let results = [
                SearchResult(path: "/a.md", title: "A", score: 5.0, snippet: nil)
            ]

            let normalized = Search.normalizeScores(results)

            #expect(normalized.count == 1)
            #expect(normalized[0].score == 1.0)
        }
    }

    // MARK: - Reciprocal Rank Fusion Tests

    @Suite("Reciprocal Rank Fusion")
    struct RRFTests {

        @Test("RRF combines two result sets")
        func combinesTwoSets() {
            let set1 = [
                SearchResult(path: "/a.md", title: "A", score: 1.0, snippet: nil),
                SearchResult(path: "/b.md", title: "B", score: 0.8, snippet: nil)
            ]
            let set2 = [
                SearchResult(path: "/b.md", title: "B", score: 1.0, snippet: nil),
                SearchResult(path: "/c.md", title: "C", score: 0.5, snippet: nil)
            ]

            let fused = Search.reciprocalRankFusion([set1, set2], k: 60)

            // Should contain all unique paths
            let paths = Set(fused.map { $0.path })
            #expect(paths.contains("/a.md"))
            #expect(paths.contains("/b.md"))
            #expect(paths.contains("/c.md"))
        }

        @Test("RRF boosts documents appearing in multiple sets")
        func boostsMultipleAppearances() {
            let set1 = [
                SearchResult(path: "/a.md", title: "A", score: 1.0, snippet: nil),  // rank 1
                SearchResult(path: "/b.md", title: "B", score: 0.8, snippet: nil)   // rank 2
            ]
            let set2 = [
                SearchResult(path: "/b.md", title: "B", score: 1.0, snippet: nil),  // rank 1
                SearchResult(path: "/c.md", title: "C", score: 0.5, snippet: nil)   // rank 2
            ]

            let fused = Search.reciprocalRankFusion([set1, set2], k: 60)

            // B appears in both sets, so should rank highest
            #expect(fused.first?.path == "/b.md")
        }

        @Test("RRF uses k=60 by default")
        func defaultK60() {
            let set1 = [
                SearchResult(path: "/a.md", title: "A", score: 1.0, snippet: nil)
            ]

            // Using default k should produce same result as explicit k=60
            let fusedDefault = Search.reciprocalRankFusion([set1])
            let fusedExplicit = Search.reciprocalRankFusion([set1], k: 60)

            #expect(fusedDefault.count == fusedExplicit.count)
            if !fusedDefault.isEmpty {
                #expect(fusedDefault[0].score == fusedExplicit[0].score)
            }
        }

        @Test("RRF handles empty input")
        func handlesEmpty() {
            let fused = Search.reciprocalRankFusion([])
            #expect(fused.isEmpty)
        }

        @Test("RRF handles single set")
        func handlesSingleSet() {
            let set1 = [
                SearchResult(path: "/a.md", title: "A", score: 1.0, snippet: nil),
                SearchResult(path: "/b.md", title: "B", score: 0.8, snippet: nil)
            ]

            let fused = Search.reciprocalRankFusion([set1], k: 60)

            // Should preserve order from single set
            #expect(fused.count == 2)
            #expect(fused[0].path == "/a.md")
            #expect(fused[1].path == "/b.md")
        }

        @Test("RRF results are sorted by fused score")
        func sortedByScore() {
            let set1 = [
                SearchResult(path: "/a.md", title: "A", score: 1.0, snippet: nil),
                SearchResult(path: "/b.md", title: "B", score: 0.5, snippet: nil)
            ]
            let set2 = [
                SearchResult(path: "/c.md", title: "C", score: 1.0, snippet: nil),
                SearchResult(path: "/a.md", title: "A", score: 0.5, snippet: nil)
            ]

            let fused = Search.reciprocalRankFusion([set1, set2], k: 60)

            // Results should be in descending score order
            for i in 0..<(fused.count - 1) {
                #expect(fused[i].score >= fused[i + 1].score)
            }
        }
    }

    // MARK: - Search Integration Tests

    @Suite("Search Integration")
    struct IntegrationTests {

        @Test("keywordSearch finds documents by content")
        func keywordSearchByContent() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.keywordSearch(query: "Swift", limit: 10)

            #expect(results.count == 2)
            let paths = Set(results.map { $0.path })
            #expect(paths.contains("/swift/basics.md"))
            #expect(paths.contains("/swift/advanced.md"))
        }

        @Test("keywordSearch respects limit")
        func keywordSearchLimit() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.keywordSearch(query: "programming", limit: 2)

            #expect(results.count == 2)
        }

        @Test("hybridSearch returns results")
        func hybridSearchReturns() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.hybridSearch(query: "Swift", limit: 10)

            // Should return results (hybrid uses keyword search when vector not available)
            #expect(!results.isEmpty)
        }

        @Test("search with keyword mode uses keywordSearch")
        func searchKeywordMode() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.search(query: "Rust", mode: .keyword, limit: 10)

            #expect(results.count == 1)
            #expect(results.first?.path == "/rust/guide.md")
        }

        @Test("search with hybrid mode as default")
        func searchDefaultHybrid() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            // Default mode should be hybrid
            let results = search.search(query: "Python", limit: 10)

            #expect(!results.isEmpty)
            #expect(results.first?.path == "/python/intro.md")
        }

        @Test("search returns empty for no matches")
        func searchNoMatches() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.search(query: "JavaScript", limit: 10)

            #expect(results.isEmpty)
        }

        @Test("search results have normalized scores")
        func searchNormalizedScores() throws {
            let (search, store, dbPath) = try SearchTests.createTestSearch()
            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let results = search.search(query: "programming language", limit: 10)

            for result in results {
                #expect(result.score >= 0.0)
                #expect(result.score <= 1.0)
            }
        }
    }
}
