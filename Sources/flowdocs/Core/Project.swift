import Foundation

/// Constants for flowdocs directories and files
let flowdocsDir = ".flowdocs"
let indexFile = "index.sqlite"
let systemIndicesDir = "indices"

/// Options for mode detection
struct ModeOptions: Sendable {
    var cwd: String = FileManager.default.currentDirectoryPath
    var forceProject: Bool = false
    var forceSystem: Bool = false
    var indexName: String?
}

/// Project detection and configuration utilities
/// Handles finding project roots, detecting modes, and managing index paths
final class Project: Sendable {

    // MARK: - Project Root Detection

    /// Find project root by walking up directory tree looking for .flowdocs/
    /// Returns nil if not found, stops at filesystem root
    /// Security: Rejects symlinked .flowdocs directories (prevents TOCTOU attacks)
    static func getProjectRoot(startDir: String) -> String? {
        guard !startDir.isEmpty else { return nil }

        let fileManager = FileManager.default
        var currentDir = (startDir as NSString).standardizingPath

        // Verify the starting directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: currentDir, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        while true {
            let flowdocsPath = (currentDir as NSString).appendingPathComponent(flowdocsDir)

            // Check if .flowdocs exists and is a real directory (not a symlink)
            if isRealDirectory(flowdocsPath) {
                return currentDir
            }

            // Move to parent directory
            let parentDir = (currentDir as NSString).deletingLastPathComponent

            // Stop if we've reached the root (parent is same as current)
            if parentDir == currentDir {
                return nil
            }

            currentDir = parentDir
        }
    }

    // MARK: - Mode Detection

    /// Detect whether to use project or system mode
    /// Priority: forceSystem > forceProject > auto-detect (presence of .flowdocs)
    static func detectMode(options: ModeOptions = ModeOptions()) -> Mode {
        // forceSystem takes highest priority
        if options.forceSystem {
            return .system
        }

        // forceProject takes second priority
        if options.forceProject {
            return .project
        }

        // Auto-detect based on .flowdocs presence
        if getProjectRoot(startDir: options.cwd) != nil {
            return .project
        }

        return .system
    }

    // MARK: - Index Path

    /// Get path to SQLite index file
    /// Project mode: .flowdocs/index.sqlite in project root
    /// System mode: ~/.flowdocs/indices/{sanitizedName}.sqlite
    static func getIndexPath(options: ModeOptions = ModeOptions()) -> String {
        let mode = detectMode(options: options)

        switch mode {
        case .project:
            if let projectRoot = getProjectRoot(startDir: options.cwd) {
                let flowdocsPath = (projectRoot as NSString).appendingPathComponent(flowdocsDir)
                return (flowdocsPath as NSString).appendingPathComponent(indexFile)
            }
            // Fallback to system mode if project root not found
            return getSystemIndexPath(indexName: options.indexName)

        case .system:
            return getSystemIndexPath(indexName: options.indexName)
        }
    }

    /// Get path to system index file
    private static func getSystemIndexPath(indexName: String?) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let flowdocsHome = (homeDir as NSString).appendingPathComponent(flowdocsDir)
        let indicesDir = (flowdocsHome as NSString).appendingPathComponent(systemIndicesDir)

        let sanitizedName = sanitizeIndexName(indexName ?? "default")
        return (indicesDir as NSString).appendingPathComponent("\(sanitizedName).sqlite")
    }

    // MARK: - Project Initialization

    /// Error types for project operations
    enum ProjectError: Error, LocalizedError {
        case directoryNotFound(String)
        case failedToCreateDirectory(String)
        case invalidPath(String)

        var errorDescription: String? {
            switch self {
            case .directoryNotFound(let path):
                return "Directory not found: \(path)"
            case .failedToCreateDirectory(let path):
                return "Failed to create directory: \(path)"
            case .invalidPath(let path):
                return "Invalid path: \(path)"
            }
        }
    }

    /// Initialize project by creating .flowdocs directory
    /// - Parameter projectRoot: The root directory for the project
    /// - Returns: ProjectConfig with the initialized project configuration
    /// - Throws: ProjectError if the directory doesn't exist or can't be created
    static func initProject(at projectRoot: String) throws -> ProjectConfig {
        let fileManager = FileManager.default

        // Verify the project root exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectRoot, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectError.directoryNotFound(projectRoot)
        }

        // Create .flowdocs directory
        let flowdocsPath = (projectRoot as NSString).appendingPathComponent(flowdocsDir)

        do {
            try fileManager.createDirectory(
                atPath: flowdocsPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ProjectError.failedToCreateDirectory(flowdocsPath)
        }

        let indexPath = (flowdocsPath as NSString).appendingPathComponent(indexFile)

        return ProjectConfig(
            mode: .project,
            indexPath: indexPath,
            projectRoot: projectRoot
        )
    }

    // MARK: - Project Configuration

    /// Get full project configuration based on options
    /// - Parameter options: Mode detection options
    /// - Returns: ProjectConfig with current mode and paths
    static func getProjectConfig(options: ModeOptions = ModeOptions()) -> ProjectConfig {
        let mode = detectMode(options: options)
        let indexPath = getIndexPath(options: options)

        switch mode {
        case .project:
            let projectRoot = getProjectRoot(startDir: options.cwd)
            return ProjectConfig(
                mode: .project,
                indexPath: indexPath,
                projectRoot: projectRoot
            )
        case .system:
            return ProjectConfig(
                mode: .system,
                indexPath: indexPath,
                projectRoot: nil
            )
        }
    }

    // MARK: - Path Sanitization

    /// Sanitize index name for system mode (prevents path traversal)
    /// - Removes path separators (/ \)
    /// - Removes parent traversal (..)
    /// - Only allows alphanumeric, underscore, dash
    /// - Lowercase, max 64 chars
    /// - Returns "default" if empty after sanitization
    static func sanitizeIndexName(_ name: String) -> String {
        var sanitized = name

        // Remove path traversal sequences
        sanitized = sanitized.replacingOccurrences(of: "..", with: "")

        // Filter to only allowed characters: alphanumeric, underscore, dash
        sanitized = sanitized.filter { char in
            char.isLetter && char.isASCII ||
            char.isNumber ||
            char == "_" ||
            char == "-"
        }

        // Convert to lowercase
        sanitized = sanitized.lowercased()

        // Truncate to max 64 characters
        if sanitized.count > 64 {
            sanitized = String(sanitized.prefix(64))
        }

        // Return "default" if empty
        if sanitized.isEmpty {
            return "default"
        }

        return sanitized
    }

    // MARK: - Security Validation

    /// Check if path is a real directory (not a symlink)
    /// Prevents TOCTOU attacks by checking the actual file type
    static func isRealDirectory(_ path: String) -> Bool {
        let fileManager = FileManager.default

        // First check if path exists
        guard fileManager.fileExists(atPath: path) else {
            return false
        }

        // Check if it's a symbolic link
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileType = attributes[.type] as? FileAttributeType

            // Must be a directory, not a symlink
            return fileType == .typeDirectory
        } catch {
            return false
        }
    }

    /// Check if path is a real file (not a symlink)
    /// Prevents TOCTOU attacks by checking the actual file type
    static func isRealFile(_ path: String) -> Bool {
        let fileManager = FileManager.default

        // First check if path exists
        guard fileManager.fileExists(atPath: path) else {
            return false
        }

        // Check file type
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileType = attributes[.type] as? FileAttributeType

            // Must be a regular file, not a symlink or directory
            return fileType == .typeRegular
        } catch {
            return false
        }
    }

    /// Validate that target path is within base directory (prevents path traversal)
    /// - Parameters:
    ///   - targetPath: The path to validate
    ///   - baseDir: The base directory that target must be within
    /// - Returns: true if targetPath is within baseDir, false otherwise
    static func validatePathWithinBase(targetPath: String, baseDir: String) -> Bool {
        // Resolve both paths to absolute, canonical form
        let resolvedTarget = resolveCanonicalPath(targetPath)
        let resolvedBase = resolveCanonicalPath(baseDir)

        // Ensure base ends with separator for proper prefix matching
        let normalizedBase = resolvedBase.hasSuffix("/") ? resolvedBase : resolvedBase + "/"

        // Target is valid if it equals base or starts with base + "/"
        return resolvedTarget == resolvedBase || resolvedTarget.hasPrefix(normalizedBase)
    }

    /// Resolve path to canonical absolute form
    /// Handles . and .. components, removes trailing slashes
    private static func resolveCanonicalPath(_ path: String) -> String {
        let nsPath = path as NSString

        // Standardize the path (resolves . and .. and symlinks)
        var resolved = nsPath.standardizingPath

        // Remove trailing slash if present (unless it's root)
        if resolved.count > 1 && resolved.hasSuffix("/") {
            resolved = String(resolved.dropLast())
        }

        return resolved
    }
}
