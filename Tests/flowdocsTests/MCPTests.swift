import Testing
import Foundation
@testable import flowdocs

@Suite("MCP Server Tests")
struct MCPTests {

    // Helper to create a temporary directory for testing
    static func createTempDir() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowdocs_mcp_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.path
    }

    // Helper to clean up temp directory
    static func cleanupTempDir(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // Helper to create an initialized project
    static func createInitializedProject() throws -> (tempDir: String, server: MCPServer) {
        let tempDir = try createTempDir()
        let server = MCPServer(cwd: tempDir)

        // Initialize the project
        let flowdocsPath = (tempDir as NSString).appendingPathComponent(".flowdocs")
        try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

        return (tempDir, server)
    }

    // MARK: - JSON-RPC Request Parsing Tests

    @Suite("JSON-RPC Request Parsing")
    struct RequestParsingTests {

        @Test("Parse valid initialize request")
        func parseInitializeRequest() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"jsonrpc\":\"2.0\""))
            #expect(response.contains("\"id\":1"))
            #expect(response.contains("protocolVersion"))
            #expect(response.contains("flowdocs"))
        }

        @Test("Parse valid tools/list request")
        func parseToolsListRequest() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":2,"method":"tools/list"}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"tools\""))
            #expect(response.contains("\"id\":2"))
        }

        @Test("Parse valid tools/call request")
        func parseToolsCallRequest() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let json = """
            {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"status","arguments":{}}}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"id\":3"))
            #expect(response.contains("\"content\""))
        }

        @Test("Parse request with null id")
        func parseRequestWithNullId() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":null,"method":"initialize"}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"id\":null"))
        }

        @Test("Throw error for invalid JSON")
        func parseInvalidJSON() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = "not valid json"

            #expect(throws: Error.self) {
                _ = try server.handleRequest(json)
            }
        }
    }

    // MARK: - ListTools Response Tests

    @Suite("ListTools Response")
    struct ListToolsTests {

        @Test("Returns all tool definitions")
        func returnsAllTools() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let tools = server.getToolDefinitions()

            let toolNames = tools.compactMap { $0["name"] as? String }
            #expect(toolNames.contains("init"))
            #expect(toolNames.contains("add"))
            #expect(toolNames.contains("create"))
            #expect(toolNames.contains("search"))
            #expect(toolNames.contains("get"))
            #expect(toolNames.contains("status"))
            #expect(toolNames.contains("remove"))
        }

        @Test("Each tool has name, description, and inputSchema")
        func toolsHaveRequiredFields() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let tools = server.getToolDefinitions()

            for tool in tools {
                #expect(tool["name"] != nil)
                #expect(tool["description"] != nil)
                #expect(tool["inputSchema"] != nil)
            }
        }

        @Test("tools/list returns proper JSON-RPC response")
        func toolsListResponse() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"tools/list"}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"jsonrpc\":\"2.0\""))
            #expect(response.contains("\"id\":1"))
            #expect(response.contains("\"result\""))
            #expect(response.contains("\"tools\""))
        }
    }

    // MARK: - CallTool Dispatch Tests

    @Suite("CallTool Dispatch")
    struct CallToolDispatchTests {

        @Test("Dispatch to init tool")
        func dispatchInit() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let result = try server.callTool(name: "init", arguments: [:])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to add tool")
        func dispatchAdd() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Create a test markdown file
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test\nContent".write(toFile: testFile, atomically: true, encoding: .utf8)

            let result = try server.callTool(name: "add", arguments: ["path": "test.md"])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to create tool")
        func dispatchCreate() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "create", arguments: [
                "path": "docs/new.md",
                "content": "# New Document\nThis is new content."
            ])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to search tool")
        func dispatchSearch() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "search", arguments: ["query": "test"])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to get tool")
        func dispatchGet() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // First add a document
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test\nContent".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.callTool(name: "add", arguments: ["path": "test.md"])

            let result = try server.callTool(name: "get", arguments: ["path": "test.md"])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to status tool")
        func dispatchStatus() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "status", arguments: [:])

            #expect(result["content"] != nil)
        }

        @Test("Dispatch to remove tool")
        func dispatchRemove() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // First add a document
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test\nContent".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.callTool(name: "add", arguments: ["path": "test.md"])

            let result = try server.callTool(name: "remove", arguments: ["path": "test.md"])

            #expect(result["content"] != nil)
        }

        @Test("Unknown tool returns error")
        func dispatchUnknownTool() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let result = try server.callTool(name: "unknown_tool", arguments: [:])

            #expect(result["isError"] as? Bool == true)
        }
    }

    // MARK: - Tool Implementation Tests

    @Suite("Tool Implementations")
    struct ToolImplementationTests {

        // MARK: - Init Tool

        @Test("Init creates .flowdocs directory")
        func initCreatesFlowdocsDir() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            _ = try server.toolInit()

            let flowdocsPath = (tempDir as NSString).appendingPathComponent(".flowdocs")
            #expect(FileManager.default.fileExists(atPath: flowdocsPath))
        }

        @Test("Init returns success message")
        func initReturnsSuccess() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let result = try server.toolInit()

            let content = result["content"] as? [[String: Any]]
            #expect(content != nil)

            let text = content?.first?["text"] as? String
            #expect(text?.contains("Initialized") == true || text?.contains("initialized") == true)
        }

        @Test("Init returns message when already initialized")
        func initAlreadyInitialized() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolInit()

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.lowercased().contains("already") == true)
        }

        // MARK: - Add Tool

        @Test("Add indexes markdown file")
        func addIndexesMarkdown() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Create test file
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test Title\nTest content".write(toFile: testFile, atomically: true, encoding: .utf8)

            let result = try server.toolAdd(path: "test.md")

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.lowercased().contains("added") == true)
        }

        @Test("Add returns error for non-existent file")
        func addNonExistentFile() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolAdd(path: "nonexistent.md")

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Add indexes directory recursively")
        func addIndexesDirectory() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Create test directory with files
            let docsDir = (tempDir as NSString).appendingPathComponent("docs")
            try FileManager.default.createDirectory(atPath: docsDir, withIntermediateDirectories: true)

            try "# Doc 1\nContent 1".write(toFile: (docsDir as NSString).appendingPathComponent("doc1.md"), atomically: true, encoding: .utf8)
            try "# Doc 2\nContent 2".write(toFile: (docsDir as NSString).appendingPathComponent("doc2.md"), atomically: true, encoding: .utf8)

            let result = try server.toolAdd(path: "docs")

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("2") == true) // Should add 2 documents
        }

        // MARK: - Create Tool

        @Test("Create creates new document")
        func createCreatesDocument() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolCreate(path: "new-doc.md", content: "# New Doc\nContent")

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.lowercased().contains("created") == true)

            // Verify file exists
            let filePath = (tempDir as NSString).appendingPathComponent("new-doc.md")
            #expect(FileManager.default.fileExists(atPath: filePath))
        }

        @Test("Create creates parent directories")
        func createCreatesParentDirs() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolCreate(path: "docs/guides/new-doc.md", content: "# New Doc\nContent")

            #expect(result["isError"] as? Bool != true)

            // Verify file exists
            let filePath = (tempDir as NSString).appendingPathComponent("docs/guides/new-doc.md")
            #expect(FileManager.default.fileExists(atPath: filePath))
        }

        @Test("Create adds document to index")
        func createAddsToIndex() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            _ = try server.toolCreate(path: "indexed-doc.md", content: "# Indexed\nSearchable content here")

            // Should be able to search for it
            let searchResult = try server.toolSearch(query: "Searchable", limit: 10)
            let content = searchResult["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("indexed-doc.md") == true || text?.contains("Indexed") == true)
        }

        // MARK: - Search Tool

        @Test("Search returns results")
        func searchReturnsResults() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Add some documents
            let testFile = (tempDir as NSString).appendingPathComponent("swift-guide.md")
            try "# Swift Guide\nSwift programming language tutorial".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.toolAdd(path: "swift-guide.md")

            let result = try server.toolSearch(query: "Swift", limit: 10)

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("swift-guide") == true || text?.contains("Swift") == true)
        }

        @Test("Search returns no results message when empty")
        func searchNoResults() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolSearch(query: "nonexistent_query_xyz", limit: 10)

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.lowercased().contains("no") == true)
        }

        @Test("Search respects limit")
        func searchRespectsLimit() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Add multiple documents
            for i in 1...5 {
                let filePath = (tempDir as NSString).appendingPathComponent("doc\(i).md")
                try "# Document \(i)\nSwift content".write(toFile: filePath, atomically: true, encoding: .utf8)
                _ = try server.toolAdd(path: "doc\(i).md")
            }

            let result = try server.toolSearch(query: "Swift", limit: 2)

            // Result should contain limited results
            #expect(result["content"] != nil)
        }

        // MARK: - Get Tool

        @Test("Get retrieves document content")
        func getRetrievesContent() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Add a document
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test Title\nThis is the content.".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.toolAdd(path: "test.md")

            let result = try server.toolGet(path: "test.md")

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("This is the content") == true)
        }

        @Test("Get returns error for non-existent document")
        func getNonExistent() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolGet(path: "nonexistent.md")

            #expect(result["isError"] as? Bool == true)
        }

        // MARK: - Status Tool

        @Test("Status returns index information")
        func statusReturnsInfo() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolStatus()

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("Mode") == true || text?.contains("mode") == true)
            #expect(text?.contains("Document") == true || text?.contains("document") == true)
        }

        @Test("Status shows document count")
        func statusShowsCount() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Add some documents
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test\nContent".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.toolAdd(path: "test.md")

            let result = try server.toolStatus()

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.contains("1") == true)
        }

        // MARK: - Remove Tool

        @Test("Remove deletes document from index")
        func removeDeletesDocument() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Add a document
            let testFile = (tempDir as NSString).appendingPathComponent("test.md")
            try "# Test\nContent".write(toFile: testFile, atomically: true, encoding: .utf8)
            _ = try server.toolAdd(path: "test.md")

            let result = try server.toolRemove(path: "test.md")

            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            #expect(text?.lowercased().contains("removed") == true)
        }

        @Test("Remove returns error for non-existent document")
        func removeNonExistent() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.toolRemove(path: "nonexistent.md")

            #expect(result["isError"] as? Bool == true)
        }
    }

    // MARK: - Error Response Tests

    @Suite("Error Responses")
    struct ErrorResponseTests {

        @Test("Error response has correct format")
        func errorResponseFormat() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let errorResponse = server.makeErrorResponse(id: 5, code: -32601, message: "Method not found")

            #expect(errorResponse.contains("\"jsonrpc\":\"2.0\""))
            #expect(errorResponse.contains("\"id\":5"))
            #expect(errorResponse.contains("\"error\""))
            #expect(errorResponse.contains("-32601"))
            #expect(errorResponse.contains("Method not found"))
        }

        @Test("Error response with null id")
        func errorResponseNullId() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let errorResponse = server.makeErrorResponse(id: nil, code: -32700, message: "Parse error")

            #expect(errorResponse.contains("\"id\":null"))
        }
    }

    // MARK: - Invalid Method Handling Tests

    @Suite("Invalid Method Handling")
    struct InvalidMethodTests {

        @Test("Unknown method returns error")
        func unknownMethodError() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"unknown/method"}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"error\""))
            #expect(response.contains("-32601"))
        }

        @Test("Empty method returns error")
        func emptyMethodError() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":1,"method":""}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"error\""))
        }
    }

    // MARK: - Missing Required Arguments Tests

    @Suite("Missing Required Arguments")
    struct MissingArgumentsTests {

        @Test("tools/call without tool name returns error")
        func missingToolName() throws {
            let tempDir = try MCPTests.createTempDir()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let server = MCPServer(cwd: tempDir)
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}
            """

            let response = try server.handleRequest(json)
            #expect(response.contains("\"error\""))
            #expect(response.contains("-32602"))
        }

        @Test("Add tool without path returns error")
        func addMissingPath() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "add", arguments: [:])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Create tool without path returns error")
        func createMissingPath() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "create", arguments: ["content": "test"])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Create tool without content returns error")
        func createMissingContent() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "create", arguments: ["path": "test.md"])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Search tool without query returns error")
        func searchMissingQuery() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "search", arguments: [:])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Get tool without path returns error")
        func getMissingPath() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "get", arguments: [:])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Remove tool without path returns error")
        func removeMissingPath() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "remove", arguments: [:])

            #expect(result["isError"] as? Bool == true)
        }
    }

    // MARK: - Security Tests

    @Suite("Security Validation")
    struct SecurityTests {

        @Test("Reject query exceeding max length")
        func rejectLongQuery() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let longQuery = String(repeating: "a", count: 10001) // Exceeds 10,000 char limit
            let result = try server.toolSearch(query: longQuery, limit: 10)

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Validate path argument is string")
        func validatePathIsString() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            // Try passing a non-string value
            let result = try server.callTool(name: "add", arguments: ["path": 123])

            #expect(result["isError"] as? Bool == true)
        }

        @Test("Reject path traversal in add")
        func rejectPathTraversalInAdd() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "add", arguments: ["path": "../../../etc/passwd"])

            // Should either error or not add anything outside project
            let content = result["content"] as? [[String: Any]]
            let text = content?.first?["text"] as? String
            let isError = result["isError"] as? Bool ?? false

            // Either returns an error or doesn't find the file
            #expect(isError || text?.lowercased().contains("error") == true || text?.lowercased().contains("not") == true)
        }

        @Test("Reject path traversal in create")
        func rejectPathTraversalInCreate() throws {
            let (tempDir, server) = try MCPTests.createInitializedProject()
            defer { MCPTests.cleanupTempDir(tempDir) }

            let result = try server.callTool(name: "create", arguments: [
                "path": "../../../tmp/evil.md",
                "content": "evil content"
            ])

            #expect(result["isError"] as? Bool == true)
        }
    }

    // MARK: - AnyCodable Tests

    @Suite("AnyCodable Encoding/Decoding")
    struct AnyCodableTests {

        @Test("Encode and decode string")
        func stringEncodeDecode() throws {
            let original = AnyCodable("test string")
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            #expect(decoded.value as? String == "test string")
        }

        @Test("Encode and decode integer")
        func intEncodeDecode() throws {
            let original = AnyCodable(42)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            #expect(decoded.value as? Int == 42)
        }

        @Test("Encode and decode double")
        func doubleEncodeDecode() throws {
            let original = AnyCodable(3.14)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            #expect(decoded.value as? Double == 3.14)
        }

        @Test("Encode and decode boolean")
        func boolEncodeDecode() throws {
            let original = AnyCodable(true)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            #expect(decoded.value as? Bool == true)
        }

        @Test("Encode and decode array")
        func arrayEncodeDecode() throws {
            let original = AnyCodable([1, 2, 3])
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            let array = decoded.value as? [Any]
            #expect(array?.count == 3)
        }

        @Test("Encode and decode dictionary")
        func dictEncodeDecode() throws {
            let original = AnyCodable(["key": "value"])
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)

            let dict = decoded.value as? [String: Any]
            #expect(dict?["key"] as? String == "value")
        }
    }

    // MARK: - JSON-RPC Structures Tests

    @Suite("JSON-RPC Structures")
    struct JSONRPCStructuresTests {

        @Test("JSONRPCRequest decodes correctly")
        func requestDecoding() throws {
            let json = """
            {"jsonrpc":"2.0","id":1,"method":"test","params":{"name":"tool","arguments":{"key":"value"}}}
            """

            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))

            #expect(request.jsonrpc == "2.0")
            #expect(request.id == 1)
            #expect(request.method == "test")
            #expect(request.params?.name == "tool")
        }

        @Test("JSONRPCResponse encodes correctly")
        func responseEncoding() throws {
            let response = JSONRPCResponse(id: 1, result: AnyCodable(["test": "value"]), error: nil)
            let encoded = try JSONEncoder().encode(response)
            let json = String(data: encoded, encoding: .utf8)

            #expect(json?.contains("\"jsonrpc\":\"2.0\"") == true)
            #expect(json?.contains("\"id\":1") == true)
            #expect(json?.contains("\"result\"") == true)
        }

        @Test("JSONRPCError encodes correctly")
        func errorEncoding() throws {
            let error = JSONRPCError(code: -32600, message: "Invalid Request")
            let encoded = try JSONEncoder().encode(error)
            let json = String(data: encoded, encoding: .utf8)

            #expect(json?.contains("-32600") == true)
            #expect(json?.contains("Invalid Request") == true)
        }
    }
}
