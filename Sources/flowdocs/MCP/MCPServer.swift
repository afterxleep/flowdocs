import Foundation

// MARK: - JSON-RPC 2.0 Structures

/// JSON-RPC 2.0 request structure
struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: Int?
    let method: String
    let params: JSONRPCParams?
}

/// Parameters for JSON-RPC requests
struct JSONRPCParams: Codable {
    let name: String?
    let arguments: [String: AnyCodable]?
}

/// JSON-RPC 2.0 response structure
struct JSONRPCResponse: Encodable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?

    init(id: Int?, result: AnyCodable?, error: JSONRPCError?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)

        // Always encode id field (including as null) per JSON-RPC 2.0 spec
        try container.encode(id, forKey: .id)

        if let result = result {
            try container.encode(result, forKey: .result)
        }
        if let error = error {
            try container.encode(error, forKey: .error)
        }
    }
}

/// JSON-RPC 2.0 error structure
struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

// MARK: - AnyCodable

/// A type-erased Codable wrapper for handling dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            // Check Bool before Int because JSON booleans can be decoded as Int
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - MCP Server

/// MCP (Model Context Protocol) Server
/// Communicates via JSON-RPC 2.0 over stdin/stdout
final class MCPServer: @unchecked Sendable {

    // MARK: - Constants

    /// Maximum allowed query length for security
    static let maxQueryLength = 10_000

    // MARK: - Properties

    let cwd: String
    private var store: Store?
    private let storeLock = NSLock()

    /// Signal sources for graceful shutdown
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    // MARK: - Initialization

    init(cwd: String = FileManager.default.currentDirectoryPath) {
        self.cwd = cwd
    }

    deinit {
        // Cancel signal sources
        sigintSource?.cancel()
        sigtermSource?.cancel()

        // Close the store if open
        storeLock.lock()
        store?.close()
        store = nil
        storeLock.unlock()
    }

    // MARK: - Server Lifecycle

    /// Run the server - reads JSON-RPC requests from stdin, responds to stdout
    func run() throws {
        // Set up signal handling for graceful shutdown using DispatchSourceSignal
        // This is safer than using signal() as it allows proper cleanup
        setupSignalHandling()

        while let line = readLine() {
            guard !line.isEmpty else { continue }

            do {
                let response = try handleRequest(line)
                print(response)
                fflush(stdout)
            } catch {
                let errorResponse = makeErrorResponse(id: nil, code: -32700, message: "Parse error")
                print(errorResponse)
                fflush(stdout)
            }
        }
    }

    /// Set up signal handling for graceful shutdown
    private func setupSignalHandling() {
        // Ignore default signal handlers
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        // Create dispatch sources for signals
        sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        let shutdownHandler: () -> Void = { [weak self] in
            // Close the store before exiting
            self?.storeLock.lock()
            self?.store?.close()
            self?.store = nil
            self?.storeLock.unlock()
            exit(0)
        }

        sigintSource?.setEventHandler(handler: shutdownHandler)
        sigtermSource?.setEventHandler(handler: shutdownHandler)

        sigintSource?.resume()
        sigtermSource?.resume()
    }

    // MARK: - Request Handling

    /// Handle a single JSON-RPC request
    /// - Parameter json: The JSON-RPC request string
    /// - Returns: JSON-RPC response string
    func handleRequest(_ json: String) throws -> String {
        let decoder = JSONDecoder()
        let request = try decoder.decode(JSONRPCRequest.self, from: Data(json.utf8))

        switch request.method {
        case "initialize":
            return makeResponse(id: request.id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "flowdocs", "version": "1.0.0"]
            ])

        case "tools/list":
            return makeResponse(id: request.id, result: ["tools": getToolDefinitions()])

        case "tools/call":
            guard let name = request.params?.name else {
                return makeErrorResponse(id: request.id, code: -32602, message: "Missing tool name")
            }
            let args = request.params?.arguments?.mapValues { $0.value } ?? [:]
            let result = try callTool(name: name, arguments: args)
            return makeResponse(id: request.id, result: result)

        case "":
            return makeErrorResponse(id: request.id, code: -32601, message: "Method not found")

        default:
            return makeErrorResponse(id: request.id, code: -32601, message: "Method not found")
        }
    }

    // MARK: - Tool Definitions

    /// Get tool definitions for tools/list
    /// - Returns: Array of tool definition dictionaries
    func getToolDefinitions() -> [[String: Any]] {
        return [
            [
                "name": "init",
                "description": "Initialize flowdocs in the current project directory",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "add",
                "description": "Add a file or directory to the documentation index",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "File or directory path to index"
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "create",
                "description": "Create a new markdown document and add it to the index",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Path for the new document"
                        ],
                        "content": [
                            "type": "string",
                            "description": "Markdown content"
                        ]
                    ],
                    "required": ["path", "content"]
                ]
            ],
            [
                "name": "search",
                "description": "Search documentation",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query"
                        ],
                        "limit": [
                            "type": "number",
                            "description": "Maximum results (default: 10)"
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "get",
                "description": "Retrieve the full content of a document",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Document path"
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "status",
                "description": "Get the status of the documentation index",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "remove",
                "description": "Remove a document from the index",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Document path to remove"
                        ]
                    ],
                    "required": ["path"]
                ]
            ]
        ]
    }

    // MARK: - Tool Dispatch

    /// Call a tool by name with arguments
    /// - Parameters:
    ///   - name: The tool name
    ///   - arguments: Dictionary of arguments
    /// - Returns: Tool result dictionary with content array
    func callTool(name: String, arguments: [String: Any]) throws -> [String: Any] {
        switch name {
        case "init":
            return try toolInit()

        case "add":
            guard let path = arguments["path"] as? String else {
                return makeToolError("Missing required argument: path")
            }
            return try toolAdd(path: path)

        case "create":
            guard let path = arguments["path"] as? String else {
                return makeToolError("Missing required argument: path")
            }
            guard let content = arguments["content"] as? String else {
                return makeToolError("Missing required argument: content")
            }
            return try toolCreate(path: path, content: content)

        case "search":
            guard let query = arguments["query"] as? String else {
                return makeToolError("Missing required argument: query")
            }
            let limit = (arguments["limit"] as? Int) ?? 10
            return try toolSearch(query: query, limit: limit)

        case "get":
            guard let path = arguments["path"] as? String else {
                return makeToolError("Missing required argument: path")
            }
            return try toolGet(path: path)

        case "status":
            return try toolStatus()

        case "remove":
            guard let path = arguments["path"] as? String else {
                return makeToolError("Missing required argument: path")
            }
            return try toolRemove(path: path)

        default:
            return makeToolError("Unknown tool: \(name)")
        }
    }

    // MARK: - Tool Implementations

    /// Initialize flowdocs in the current directory
    func toolInit() throws -> [String: Any] {
        let flowdocsPath = (cwd as NSString).appendingPathComponent(flowdocsDir)

        // Check if already initialized
        if FileManager.default.fileExists(atPath: flowdocsPath) {
            return makeToolSuccess("Already initialized at \(flowdocsPath)")
        }

        // Create .flowdocs directory
        do {
            try FileManager.default.createDirectory(
                atPath: flowdocsPath,
                withIntermediateDirectories: true
            )
        } catch {
            return makeToolError("Failed to create directory: \(error.localizedDescription)")
        }

        // Initialize store (thread-safe)
        storeLock.lock()
        defer { storeLock.unlock() }

        let indexPath = (flowdocsPath as NSString).appendingPathComponent(indexFile)
        let newStore = Store(dbPath: indexPath)
        do {
            try newStore.open()
            self.store = newStore
        } catch {
            return makeToolError("Failed to initialize database: \(error.localizedDescription)")
        }

        return makeToolSuccess("Initialized flowdocs at \(cwd)")
    }

    /// Add a file or directory to the index
    func toolAdd(path: String) throws -> [String: Any] {
        try ensureStore()

        guard let store = self.store else {
            return makeToolError("Store not initialized")
        }

        let absolutePath = resolvePathInCwd(path)

        // Security: validate path is within cwd
        guard Project.validatePathWithinBase(targetPath: absolutePath, baseDir: cwd) else {
            return makeToolError("Path is outside project directory")
        }

        // Check if path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) else {
            return makeToolError("Path does not exist: \(path)")
        }

        if isDirectory.boolValue {
            let count = try addDirectoryToStore(store: store, dirPath: absolutePath, baseDir: cwd)
            return makeToolSuccess("Added \(count) document(s) from \(path)")
        } else {
            let added = try addFileToStore(store: store, filePath: absolutePath, baseDir: cwd)
            if added {
                return makeToolSuccess("Added \(path)")
            } else {
                return makeToolError("Could not add \(path) (not a markdown file or invalid)")
            }
        }
    }

    /// Create a new markdown document and add it to the index
    func toolCreate(path: String, content: String) throws -> [String: Any] {
        try ensureStore()

        guard let store = self.store else {
            return makeToolError("Store not initialized")
        }

        // Compute absolute path
        let absolutePath = resolvePathInCwd(path)

        // Security: validate path is within cwd
        guard Project.validatePathWithinBase(targetPath: absolutePath, baseDir: cwd) else {
            return makeToolError("Path is outside project directory")
        }

        // Create parent directories if needed
        let parentDir = (absolutePath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )
        } catch {
            return makeToolError("Failed to create directory: \(error.localizedDescription)")
        }

        // Write the file
        do {
            try content.write(toFile: absolutePath, atomically: true, encoding: .utf8)
        } catch {
            return makeToolError("Failed to write file: \(error.localizedDescription)")
        }

        // Add to index
        let relativePath = computeRelativePathFromBase(filePath: absolutePath, baseDir: cwd)
        let filename = (absolutePath as NSString).lastPathComponent
        let title = extractTitleFromMarkdown(content: content, fallback: filename)

        let input = DocumentInput(
            path: relativePath,
            title: title,
            content: content
        )

        do {
            try store.addDocument(input)
        } catch {
            return makeToolError("Failed to add to index: \(error.localizedDescription)")
        }

        return makeToolSuccess("Created and indexed \(path)")
    }

    /// Search documentation
    func toolSearch(query: String, limit: Int?) throws -> [String: Any] {
        // Security: validate query length
        if query.count > MCPServer.maxQueryLength {
            return makeToolError("Query exceeds maximum length of \(MCPServer.maxQueryLength) characters")
        }

        try ensureStore()

        guard let store = self.store else {
            return makeToolError("Store not initialized")
        }

        let searchLimit = limit ?? 10
        let search = Search(store: store)
        let results = search.search(query: query, limit: searchLimit)

        if results.isEmpty {
            return makeToolSuccess("No results found for '\(query)'")
        }

        var output = "Found \(results.count) result(s) for '\(query)':\n\n"

        for (index, result) in results.enumerated() {
            let scorePercent = Int(result.score * 100)
            output += "\(index + 1). \(result.title)\n"
            output += "   Path: \(result.path)\n"
            output += "   Relevance: \(scorePercent)%\n"
            if let snippet = result.snippet {
                output += "   \(snippet)\n"
            }
            output += "\n"
        }

        return makeToolSuccess(output)
    }

    /// Retrieve the full content of a document
    func toolGet(path: String) throws -> [String: Any] {
        try ensureStore()

        guard let store = self.store else {
            return makeToolError("Store not initialized")
        }

        guard let document = store.getDocument(path: path) else {
            return makeToolError("Document not found: \(path)")
        }

        var output = "Title: \(document.title)\n"
        output += "Path: \(document.path)\n"
        output += "Updated: \(document.updatedAt)\n\n"
        output += document.content

        return makeToolSuccess(output)
    }

    /// Get the status of the documentation index
    func toolStatus() throws -> [String: Any] {
        let options = ModeOptions(cwd: cwd)
        let config = Project.getProjectConfig(options: options)

        var output = "Mode: \(config.mode.rawValue)\n"
        output += "Index: \(config.indexPath)\n"

        if let projectRoot = config.projectRoot {
            output += "Project root: \(projectRoot)\n"
        }

        // Try to get stats - this will create the index if it doesn't exist
        try ensureStore()
        if let store = self.store {
            let stats = store.getStats()
            output += "\nDocuments: \(stats.documentCount)\n"
            output += "Embeddings: \(stats.embeddedCount)\n"
        } else {
            output += "\nNo index found. Use 'init' to initialize.\n"
        }

        return makeToolSuccess(output)
    }

    /// Remove a document from the index
    func toolRemove(path: String) throws -> [String: Any] {
        try ensureStore()

        guard let store = self.store else {
            return makeToolError("Store not initialized")
        }

        // Check if document exists
        guard store.getDocument(path: path) != nil else {
            return makeToolError("Document not found: \(path)")
        }

        do {
            try store.removeDocument(path: path)
        } catch {
            return makeToolError("Failed to remove document: \(error.localizedDescription)")
        }

        return makeToolSuccess("Removed \(path)")
    }

    // MARK: - Store Management

    /// Ensure the store is initialized (thread-safe)
    func ensureStore() throws {
        storeLock.lock()
        defer { storeLock.unlock() }

        if store != nil { return }

        let options = ModeOptions(cwd: cwd)
        let config = Project.getProjectConfig(options: options)

        // Ensure parent directories exist
        let indexDir = (config.indexPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: indexDir,
            withIntermediateDirectories: true
        )

        let newStore = Store(dbPath: config.indexPath)
        try newStore.open()
        self.store = newStore
    }

    // MARK: - Response Helpers

    /// Create a successful JSON-RPC response
    /// - Parameters:
    ///   - id: Request ID
    ///   - result: Result value
    /// - Returns: JSON string
    func makeResponse(id: Int?, result: Any) -> String {
        let response = JSONRPCResponse(
            id: id,
            result: AnyCodable(result),
            error: nil
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let data = try encoder.encode(response)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return makeErrorResponse(id: id, code: -32603, message: "Internal error")
        }
    }

    /// Create an error JSON-RPC response
    /// - Parameters:
    ///   - id: Request ID
    ///   - code: Error code
    ///   - message: Error message
    /// - Returns: JSON string
    func makeErrorResponse(id: Int?, code: Int, message: String) -> String {
        let response = JSONRPCResponse(
            id: id,
            result: nil,
            error: JSONRPCError(code: code, message: message)
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let data = try encoder.encode(response)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return """
            {"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}
            """
        }
    }

    /// Create a tool success response
    /// - Parameter text: Success message text
    /// - Returns: Tool result dictionary
    private func makeToolSuccess(_ text: String) -> [String: Any] {
        return [
            "content": [
                ["type": "text", "text": text]
            ]
        ]
    }

    /// Create a tool error response
    /// - Parameter text: Error message text
    /// - Returns: Tool result dictionary with isError flag
    private func makeToolError(_ text: String) -> [String: Any] {
        return [
            "content": [
                ["type": "text", "text": "Error: \(text)"]
            ],
            "isError": true
        ]
    }

    // MARK: - Path Helpers

    /// Resolve a path relative to cwd
    private func resolvePathInCwd(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (cwd as NSString).appendingPathComponent(path)
    }

    /// Compute relative path from base directory
    private func computeRelativePathFromBase(filePath: String, baseDir: String) -> String {
        let normalizedFile = (filePath as NSString).standardizingPath
        var normalizedBase = (baseDir as NSString).standardizingPath

        if !normalizedBase.hasSuffix("/") {
            normalizedBase += "/"
        }

        if normalizedFile.hasPrefix(normalizedBase) {
            return String(normalizedFile.dropFirst(normalizedBase.count))
        }

        return (filePath as NSString).lastPathComponent
    }

    /// Extract title from markdown content
    private func extractTitleFromMarkdown(content: String, fallback: String) -> String {
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }

        return fallback
    }

    // MARK: - File Indexing Helpers

    /// Add a directory recursively to the store
    private func addDirectoryToStore(store: Store, dirPath: String, baseDir: String) throws -> Int {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dirPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return 0
        }

        var count = 0

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: dirPath),
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        while let url = enumerator.nextObject() as? URL {
            let filePath = url.path

            // Skip hidden paths
            if isHiddenFilePath(filePath) {
                continue
            }

            // Check if it's a file
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue {
                if try addFileToStore(store: store, filePath: filePath, baseDir: baseDir) {
                    count += 1
                }
            }
        }

        return count
    }

    /// Add a single file to the store
    private func addFileToStore(store: Store, filePath: String, baseDir: String) throws -> Bool {
        let fileManager = FileManager.default

        // Check if file exists and is a regular file
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        // Check if it's a markdown file
        guard isMarkdownExtension(filePath) else {
            return false
        }

        // Validate path is within base directory
        guard Project.validatePathWithinBase(targetPath: filePath, baseDir: baseDir) else {
            return false
        }

        // Read file content
        let content: String
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            return false
        }

        // Compute relative path
        let relativePath = computeRelativePathFromBase(filePath: filePath, baseDir: baseDir)

        // Extract title
        let filename = (filePath as NSString).lastPathComponent
        let title = extractTitleFromMarkdown(content: content, fallback: filename)

        // Add to store
        let input = DocumentInput(
            path: relativePath,
            title: title,
            content: content
        )

        try store.addDocument(input)
        return true
    }

    /// Check if a file has a markdown extension
    private func isMarkdownExtension(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// Check if a path contains hidden components
    private func isHiddenFilePath(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        return components.contains { component in
            component.hasPrefix(".") && !component.isEmpty
        }
    }
}
