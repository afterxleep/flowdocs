import Testing
import Foundation
@testable import flowdocs

@Suite("Models Tests")
struct ModelsTests {

    // MARK: - Mode Tests

    @Suite("Mode Enum")
    struct ModeTests {

        @Test("Mode raw values are correct")
        func modeRawValues() {
            #expect(Mode.project.rawValue == "project")
            #expect(Mode.system.rawValue == "system")
        }

        @Test("Mode encodes to JSON correctly")
        func modeEncodesToJSON() throws {
            let encoder = JSONEncoder()

            let projectData = try encoder.encode(Mode.project)
            let projectString = String(data: projectData, encoding: .utf8)
            #expect(projectString == "\"project\"")

            let systemData = try encoder.encode(Mode.system)
            let systemString = String(data: systemData, encoding: .utf8)
            #expect(systemString == "\"system\"")
        }

        @Test("Mode decodes from JSON correctly")
        func modeDecodesFromJSON() throws {
            let decoder = JSONDecoder()

            let projectData = "\"project\"".data(using: .utf8)!
            let projectMode = try decoder.decode(Mode.self, from: projectData)
            #expect(projectMode == .project)

            let systemData = "\"system\"".data(using: .utf8)!
            let systemMode = try decoder.decode(Mode.self, from: systemData)
            #expect(systemMode == .system)
        }

        @Test("Mode fails to decode invalid value")
        func modeFailsInvalidDecode() {
            let decoder = JSONDecoder()
            let invalidData = "\"invalid\"".data(using: .utf8)!

            #expect(throws: DecodingError.self) {
                _ = try decoder.decode(Mode.self, from: invalidData)
            }
        }
    }

    // MARK: - Document Tests

    @Suite("Document")
    struct DocumentTests {

        @Test("Document can be created with all properties")
        func documentCreation() {
            let now = Date()
            let doc = Document(
                path: "/path/to/doc.md",
                title: "Test Document",
                content: "This is test content",
                contentHash: "abc123hash",
                updatedAt: now
            )

            #expect(doc.path == "/path/to/doc.md")
            #expect(doc.title == "Test Document")
            #expect(doc.content == "This is test content")
            #expect(doc.contentHash == "abc123hash")
            #expect(doc.updatedAt == now)
        }

        @Test("Document hash should be SHA-256 format (64 hex chars)")
        func documentHashFormat() {
            let validHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            let doc = Document(
                path: "/test.md",
                title: "Test",
                content: "",
                contentHash: validHash,
                updatedAt: Date()
            )

            #expect(doc.contentHash.count == 64)
            #expect(doc.contentHash.allSatisfy { $0.isHexDigit })
        }

        @Test("Document with empty content is valid")
        func documentEmptyContent() {
            let doc = Document(
                path: "/empty.md",
                title: "Empty",
                content: "",
                contentHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                updatedAt: Date()
            )

            #expect(doc.content.isEmpty)
            #expect(!doc.contentHash.isEmpty)
        }
    }

    // MARK: - SearchResult Tests

    @Suite("SearchResult")
    struct SearchResultTests {

        @Test("SearchResult can be created")
        func searchResultCreation() {
            let result = SearchResult(
                path: "/doc.md",
                title: "Found Document",
                score: 0.85,
                snippet: "...matching text..."
            )

            #expect(result.path == "/doc.md")
            #expect(result.title == "Found Document")
            #expect(result.score == 0.85)
            #expect(result.snippet == "...matching text...")
        }

        @Test("SearchResult score should be in valid range 0-1")
        func searchResultScoreRange() {
            let result1 = SearchResult(path: "/a.md", title: "A", score: 0.0, snippet: nil)
            let result2 = SearchResult(path: "/b.md", title: "B", score: 1.0, snippet: nil)
            let result3 = SearchResult(path: "/c.md", title: "C", score: 0.5, snippet: nil)

            #expect(result1.score >= 0.0 && result1.score <= 1.0)
            #expect(result2.score >= 0.0 && result2.score <= 1.0)
            #expect(result3.score >= 0.0 && result3.score <= 1.0)
        }

        @Test("SearchResult snippet can be nil")
        func searchResultNilSnippet() {
            let result = SearchResult(
                path: "/doc.md",
                title: "Document",
                score: 0.5,
                snippet: nil
            )

            #expect(result.snippet == nil)
        }

        @Test("SearchResult score is mutable")
        func searchResultScoreMutable() {
            var result = SearchResult(
                path: "/doc.md",
                title: "Document",
                score: 0.3,
                snippet: nil
            )

            result.score = 0.9
            #expect(result.score == 0.9)
        }

        @Test("SearchResult snippet is mutable")
        func searchResultSnippetMutable() {
            var result = SearchResult(
                path: "/doc.md",
                title: "Document",
                score: 0.5,
                snippet: nil
            )

            result.snippet = "New snippet"
            #expect(result.snippet == "New snippet")
        }
    }

    // MARK: - IndexStatus Tests

    @Suite("IndexStatus")
    struct IndexStatusTests {

        @Test("IndexStatus initializes with project mode")
        func indexStatusProjectMode() {
            let status = IndexStatus(
                mode: .project,
                indexPath: "/project/.flowdocs/index.db",
                documentCount: 10,
                embeddedCount: 5,
                lastUpdated: Date()
            )

            #expect(status.mode == .project)
            #expect(status.indexPath == "/project/.flowdocs/index.db")
            #expect(status.documentCount == 10)
            #expect(status.embeddedCount == 5)
            #expect(status.lastUpdated != nil)
        }

        @Test("IndexStatus initializes with system mode")
        func indexStatusSystemMode() {
            let status = IndexStatus(
                mode: .system,
                indexPath: "~/.flowdocs/index.db",
                documentCount: 100,
                embeddedCount: 50,
                lastUpdated: nil
            )

            #expect(status.mode == .system)
            #expect(status.indexPath == "~/.flowdocs/index.db")
            #expect(status.documentCount == 100)
            #expect(status.embeddedCount == 50)
            #expect(status.lastUpdated == nil)
        }

        @Test("IndexStatus with zero counts")
        func indexStatusZeroCounts() {
            let status = IndexStatus(
                mode: .project,
                indexPath: "/path/index.db",
                documentCount: 0,
                embeddedCount: 0,
                lastUpdated: nil
            )

            #expect(status.documentCount == 0)
            #expect(status.embeddedCount == 0)
        }

        @Test("IndexStatus lastUpdated is mutable")
        func indexStatusLastUpdatedMutable() {
            var status = IndexStatus(
                mode: .project,
                indexPath: "/path/index.db",
                documentCount: 0,
                embeddedCount: 0,
                lastUpdated: nil
            )

            let now = Date()
            status.lastUpdated = now
            #expect(status.lastUpdated == now)
        }
    }

    // MARK: - ProjectConfig Tests

    @Suite("ProjectConfig")
    struct ProjectConfigTests {

        @Test("ProjectConfig handles project mode with project root")
        func projectConfigProjectMode() {
            let config = ProjectConfig(
                mode: .project,
                indexPath: "/project/.flowdocs/index.db",
                projectRoot: "/project"
            )

            #expect(config.mode == .project)
            #expect(config.indexPath == "/project/.flowdocs/index.db")
            #expect(config.projectRoot == "/project")
        }

        @Test("ProjectConfig handles system mode without project root")
        func projectConfigSystemMode() {
            let config = ProjectConfig(
                mode: .system,
                indexPath: "~/.flowdocs/index.db",
                projectRoot: nil
            )

            #expect(config.mode == .system)
            #expect(config.indexPath == "~/.flowdocs/index.db")
            #expect(config.projectRoot == nil)
        }

        @Test("ProjectConfig projectRoot is mutable")
        func projectConfigProjectRootMutable() {
            var config = ProjectConfig(
                mode: .project,
                indexPath: "/path/index.db",
                projectRoot: nil
            )

            config.projectRoot = "/new/project/root"
            #expect(config.projectRoot == "/new/project/root")
        }

        @Test("ProjectConfig can change project root")
        func projectConfigChangeRoot() {
            var config = ProjectConfig(
                mode: .project,
                indexPath: "/project/.flowdocs/index.db",
                projectRoot: "/old/project"
            )

            config.projectRoot = "/new/project"
            #expect(config.projectRoot == "/new/project")
        }
    }
}
