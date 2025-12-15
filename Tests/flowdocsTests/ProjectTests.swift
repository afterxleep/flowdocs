import Testing
import Foundation
@testable import flowdocs

@Suite("Project Tests")
struct ProjectTests {

    // Helper to create temporary test directories
    static func tempDir() -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("flowdocs_project_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir.path
    }

    // Helper to clean up a directory
    static func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - getProjectRoot Tests

    @Suite("getProjectRoot")
    struct GetProjectRootTests {

        @Test("Finds .flowdocs in current directory")
        func findsFlowdocsInCurrentDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create .flowdocs directory
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            let result = Project.getProjectRoot(startDir: testDir)
            #expect(result == testDir)
        }

        @Test("Finds .flowdocs in parent directory")
        func findsFlowdocsInParentDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create nested structure
            let subDir = (testDir as NSString).appendingPathComponent("subdir")
            try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)

            // Create .flowdocs in parent
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            let result = Project.getProjectRoot(startDir: subDir)
            #expect(result == testDir)
        }

        @Test("Finds .flowdocs in grandparent directory")
        func findsFlowdocsInGrandparentDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create deeply nested structure
            let deepDir = (testDir as NSString).appendingPathComponent("a/b/c")
            try FileManager.default.createDirectory(atPath: deepDir, withIntermediateDirectories: true)

            // Create .flowdocs at root
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            let result = Project.getProjectRoot(startDir: deepDir)
            #expect(result == testDir)
        }

        @Test("Returns nil when .flowdocs not found")
        func returnsNilWhenNotFound() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // No .flowdocs directory
            let result = Project.getProjectRoot(startDir: testDir)
            #expect(result == nil)
        }

        @Test("Returns nil for empty path")
        func returnsNilForEmptyPath() {
            let result = Project.getProjectRoot(startDir: "")
            #expect(result == nil)
        }

        @Test("Returns nil for non-existent path")
        func returnsNilForNonExistentPath() {
            let result = Project.getProjectRoot(startDir: "/nonexistent/path/that/does/not/exist")
            #expect(result == nil)
        }

        @Test("Rejects symlinked .flowdocs directory (security)")
        func rejectsSymlinkedFlowdocs() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create a real .flowdocs elsewhere
            let realFlowdocs = (testDir as NSString).appendingPathComponent("real_flowdocs")
            try FileManager.default.createDirectory(atPath: realFlowdocs, withIntermediateDirectories: true)

            // Create a subdir where we'll put the symlink
            let projectDir = (testDir as NSString).appendingPathComponent("project")
            try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

            // Create symlink to real .flowdocs
            let symlinkPath = (projectDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: realFlowdocs)

            // Should reject the symlinked .flowdocs
            let result = Project.getProjectRoot(startDir: projectDir)
            #expect(result == nil)
        }

        @Test("Stops at filesystem root")
        func stopsAtFilesystemRoot() {
            // Starting from root should not infinite loop
            let result = Project.getProjectRoot(startDir: "/")
            // Just verify it returns (doesn't hang) - likely nil unless system has .flowdocs at root
            #expect(result == nil || result == "/")
        }
    }

    // MARK: - detectMode Tests

    @Suite("detectMode")
    struct DetectModeTests {

        @Test("Returns project mode when .flowdocs exists")
        func returnsProjectWhenFlowdocsExists() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create .flowdocs
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            let mode = Project.detectMode(options: ModeOptions(cwd: testDir))
            #expect(mode == .project)
        }

        @Test("Returns system mode when no .flowdocs")
        func returnsSystemWhenNoFlowdocs() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let mode = Project.detectMode(options: ModeOptions(cwd: testDir))
            #expect(mode == .system)
        }

        @Test("Respects forceProject flag")
        func respectsForceProjectFlag() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // No .flowdocs, but forceProject is true
            var options = ModeOptions(cwd: testDir)
            options.forceProject = true

            let mode = Project.detectMode(options: options)
            #expect(mode == .project)
        }

        @Test("Respects forceSystem flag")
        func respectsForceSystemFlag() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create .flowdocs
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            // forceSystem should override
            var options = ModeOptions(cwd: testDir)
            options.forceSystem = true

            let mode = Project.detectMode(options: options)
            #expect(mode == .system)
        }

        @Test("forceSystem takes priority over forceProject")
        func forceSystemTakesPriority() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            var options = ModeOptions(cwd: testDir)
            options.forceProject = true
            options.forceSystem = true

            let mode = Project.detectMode(options: options)
            #expect(mode == .system)
        }
    }

    // MARK: - getIndexPath Tests

    @Suite("getIndexPath")
    struct GetIndexPathTests {

        @Test("Returns correct path for project mode")
        func projectModeIndexPath() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Create .flowdocs
            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            try FileManager.default.createDirectory(atPath: flowdocsPath, withIntermediateDirectories: true)

            let indexPath = Project.getIndexPath(options: ModeOptions(cwd: testDir))
            let expectedPath = (flowdocsPath as NSString).appendingPathComponent(indexFile)
            #expect(indexPath == expectedPath)
        }

        @Test("Returns correct path for system mode")
        func systemModeIndexPath() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // No .flowdocs, so system mode
            let indexPath = Project.getIndexPath(options: ModeOptions(cwd: testDir))

            // Should be in ~/.flowdocs/indices/
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            #expect(indexPath.hasPrefix(homeDir))
            #expect(indexPath.contains(systemIndicesDir))
            #expect(indexPath.hasSuffix(".sqlite"))
        }

        @Test("System mode uses sanitized index name")
        func systemModeUsesIndexName() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            var options = ModeOptions(cwd: testDir)
            options.forceSystem = true
            options.indexName = "my-custom-index"

            let indexPath = Project.getIndexPath(options: options)
            #expect(indexPath.contains("my-custom-index"))
            #expect(indexPath.hasSuffix(".sqlite"))
        }

        @Test("System mode defaults to 'default' index name")
        func systemModeDefaultIndexName() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            var options = ModeOptions(cwd: testDir)
            options.forceSystem = true

            let indexPath = Project.getIndexPath(options: options)
            #expect(indexPath.contains("default.sqlite"))
        }
    }

    // MARK: - initProject Tests

    @Suite("initProject")
    struct InitProjectTests {

        @Test("Creates .flowdocs directory")
        func createsFlowdocsDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let config = try Project.initProject(at: testDir)

            let flowdocsPath = (testDir as NSString).appendingPathComponent(flowdocsDir)
            #expect(FileManager.default.fileExists(atPath: flowdocsPath))
            #expect(config.mode == .project)
            #expect(config.projectRoot == testDir)
        }

        @Test("Returns correct config")
        func returnsCorrectConfig() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let config = try Project.initProject(at: testDir)

            #expect(config.mode == .project)
            #expect(config.projectRoot == testDir)
            #expect(config.indexPath.contains(flowdocsDir))
            #expect(config.indexPath.contains(indexFile))
        }

        @Test("Is idempotent - does not fail if already initialized")
        func isIdempotent() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Initialize twice
            _ = try Project.initProject(at: testDir)
            let config = try Project.initProject(at: testDir)

            #expect(config.mode == .project)
        }

        @Test("Throws for non-existent directory")
        func throwsForNonExistentDir() {
            #expect(throws: (any Error).self) {
                _ = try Project.initProject(at: "/nonexistent/path/that/does/not/exist")
            }
        }
    }

    // MARK: - getProjectConfig Tests

    @Suite("getProjectConfig")
    struct GetProjectConfigTests {

        @Test("Returns project config when in project")
        func returnsProjectConfig() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            // Initialize project
            _ = try Project.initProject(at: testDir)

            let config = Project.getProjectConfig(options: ModeOptions(cwd: testDir))

            #expect(config.mode == .project)
            #expect(config.projectRoot == testDir)
        }

        @Test("Returns system config when not in project")
        func returnsSystemConfig() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let config = Project.getProjectConfig(options: ModeOptions(cwd: testDir))

            #expect(config.mode == .system)
            #expect(config.projectRoot == nil)
        }
    }

    // MARK: - sanitizeIndexName Tests

    @Suite("sanitizeIndexName")
    struct SanitizeIndexNameTests {

        @Test("Allows alphanumeric characters")
        func allowsAlphanumeric() {
            let result = Project.sanitizeIndexName("myIndex123")
            #expect(result == "myindex123")
        }

        @Test("Allows underscore and dash")
        func allowsUnderscoreDash() {
            let result = Project.sanitizeIndexName("my_index-name")
            #expect(result == "my_index-name")
        }

        @Test("Converts to lowercase")
        func convertsToLowercase() {
            let result = Project.sanitizeIndexName("MyIndex")
            #expect(result == "myindex")
        }

        @Test("Removes path separators")
        func removesPathSeparators() {
            let result = Project.sanitizeIndexName("path/to/index")
            #expect(!result.contains("/"))

            let result2 = Project.sanitizeIndexName("path\\to\\index")
            #expect(!result2.contains("\\"))
        }

        @Test("Removes parent traversal")
        func removesParentTraversal() {
            let result = Project.sanitizeIndexName("../../../etc/passwd")
            #expect(!result.contains(".."))
            #expect(!result.contains("/"))
        }

        @Test("Removes special characters")
        func removesSpecialChars() {
            let result = Project.sanitizeIndexName("index!@#$%^&*()name")
            // Should only contain alphanumeric, underscore, dash
            #expect(result.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        }

        @Test("Truncates to 64 characters")
        func truncatesLongNames() {
            let longName = String(repeating: "a", count: 100)
            let result = Project.sanitizeIndexName(longName)
            #expect(result.count <= 64)
        }

        @Test("Returns 'default' for empty result")
        func returnsDefaultForEmpty() {
            let result = Project.sanitizeIndexName("")
            #expect(result == "default")

            let result2 = Project.sanitizeIndexName("!@#$%")
            #expect(result2 == "default")
        }

        @Test("Handles unicode gracefully")
        func handlesUnicode() {
            let result = Project.sanitizeIndexName("index_name")
            #expect(result.allSatisfy { $0.isASCII })
        }
    }

    // MARK: - isRealDirectory Tests

    @Suite("isRealDirectory")
    struct IsRealDirectoryTests {

        @Test("Returns true for real directory")
        func returnsTrueForRealDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            #expect(Project.isRealDirectory(testDir) == true)
        }

        @Test("Returns false for symlinked directory")
        func returnsFalseForSymlink() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let realDir = (testDir as NSString).appendingPathComponent("real")
            let symlinkDir = (testDir as NSString).appendingPathComponent("symlink")

            try FileManager.default.createDirectory(atPath: realDir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: symlinkDir, withDestinationPath: realDir)

            #expect(Project.isRealDirectory(realDir) == true)
            #expect(Project.isRealDirectory(symlinkDir) == false)
        }

        @Test("Returns false for file")
        func returnsFalseForFile() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let filePath = (testDir as NSString).appendingPathComponent("file.txt")
            try "content".write(toFile: filePath, atomically: true, encoding: .utf8)

            #expect(Project.isRealDirectory(filePath) == false)
        }

        @Test("Returns false for non-existent path")
        func returnsFalseForNonExistent() {
            #expect(Project.isRealDirectory("/nonexistent/path") == false)
        }
    }

    // MARK: - isRealFile Tests

    @Suite("isRealFile")
    struct IsRealFileTests {

        @Test("Returns true for real file")
        func returnsTrueForRealFile() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let filePath = (testDir as NSString).appendingPathComponent("file.txt")
            try "content".write(toFile: filePath, atomically: true, encoding: .utf8)

            #expect(Project.isRealFile(filePath) == true)
        }

        @Test("Returns false for symlinked file")
        func returnsFalseForSymlink() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let realFile = (testDir as NSString).appendingPathComponent("real.txt")
            let symlinkFile = (testDir as NSString).appendingPathComponent("symlink.txt")

            try "content".write(toFile: realFile, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(atPath: symlinkFile, withDestinationPath: realFile)

            #expect(Project.isRealFile(realFile) == true)
            #expect(Project.isRealFile(symlinkFile) == false)
        }

        @Test("Returns false for directory")
        func returnsFalseForDir() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            #expect(Project.isRealFile(testDir) == false)
        }

        @Test("Returns false for non-existent path")
        func returnsFalseForNonExistent() {
            #expect(Project.isRealFile("/nonexistent/path") == false)
        }
    }

    // MARK: - validatePathWithinBase Tests

    @Suite("validatePathWithinBase")
    struct ValidatePathWithinBaseTests {

        @Test("Accepts path within base directory")
        func acceptsValidPath() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let targetPath = (testDir as NSString).appendingPathComponent("subdir/file.md")

            #expect(Project.validatePathWithinBase(targetPath: targetPath, baseDir: testDir) == true)
        }

        @Test("Accepts exact base directory path")
        func acceptsExactBase() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            #expect(Project.validatePathWithinBase(targetPath: testDir, baseDir: testDir) == true)
        }

        @Test("Rejects path traversal with ..")
        func rejectsPathTraversal() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let evilPath = (testDir as NSString).appendingPathComponent("../../../etc/passwd")

            #expect(Project.validatePathWithinBase(targetPath: evilPath, baseDir: testDir) == false)
        }

        @Test("Rejects absolute path outside base")
        func rejectsOutsidePath() {
            let baseDir = "/Users/test/project"
            let outsidePath = "/Users/other/secret"

            #expect(Project.validatePathWithinBase(targetPath: outsidePath, baseDir: baseDir) == false)
        }

        @Test("Handles paths with . components")
        func handlesCurrentDirComponents() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let pathWithDot = (testDir as NSString).appendingPathComponent("./subdir/./file.md")

            #expect(Project.validatePathWithinBase(targetPath: pathWithDot, baseDir: testDir) == true)
        }

        @Test("Rejects path that is prefix but not within")
        func rejectsPrefixPath() {
            let baseDir = "/Users/test/project"
            let prefixPath = "/Users/test/project_other/file.md"

            #expect(Project.validatePathWithinBase(targetPath: prefixPath, baseDir: baseDir) == false)
        }

        @Test("Handles trailing slashes consistently")
        func handlesTrailingSlashes() throws {
            let testDir = ProjectTests.tempDir()
            defer { ProjectTests.cleanup(testDir) }

            let targetPath = (testDir as NSString).appendingPathComponent("subdir/file.md")
            let baseDirWithSlash = testDir + "/"

            #expect(Project.validatePathWithinBase(targetPath: targetPath, baseDir: baseDirWithSlash) == true)
        }
    }

    // MARK: - ModeOptions Tests

    @Suite("ModeOptions")
    struct ModeOptionsTests {

        @Test("ModeOptions has correct defaults")
        func modeOptionsDefaults() {
            let options = ModeOptions()

            #expect(options.forceProject == false)
            #expect(options.forceSystem == false)
            #expect(options.indexName == nil)
            // cwd default is current directory, just verify it's set
            #expect(!options.cwd.isEmpty)
        }

        @Test("ModeOptions can be customized")
        func modeOptionsCustom() {
            var options = ModeOptions()
            options.cwd = "/custom/path"
            options.forceProject = true
            options.indexName = "custom"

            #expect(options.cwd == "/custom/path")
            #expect(options.forceProject == true)
            #expect(options.indexName == "custom")
        }
    }

    // MARK: - Constants Tests

    @Suite("Constants")
    struct ConstantsTests {

        @Test("flowdocsDir is .flowdocs")
        func flowdocsDirConstant() {
            #expect(flowdocsDir == ".flowdocs")
        }

        @Test("indexFile is index.sqlite")
        func indexFileConstant() {
            #expect(indexFile == "index.sqlite")
        }

        @Test("systemIndicesDir is indices")
        func systemIndicesDirConstant() {
            #expect(systemIndicesDir == "indices")
        }
    }
}
