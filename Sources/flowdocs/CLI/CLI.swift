import ArgumentParser
import Foundation

// MARK: - Main Command

@main
struct Flowdocs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flowdocs",
        abstract: "Semantic documentation search engine",
        version: "1.0.0",
        subcommands: [
            Init.self,
            Add.self,
            SearchCommand.self,
            Get.self,
            Status.self,
            Remove.self,
            Serve.self
        ]
    )
}

// MARK: - Init Command

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize flowdocs in current directory"
    )

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath

        // Check if already initialized
        let flowdocsPath = (cwd as NSString).appendingPathComponent(flowdocsDir)
        if FileManager.default.fileExists(atPath: flowdocsPath) {
            print("Already initialized at \(flowdocsPath)")
            return
        }

        let config = try Project.initProject(at: cwd)
        print("Initialized flowdocs project at \(config.projectRoot ?? cwd)")
        print("Index will be stored at \(config.indexPath)")
    }
}

// MARK: - Add Command

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add file or directory to index"
    )

    @Argument(help: "File or directory path to index")
    var path: String

    func run() throws {
        let config = Project.getProjectConfig()

        // Ensure parent directories exist for index
        let indexDir = (config.indexPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: indexDir,
            withIntermediateDirectories: true
        )

        let store = Store(dbPath: config.indexPath)
        try store.open()
        defer { store.close() }

        let absolutePath = resolveToAbsolutePath(path)
        let baseDir = config.projectRoot ?? FileManager.default.currentDirectoryPath

        // Check if path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) else {
            print("Error: Path does not exist: \(path)")
            throw ExitCode.failure
        }

        if isDirectory.boolValue {
            let count = try addDirectory(store: store, dirPath: absolutePath, baseDir: baseDir)
            print("Added \(count) document(s) from \(path)")
        } else {
            let added = try addFile(store: store, filePath: absolutePath, baseDir: baseDir)
            if added {
                print("Added \(path)")
            } else {
                print("Skipped \(path) (not a markdown file or outside project)")
            }
        }
    }
}

// MARK: - Search Command

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search documents"
    )

    @Argument(help: "Search query")
    var query: [String]

    @Option(name: .long, help: "Maximum results (default: 10)")
    var limit: Int = 10

    func run() throws {
        let config = Project.getProjectConfig()

        guard FileManager.default.fileExists(atPath: config.indexPath) else {
            print("Error: No index found. Run 'flowdocs init' first.")
            throw ExitCode.failure
        }

        let store = Store(dbPath: config.indexPath)
        try store.open()
        defer { store.close() }

        let search = Search(store: store)
        let queryString = query.joined(separator: " ")
        let results = search.search(query: queryString, limit: limit)

        if results.isEmpty {
            print("No results found for '\(queryString)'")
            return
        }

        print("Found \(results.count) result(s) for '\(queryString)':\n")

        for (index, result) in results.enumerated() {
            let scorePercent = Int(result.score * 100)
            print("\(index + 1). \(result.title)")
            print("   Path: \(result.path)")
            print("   Relevance: \(scorePercent)%")
            if let snippet = result.snippet {
                print("   \(snippet)")
            }
            print("")
        }
    }
}

// MARK: - Get Command

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Retrieve document content"
    )

    @Argument(help: "Document path")
    var path: String

    func run() throws {
        let config = Project.getProjectConfig()

        guard FileManager.default.fileExists(atPath: config.indexPath) else {
            print("Error: No index found. Run 'flowdocs init' first.")
            throw ExitCode.failure
        }

        let store = Store(dbPath: config.indexPath)
        try store.open()
        defer { store.close() }

        guard let document = store.getDocument(path: path) else {
            print("Error: Document not found: \(path)")
            throw ExitCode.failure
        }

        print("Title: \(document.title)")
        print("Path: \(document.path)")
        print("Updated: \(document.updatedAt)")
        print("")
        print(document.content)
    }
}

// MARK: - Status Command

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show index status"
    )

    func run() throws {
        let config = Project.getProjectConfig()

        print("Mode: \(config.mode.rawValue)")
        print("Index: \(config.indexPath)")

        if let projectRoot = config.projectRoot {
            print("Project root: \(projectRoot)")
        }

        guard FileManager.default.fileExists(atPath: config.indexPath) else {
            print("\nNo index found. Run 'flowdocs init' to initialize.")
            return
        }

        let store = Store(dbPath: config.indexPath)
        try store.open()
        defer { store.close() }

        let stats = store.getStats()
        print("\nDocuments: \(stats.documentCount)")
        print("Embeddings: \(stats.embeddedCount)")
    }
}

// MARK: - Remove Command

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove document from index"
    )

    @Argument(help: "Document path to remove")
    var path: String

    func run() throws {
        let config = Project.getProjectConfig()

        guard FileManager.default.fileExists(atPath: config.indexPath) else {
            print("Error: No index found. Run 'flowdocs init' first.")
            throw ExitCode.failure
        }

        let store = Store(dbPath: config.indexPath)
        try store.open()
        defer { store.close() }

        // Check if document exists
        guard store.getDocument(path: path) != nil else {
            print("Error: Document not found: \(path)")
            throw ExitCode.failure
        }

        try store.removeDocument(path: path)
        print("Removed \(path)")
    }
}

// MARK: - Serve Command

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start MCP server for Claude integration"
    )

    func run() throws {
        let server = MCPServer()
        try server.run()
    }
}

// MARK: - Helper Functions

/// Extract title from markdown content (first H1 heading)
/// - Parameters:
///   - content: The markdown content to parse
///   - fallback: Fallback title if no H1 found
/// - Returns: The extracted title or fallback
func extractTitle(from content: String, fallback: String) -> String {
    // Look for H1 heading pattern: # Title
    // Must be at start of a line
    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            // Extract text after "# "
            let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                return title
            }
        }
    }

    return fallback
}

/// Check if a file is a markdown file based on extension
/// - Parameter path: File path to check
/// - Returns: true if file has .md or .markdown extension
func isMarkdownFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return ext == "md" || ext == "markdown"
}

/// Check if a path contains a hidden component (starts with .)
/// - Parameter path: Path to check
/// - Returns: true if path contains hidden directory or file
func isHiddenPath(_ path: String) -> Bool {
    let components = path.components(separatedBy: "/")
    return components.contains { component in
        component.hasPrefix(".") && !component.isEmpty
    }
}

/// Recursively add markdown files from directory
/// - Parameters:
///   - store: The document store
///   - dirPath: Directory path to scan
///   - baseDir: Base directory for relative paths
/// - Returns: Number of files added
/// - Throws: Store errors on database operations
func addDirectory(store: Store, dirPath: String, baseDir: String) throws -> Int {
    let fileManager = FileManager.default

    // Check if directory exists
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: dirPath, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return 0
    }

    var count = 0

    // Get directory enumerator
    guard let enumerator = fileManager.enumerator(
        at: URL(fileURLWithPath: dirPath),
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }

    while let url = enumerator.nextObject() as? URL {
        let filePath = url.path

        // Skip hidden paths (additional check beyond .skipsHiddenFiles)
        if isHiddenPath(filePath) {
            continue
        }

        // Check if it's a file
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue {
            if try addFile(store: store, filePath: filePath, baseDir: baseDir) {
                count += 1
            }
        }
    }

    return count
}

/// Add a single markdown file to the store
/// - Parameters:
///   - store: The document store
///   - filePath: Absolute path to the file
///   - baseDir: Base directory for computing relative paths
/// - Returns: true if file was added, false if skipped
/// - Throws: Store errors on database operations
func addFile(store: Store, filePath: String, baseDir: String) throws -> Bool {
    let fileManager = FileManager.default

    // Check if file exists and is a regular file
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        return false
    }

    // Check if it's a markdown file
    guard isMarkdownFile(filePath) else {
        return false
    }

    // Validate path is within base directory (security)
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

    // Compute relative path from base directory
    let relativePath = computeRelativePath(filePath: filePath, baseDir: baseDir)

    // Extract title from markdown or use filename
    let filename = (filePath as NSString).lastPathComponent
    let title = extractTitle(from: content, fallback: filename)

    // Add to store
    let input = DocumentInput(
        path: relativePath,
        title: title,
        content: content
    )

    try store.addDocument(input)
    return true
}

/// Resolve a path to absolute path
/// - Parameter path: Relative or absolute path
/// - Returns: Absolute path
func resolveToAbsolutePath(_ path: String) -> String {
    if path.hasPrefix("/") {
        return path
    }

    let cwd = FileManager.default.currentDirectoryPath
    return (cwd as NSString).appendingPathComponent(path)
}

/// Compute relative path from base directory
/// - Parameters:
///   - filePath: Absolute file path
///   - baseDir: Base directory
/// - Returns: Relative path from base directory
func computeRelativePath(filePath: String, baseDir: String) -> String {
    let normalizedFile = (filePath as NSString).standardizingPath
    var normalizedBase = (baseDir as NSString).standardizingPath

    // Ensure base ends with separator
    if !normalizedBase.hasSuffix("/") {
        normalizedBase += "/"
    }

    // If file starts with base, strip it
    if normalizedFile.hasPrefix(normalizedBase) {
        return String(normalizedFile.dropFirst(normalizedBase.count))
    }

    // Fall back to just the filename
    return (filePath as NSString).lastPathComponent
}
