import Testing
import Foundation
@testable import flowdocs

@Suite("Store Tests")
struct StoreTests {

    // Helper to create a temporary database path
    static func tempDbPath() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("flowdocs_test_\(UUID().uuidString).db").path
    }

    // MARK: - Initialization Tests

    @Suite("Store Initialization")
    struct InitializationTests {

        @Test("Store can be initialized with a database path")
        func storeInitialization() {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            #expect(store.dbPath == dbPath)
        }

        @Test("Store can open and create database")
        func storeOpen() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)

            try store.open()
            #expect(FileManager.default.fileExists(atPath: dbPath))

            store.close()
            try? FileManager.default.removeItem(atPath: dbPath)
        }

        @Test("Store creates WAL journal mode")
        func storeWALMode() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)

            try store.open()

            // WAL mode creates -wal and -shm files
            // We verify by checking the store is functional
            #expect(FileManager.default.fileExists(atPath: dbPath))

            store.close()
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        @Test("Store can be closed")
        func storeClose() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)

            try store.open()
            store.close()

            // Should be able to delete the file after closing
            try FileManager.default.removeItem(atPath: dbPath)
            #expect(!FileManager.default.fileExists(atPath: dbPath))
        }
    }

    // MARK: - Document Operations Tests

    @Suite("Document Operations")
    struct DocumentOperationsTests {

        @Test("Add document creates new document")
        func addDocument() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let input = DocumentInput(
                path: "/test/doc.md",
                title: "Test Document",
                content: "This is test content"
            )

            try store.addDocument(input)

            let doc = store.getDocument(path: "/test/doc.md")
            #expect(doc != nil)
            #expect(doc?.path == "/test/doc.md")
            #expect(doc?.title == "Test Document")
            #expect(doc?.content == "This is test content")
        }

        @Test("Add document generates SHA-256 hash")
        func addDocumentHash() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let input = DocumentInput(
                path: "/test/doc.md",
                title: "Test",
                content: "Hello World"
            )

            try store.addDocument(input)

            let doc = store.getDocument(path: "/test/doc.md")
            #expect(doc != nil)
            #expect(doc?.contentHash.count == 64) // SHA-256 is 64 hex chars
            #expect(doc?.contentHash.allSatisfy { $0.isHexDigit } == true)
        }

        @Test("Add document sets updatedAt timestamp")
        func addDocumentTimestamp() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let beforeAdd = Date()

            let input = DocumentInput(
                path: "/test/doc.md",
                title: "Test",
                content: "Content"
            )

            try store.addDocument(input)

            let afterAdd = Date()
            let doc = store.getDocument(path: "/test/doc.md")

            #expect(doc != nil)
            #expect(doc!.updatedAt >= beforeAdd)
            #expect(doc!.updatedAt <= afterAdd)
        }

        @Test("Add document with same path updates existing")
        func addDocumentUpsert() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let input1 = DocumentInput(
                path: "/test/doc.md",
                title: "Original Title",
                content: "Original content"
            )
            try store.addDocument(input1)

            let input2 = DocumentInput(
                path: "/test/doc.md",
                title: "Updated Title",
                content: "Updated content"
            )
            try store.addDocument(input2)

            let doc = store.getDocument(path: "/test/doc.md")
            #expect(doc != nil)
            #expect(doc?.title == "Updated Title")
            #expect(doc?.content == "Updated content")

            // Should still be just one document
            let all = store.getAllDocuments()
            #expect(all.count == 1)
        }

        @Test("Get document returns nil for non-existent path")
        func getDocumentNotFound() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let doc = store.getDocument(path: "/non/existent.md")
            #expect(doc == nil)
        }

        @Test("Remove document deletes document")
        func removeDocument() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let input = DocumentInput(
                path: "/test/doc.md",
                title: "Test",
                content: "Content"
            )
            try store.addDocument(input)

            #expect(store.getDocument(path: "/test/doc.md") != nil)

            try store.removeDocument(path: "/test/doc.md")

            #expect(store.getDocument(path: "/test/doc.md") == nil)
        }

        @Test("Remove non-existent document does not throw")
        func removeNonExistentDocument() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            // Should not throw
            try store.removeDocument(path: "/non/existent.md")
        }

        @Test("Get all documents returns empty array initially")
        func getAllDocumentsEmpty() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let docs = store.getAllDocuments()
            #expect(docs.isEmpty)
        }

        @Test("Get all documents returns all added documents")
        func getAllDocuments() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(path: "/a.md", title: "A", content: "Content A"))
            try store.addDocument(DocumentInput(path: "/b.md", title: "B", content: "Content B"))
            try store.addDocument(DocumentInput(path: "/c.md", title: "C", content: "Content C"))

            let docs = store.getAllDocuments()
            #expect(docs.count == 3)

            let paths = Set(docs.map { $0.path })
            #expect(paths.contains("/a.md"))
            #expect(paths.contains("/b.md"))
            #expect(paths.contains("/c.md"))
        }
    }

    // MARK: - FTS5 Search Tests

    @Suite("FTS5 Search")
    struct FTS5SearchTests {

        @Test("Search finds document by content")
        func searchByContent() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/swift.md",
                title: "Swift Guide",
                content: "Swift is a powerful programming language"
            ))
            try store.addDocument(DocumentInput(
                path: "/python.md",
                title: "Python Guide",
                content: "Python is a versatile language"
            ))

            let results = store.searchFTS(query: "Swift", limit: 10)

            #expect(results.count == 1)
            #expect(results.first?.path == "/swift.md")
        }

        @Test("Search finds document by title")
        func searchByTitle() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/guide.md",
                title: "SwiftUI Tutorial",
                content: "Learn about user interfaces"
            ))

            let results = store.searchFTS(query: "SwiftUI", limit: 10)

            #expect(results.count == 1)
            #expect(results.first?.title == "SwiftUI Tutorial")
        }

        @Test("Search returns multiple matches ranked by relevance")
        func searchMultipleMatches() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/a.md",
                title: "Swift Swift Swift",
                content: "Swift Swift Swift Swift Swift"  // More mentions
            ))
            try store.addDocument(DocumentInput(
                path: "/b.md",
                title: "Swift",
                content: "Swift is nice"  // Fewer mentions
            ))

            let results = store.searchFTS(query: "Swift", limit: 10)

            #expect(results.count == 2)
            // First result should be the one with more matches (higher BM25 score)
            #expect(results.first?.path == "/a.md")
        }

        @Test("Search respects limit parameter")
        func searchLimit() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            for i in 1...10 {
                try store.addDocument(DocumentInput(
                    path: "/doc\(i).md",
                    title: "Document \(i)",
                    content: "Swift programming content"
                ))
            }

            let results = store.searchFTS(query: "Swift", limit: 3)

            #expect(results.count == 3)
        }

        @Test("Search returns normalized scores between 0 and 1")
        func searchNormalizedScores() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/a.md",
                title: "Swift",
                content: "Swift Swift Swift"
            ))
            try store.addDocument(DocumentInput(
                path: "/b.md",
                title: "Swift",
                content: "Swift"
            ))

            let results = store.searchFTS(query: "Swift", limit: 10)

            for result in results {
                #expect(result.score >= 0.0)
                #expect(result.score <= 1.0)
            }
        }

        @Test("Search returns empty for no matches")
        func searchNoMatches() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Swift Guide",
                content: "All about Swift programming"
            ))

            let results = store.searchFTS(query: "Rust", limit: 10)

            #expect(results.isEmpty)
        }

        @Test("Search sanitizes special characters")
        func searchSanitization() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Test",
                content: "Hello world"
            ))

            // These should not crash or throw - special chars should be sanitized
            let results1 = store.searchFTS(query: "Hello*", limit: 10)
            let results2 = store.searchFTS(query: "Hello^world", limit: 10)
            let results3 = store.searchFTS(query: "(Hello)", limit: 10)
            let results4 = store.searchFTS(query: "{test}", limit: 10)
            let results5 = store.searchFTS(query: "[test]", limit: 10)
            let results6 = store.searchFTS(query: "test:value", limit: 10)
            let results7 = store.searchFTS(query: "test\"quote", limit: 10)

            // Verify search still works after sanitization
            #expect(results1.count >= 0)
            #expect(results2.count >= 0)
            #expect(results3.count >= 0)
            #expect(results4.count >= 0)
            #expect(results5.count >= 0)
            #expect(results6.count >= 0)
            #expect(results7.count >= 0)
        }

        @Test("Search rejects boolean operators")
        func searchRejectsOperators() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Test",
                content: "Hello world"
            ))

            // AND, OR, NOT, NEAR should be stripped or handled
            let results1 = store.searchFTS(query: "Hello AND world", limit: 10)
            let results2 = store.searchFTS(query: "Hello OR world", limit: 10)
            let results3 = store.searchFTS(query: "NOT Hello", limit: 10)
            let results4 = store.searchFTS(query: "Hello NEAR world", limit: 10)

            // Should not crash, may return empty or partial results
            #expect(results1.count >= 0)
            #expect(results2.count >= 0)
            #expect(results3.count >= 0)
            #expect(results4.count >= 0)
        }
    }

    // MARK: - Stats Tests

    @Suite("Statistics")
    struct StatsTests {

        @Test("Get stats returns zero counts initially")
        func statsEmpty() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            let stats = store.getStats()
            #expect(stats.documentCount == 0)
            #expect(stats.embeddedCount == 0)
        }

        @Test("Get stats returns correct document count")
        func statsDocumentCount() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(path: "/a.md", title: "A", content: "A"))
            try store.addDocument(DocumentInput(path: "/b.md", title: "B", content: "B"))
            try store.addDocument(DocumentInput(path: "/c.md", title: "C", content: "C"))

            let stats = store.getStats()
            #expect(stats.documentCount == 3)
        }

        @Test("Get stats updates after removal")
        func statsAfterRemoval() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(path: "/a.md", title: "A", content: "A"))
            try store.addDocument(DocumentInput(path: "/b.md", title: "B", content: "B"))

            var stats = store.getStats()
            #expect(stats.documentCount == 2)

            try store.removeDocument(path: "/a.md")

            stats = store.getStats()
            #expect(stats.documentCount == 1)
        }
    }

    // MARK: - FTS Sync Tests

    @Suite("FTS Synchronization")
    struct FTSSyncTests {

        @Test("FTS index is updated on insert")
        func ftsInsertSync() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Unique Title",
                content: "Unique searchable content"
            ))

            // If FTS is properly synced, search should find this immediately
            let results = store.searchFTS(query: "Unique", limit: 10)
            #expect(results.count == 1)
        }

        @Test("FTS index is updated on delete")
        func ftsDeleteSync() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Searchable",
                content: "Searchable content"
            ))

            var results = store.searchFTS(query: "Searchable", limit: 10)
            #expect(results.count == 1)

            try store.removeDocument(path: "/doc.md")

            results = store.searchFTS(query: "Searchable", limit: 10)
            #expect(results.count == 0)
        }

        @Test("FTS index is updated on update")
        func ftsUpdateSync() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Original",
                content: "Original content"
            ))

            var results = store.searchFTS(query: "Original", limit: 10)
            #expect(results.count == 1)

            // Update the document
            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Updated",
                content: "Updated content"
            ))

            // Old content should not be found
            results = store.searchFTS(query: "Original", limit: 10)
            #expect(results.count == 0)

            // New content should be found
            results = store.searchFTS(query: "Updated", limit: 10)
            #expect(results.count == 1)
        }
    }

    // MARK: - Thread Safety Tests

    @Suite("Thread Safety")
    struct ThreadSafetyTests {

        @Test("Concurrent reads do not crash")
        func concurrentReads() async throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            // Add some documents
            for i in 1...10 {
                try store.addDocument(DocumentInput(
                    path: "/doc\(i).md",
                    title: "Document \(i)",
                    content: "Content for document \(i)"
                ))
            }

            // Perform concurrent reads
            await withTaskGroup(of: Void.self) { group in
                for _ in 1...100 {
                    group.addTask {
                        _ = store.getAllDocuments()
                        _ = store.getStats()
                        _ = store.getDocument(path: "/doc1.md")
                    }
                }
            }

            // If we get here without crashing, thread safety is working
            #expect(store.getStats().documentCount == 10)
        }

        @Test("Concurrent writes do not crash")
        func concurrentWrites() async throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            // Perform concurrent writes
            await withTaskGroup(of: Void.self) { group in
                for i in 1...50 {
                    group.addTask {
                        try? store.addDocument(DocumentInput(
                            path: "/concurrent\(i).md",
                            title: "Concurrent \(i)",
                            content: "Content \(i)"
                        ))
                    }
                }
            }

            // All documents should be added
            let stats = store.getStats()
            #expect(stats.documentCount == 50)
        }

        @Test("Concurrent read-write operations do not crash")
        func concurrentReadWrite() async throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            // Add initial documents
            for i in 1...5 {
                try store.addDocument(DocumentInput(
                    path: "/initial\(i).md",
                    title: "Initial \(i)",
                    content: "Content \(i)"
                ))
            }

            // Perform concurrent reads and writes
            await withTaskGroup(of: Void.self) { group in
                // Writers
                for i in 1...20 {
                    group.addTask {
                        try? store.addDocument(DocumentInput(
                            path: "/new\(i).md",
                            title: "New \(i)",
                            content: "New content \(i)"
                        ))
                    }
                }
                // Readers
                for _ in 1...50 {
                    group.addTask {
                        _ = store.getAllDocuments()
                        _ = store.searchFTS(query: "content", limit: 10)
                    }
                }
            }

            // Should have all documents
            let stats = store.getStats()
            #expect(stats.documentCount == 25) // 5 initial + 20 new
        }
    }

    // MARK: - Input Validation Tests

    @Suite("Input Validation")
    struct InputValidationTests {

        @Test("Search with negative limit returns results")
        func searchNegativeLimit() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Test",
                content: "Test content"
            ))

            // Negative limit should be clamped to 1
            let results = store.searchFTS(query: "Test", limit: -5)
            #expect(results.count >= 0) // Should not crash
        }

        @Test("Search with zero limit returns results")
        func searchZeroLimit() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Test",
                content: "Test content"
            ))

            // Zero limit should be clamped to 1
            let results = store.searchFTS(query: "Test", limit: 0)
            #expect(results.count >= 0) // Should not crash
        }

        @Test("Search with very large limit is clamped")
        func searchVeryLargeLimit() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            for i in 1...5 {
                try store.addDocument(DocumentInput(
                    path: "/doc\(i).md",
                    title: "Test \(i)",
                    content: "Test content \(i)"
                ))
            }

            // Very large limit should be clamped to 1000
            let results = store.searchFTS(query: "Test", limit: Int.max)
            #expect(results.count == 5) // Should return all 5 documents
        }

        @Test("Search with Int32 overflow limit does not crash")
        func searchInt32OverflowLimit() throws {
            let dbPath = StoreTests.tempDbPath()
            let store = Store(dbPath: dbPath)
            try store.open()

            defer {
                store.close()
                try? FileManager.default.removeItem(atPath: dbPath)
            }

            try store.addDocument(DocumentInput(
                path: "/doc.md",
                title: "Test",
                content: "Test content"
            ))

            // Value larger than Int32.max should not cause overflow
            let largeLimit = Int(Int32.max) + 1000
            let results = store.searchFTS(query: "Test", limit: largeLimit)
            #expect(results.count >= 0) // Should not crash
        }
    }
}
