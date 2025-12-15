import Testing
import Foundation
@testable import flowdocs

@Suite("CLI Tests")
struct CLITests {

    // Helper to create temporary test directories
    static func tempDir() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("flowdocs_cli_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir.path
    }

    // Helper to clean up a directory
    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // Helper to create a markdown file
    static func createMarkdownFile(at path: String, title: String, content: String) throws {
        let fullContent = "# \(title)\n\n\(content)"
        let dirPath = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        try fullContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - extractTitle Tests

    @Suite("extractTitle")
    struct ExtractTitleTests {

        @Test("Extracts H1 title from markdown")
        func extractsH1Title() {
            let content = "# My Document Title\n\nSome content here."
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "My Document Title")
        }

        @Test("Extracts H1 title with # at start of content")
        func extractsH1AtStart() {
            let content = "# Getting Started\n\nWelcome to the guide."
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "Getting Started")
        }

        @Test("Returns fallback when no H1 found")
        func returnsFallbackWhenNoH1() {
            let content = "Some content without a title.\n\n## Subheading"
            let title = extractTitle(from: content, fallback: "my-file.md")
            #expect(title == "my-file.md")
        }

        @Test("Returns fallback for empty content")
        func returnsFallbackForEmpty() {
            let title = extractTitle(from: "", fallback: "fallback")
            #expect(title == "fallback")
        }

        @Test("Ignores H2 and other headings")
        func ignoresNonH1Headings() {
            let content = "## Not H1\n\n### Also not H1\n\nContent"
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "default")
        }

        @Test("Extracts first H1 when multiple exist")
        func extractsFirstH1() {
            let content = "# First Title\n\n# Second Title\n\nContent"
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "First Title")
        }

        @Test("Trims whitespace from title")
        func trimsWhitespace() {
            let content = "#   Title with spaces   \n\nContent"
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "Title with spaces")
        }

        @Test("Handles H1 not at start of file")
        func handlesH1NotAtStart() {
            let content = "Some intro text.\n\n# The Real Title\n\nContent"
            let title = extractTitle(from: content, fallback: "default")
            #expect(title == "The Real Title")
        }
    }

    // MARK: - addFile Tests

    @Suite("addFile")
    struct AddFileTests {

        @Test("Adds a single markdown file to store")
        func addsSingleFile() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create test file
            let filePath = (testDir as NSString).appendingPathComponent("docs/test.md")
            try CLITests.createMarkdownFile(at: filePath, title: "Test Document", content: "Test content")

            // Create store
            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            // Add file
            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == true)

            // Verify document was added
            let doc = store.getDocument(path: "docs/test.md")
            #expect(doc != nil)
            #expect(doc?.title == "Test Document")
        }

        @Test("Returns false for non-existent file")
        func returnsFalseForNonExistent() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let filePath = (testDir as NSString).appendingPathComponent("nonexistent.md")
            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == false)
        }

        @Test("Returns false for non-markdown file")
        func returnsFalseForNonMarkdown() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create non-markdown file
            let filePath = (testDir as NSString).appendingPathComponent("file.txt")
            try "Some text content".write(toFile: filePath, atomically: true, encoding: .utf8)

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == false)
        }

        @Test("Accepts .markdown extension")
        func acceptsMarkdownExtension() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            let filePath = (testDir as NSString).appendingPathComponent("doc.markdown")
            try CLITests.createMarkdownFile(at: filePath, title: "Markdown File", content: "Content")

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == true)
        }

        @Test("Uses filename as title fallback")
        func usesFilenameFallback() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create file without H1 heading
            let filePath = (testDir as NSString).appendingPathComponent("my-document.md")
            try "Just some content without a heading".write(toFile: filePath, atomically: true, encoding: .utf8)

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == true)

            let doc = store.getDocument(path: "my-document.md")
            #expect(doc?.title == "my-document.md")
        }

        @Test("Stores relative path from base directory")
        func storesRelativePath() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            let filePath = (testDir as NSString).appendingPathComponent("docs/guides/intro.md")
            try CLITests.createMarkdownFile(at: filePath, title: "Introduction", content: "Welcome")

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)

            #expect(added == true)

            // Path should be relative
            let doc = store.getDocument(path: "docs/guides/intro.md")
            #expect(doc != nil)
        }
    }

    // MARK: - addDirectory Tests

    @Suite("addDirectory")
    struct AddDirectoryTests {

        @Test("Recursively indexes markdown files in directory")
        func indexesRecursively() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create directory structure with markdown files
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/guide.md"),
                title: "Guide",
                content: "Guide content"
            )
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/api/reference.md"),
                title: "API Reference",
                content: "API content"
            )
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("readme.md"),
                title: "README",
                content: "Readme content"
            )

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let docsDir = (testDir as NSString).appendingPathComponent("docs")
            let count = try addDirectory(store: store, dirPath: docsDir, baseDir: testDir)

            #expect(count == 2) // guide.md and api/reference.md
        }

        @Test("Skips non-markdown files")
        func skipsNonMarkdown() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create mixed files
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/guide.md"),
                title: "Guide",
                content: "Content"
            )
            try "Text content".write(
                toFile: (testDir as NSString).appendingPathComponent("docs/notes.txt"),
                atomically: true,
                encoding: .utf8
            )
            try "JSON content".write(
                toFile: (testDir as NSString).appendingPathComponent("docs/config.json"),
                atomically: true,
                encoding: .utf8
            )

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let count = try addDirectory(store: store, dirPath: testDir, baseDir: testDir)

            #expect(count == 1) // Only guide.md
        }

        @Test("Skips hidden directories")
        func skipsHiddenDirs() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create files in hidden and non-hidden directories
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/visible.md"),
                title: "Visible",
                content: "Content"
            )
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent(".hidden/secret.md"),
                title: "Secret",
                content: "Secret content"
            )

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let count = try addDirectory(store: store, dirPath: testDir, baseDir: testDir)

            #expect(count == 1) // Only visible.md

            // Verify hidden file was not indexed
            let hidden = store.getDocument(path: ".hidden/secret.md")
            #expect(hidden == nil)
        }

        @Test("Returns 0 for empty directory")
        func returnsZeroForEmpty() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let count = try addDirectory(store: store, dirPath: testDir, baseDir: testDir)

            #expect(count == 0)
        }

        @Test("Returns 0 for non-existent directory")
        func returnsZeroForNonExistent() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            let nonExistent = (testDir as NSString).appendingPathComponent("nonexistent")
            let count = try addDirectory(store: store, dirPath: nonExistent, baseDir: testDir)

            #expect(count == 0)
        }
    }

    // MARK: - isMarkdownFile Tests

    @Suite("isMarkdownFile")
    struct IsMarkdownFileTests {

        @Test("Returns true for .md extension")
        func acceptsMdExtension() {
            #expect(isMarkdownFile("document.md") == true)
            #expect(isMarkdownFile("/path/to/file.md") == true)
        }

        @Test("Returns true for .markdown extension")
        func acceptsMarkdownExtension() {
            #expect(isMarkdownFile("document.markdown") == true)
            #expect(isMarkdownFile("/path/to/file.markdown") == true)
        }

        @Test("Returns false for other extensions")
        func rejectsOtherExtensions() {
            #expect(isMarkdownFile("document.txt") == false)
            #expect(isMarkdownFile("document.html") == false)
            #expect(isMarkdownFile("document.json") == false)
            #expect(isMarkdownFile("document.swift") == false)
        }

        @Test("Is case insensitive")
        func caseInsensitive() {
            #expect(isMarkdownFile("document.MD") == true)
            #expect(isMarkdownFile("document.Md") == true)
            #expect(isMarkdownFile("document.MARKDOWN") == true)
        }

        @Test("Returns false for files with no extension")
        func rejectsNoExtension() {
            #expect(isMarkdownFile("README") == false)
            #expect(isMarkdownFile("/path/to/file") == false)
        }
    }

    // MARK: - isHiddenPath Tests

    @Suite("isHiddenPath")
    struct IsHiddenPathTests {

        @Test("Returns true for paths starting with dot")
        func hiddenWithDot() {
            #expect(isHiddenPath(".hidden") == true)
            #expect(isHiddenPath(".git") == true)
            #expect(isHiddenPath(".flowdocs") == true)
        }

        @Test("Returns true for paths containing hidden directory")
        func pathContainingHidden() {
            #expect(isHiddenPath("/project/.git/config") == true)
            #expect(isHiddenPath("/project/.hidden/file.md") == true)
        }

        @Test("Returns false for visible paths")
        func visiblePaths() {
            #expect(isHiddenPath("docs") == false)
            #expect(isHiddenPath("/project/docs/guide.md") == false)
            #expect(isHiddenPath("readme.md") == false)
        }

        @Test("Returns false for paths with dots in filenames")
        func dotsInFilenames() {
            #expect(isHiddenPath("file.config.md") == false)
            #expect(isHiddenPath("/project/docs/v1.0.md") == false)
        }
    }

    // MARK: - CLI Integration Tests

    @Suite("CLI Integration")
    struct CLIIntegrationTests {

        @Test("Full workflow: init, add, search, get, remove")
        func fullWorkflow() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // 1. Initialize project
            let config = try Project.initProject(at: testDir)
            #expect(config.mode == .project)

            // 2. Create test markdown files
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/swift-guide.md"),
                title: "Swift Programming Guide",
                content: "Swift is a powerful and intuitive programming language for Apple platforms."
            )
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("docs/api/networking.md"),
                title: "Networking API",
                content: "Use URLSession for network requests in Swift applications."
            )

            // 3. Open store and add files
            let store = Store(dbPath: config.indexPath)
            try store.open()
            defer { store.close() }

            let count = try addDirectory(store: store, dirPath: testDir, baseDir: testDir)
            #expect(count == 2)

            // 4. Search for documents
            let search = Search(store: store)
            let results = search.search(query: "Swift", limit: 10)
            #expect(results.count == 2)

            // 5. Get document content
            let doc = store.getDocument(path: "docs/swift-guide.md")
            #expect(doc != nil)
            #expect(doc?.content.contains("Swift is a powerful") == true)

            // 6. Remove document
            try store.removeDocument(path: "docs/swift-guide.md")
            let removed = store.getDocument(path: "docs/swift-guide.md")
            #expect(removed == nil)

            // 7. Verify search no longer finds removed document
            // Search for "Swift" - should now only find the networking doc
            let resultsAfter = search.search(query: "Swift applications", limit: 10)
            #expect(resultsAfter.count == 1)
        }

        @Test("Status reflects correct document count")
        func statusReflectsCount() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            _ = try Project.initProject(at: testDir)

            // Create test files
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("a.md"),
                title: "A",
                content: "Content A"
            )
            try CLITests.createMarkdownFile(
                at: (testDir as NSString).appendingPathComponent("b.md"),
                title: "B",
                content: "Content B"
            )

            let config = Project.getProjectConfig(options: ModeOptions(cwd: testDir))
            let store = Store(dbPath: config.indexPath)
            try store.open()
            defer { store.close() }

            _ = try addDirectory(store: store, dirPath: testDir, baseDir: testDir)

            let stats = store.getStats()
            #expect(stats.documentCount == 2)
        }
    }

    // MARK: - Path Validation Tests

    @Suite("Path Validation in CLI")
    struct PathValidationTests {

        @Test("Rejects path traversal in addFile")
        func rejectsPathTraversalInAddFile() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create a file outside the project
            let outsideDir = CLITests.tempDir()
            defer { CLITests.cleanup(outsideDir) }

            let outsideFile = (outsideDir as NSString).appendingPathComponent("secret.md")
            try CLITests.createMarkdownFile(at: outsideFile, title: "Secret", content: "Secret content")

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            // Try to add file outside project - should fail validation
            let added = try addFile(store: store, filePath: outsideFile, baseDir: testDir)
            #expect(added == false)
        }

        @Test("Validates path before indexing")
        func validatesPathBeforeIndexing() throws {
            let testDir = CLITests.tempDir()
            defer { CLITests.cleanup(testDir) }

            // Create file with path traversal attempt
            let filePath = (testDir as NSString).appendingPathComponent("docs/../../../etc/passwd")

            let dbPath = (testDir as NSString).appendingPathComponent("test.db")
            let store = Store(dbPath: dbPath)
            try store.open()
            defer { store.close() }

            // Should handle path traversal safely
            let added = try addFile(store: store, filePath: filePath, baseDir: testDir)
            #expect(added == false)
        }
    }
}
