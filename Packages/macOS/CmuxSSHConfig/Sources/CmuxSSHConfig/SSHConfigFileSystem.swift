public import Foundation

/// Errors raised by an injected SSH configuration filesystem.
public enum SSHConfigFileSystemError: Error, Sendable, Equatable {
    /// The requested file does not exist.
    case missing(URL)
    /// The file exists but could not be read as UTF-8 text.
    case unreadable(URL)
}

/// The filesystem seam used by include discovery.
public protocol SSHConfigFileSystem: Sendable {
    /// Reads UTF-8 text from a configuration file.
    ///
    /// - Parameter url: The file to read.
    /// - Returns: The file's UTF-8 contents.
    /// - Throws: ``SSHConfigFileSystemError`` when the file is missing or unreadable.
    func readText(at url: URL) async throws -> String

    /// Expands an OpenSSH include pattern relative to a containing file.
    ///
    /// - Parameters:
    ///   - pattern: The include path or glob.
    ///   - baseURL: The containing file's parent directory.
    /// - Returns: Matching regular-file URLs in deterministic path order.
    func matchingURLs(for pattern: String, relativeTo baseURL: URL) async -> [URL]

    /// Resolves a URL for cycle detection and stable source identity.
    ///
    /// - Parameter url: The URL to canonicalize.
    /// - Returns: A standardized, symlink-resolved URL where possible.
    func canonicalURL(for url: URL) async -> URL
}

/// The local actor-backed filesystem used by the app composition root.
public actor LocalSSHConfigFileSystem: SSHConfigFileSystem {
    private let fileManager: FileManager
    private let homeDirectory: URL

    /// Creates a local filesystem seam.
    ///
    /// - Parameters:
    ///   - fileManager: The file manager used for reads and directory traversal.
    ///   - homeDirectory: The home directory used to expand `~` in includes.
    public init(fileManager: FileManager, homeDirectory: URL) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Creates a local filesystem using the current user's home directory.
    public init() {
        self.fileManager = FileManager.default
        self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    }

    /// Creates a local filesystem with an injected home directory.
    ///
    /// - Parameter homeDirectory: The home directory used to expand `~` in includes.
    public init(homeDirectory: URL) {
        self.fileManager = FileManager.default
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func readText(at url: URL) async throws -> String {
        let standardized = url.standardizedFileURL
        guard fileManager.isReadableFile(atPath: standardized.path) else {
            if fileManager.fileExists(atPath: standardized.path) {
                throw SSHConfigFileSystemError.unreadable(standardized)
            }
            throw SSHConfigFileSystemError.missing(standardized)
        }
        do {
            return try String(contentsOf: standardized, encoding: .utf8)
        } catch {
            throw SSHConfigFileSystemError.unreadable(standardized)
        }
    }

    public func matchingURLs(for pattern: String, relativeTo baseURL: URL) async -> [URL] {
        let expanded = expand(pattern: pattern, relativeTo: baseURL)
        guard hasGlobSyntax(in: expanded.path) else {
            return fileManager.fileExists(atPath: expanded.path) ? [expanded] : []
        }

        let root = enumerationRoot(for: expanded)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var matches: [URL] = []
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while let candidate = enumerator.nextObject() as? URL {
            guard (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let candidatePath = candidate.standardizedFileURL.path
            let relativePath = candidatePath.hasPrefix(rootPath)
                ? String(candidatePath.dropFirst(rootPath.count))
                : candidatePath
            let patternPath: String
            if expanded.path.hasPrefix(rootPath) {
                patternPath = String(expanded.path.dropFirst(rootPath.count))
            } else {
                patternPath = expanded.path
            }
            if GlobMatcher(pattern: patternPath).matches(relativePath) {
                matches.append(candidate.standardizedFileURL)
            }
        }
        return matches.sorted { $0.path < $1.path }
    }

    public func canonicalURL(for url: URL) async -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func expand(pattern: String, relativeTo baseURL: URL) -> URL {
        let expandedPattern: String
        if pattern == "~" {
            expandedPattern = homeDirectory.path
        } else if pattern.hasPrefix("~/") {
            expandedPattern = homeDirectory.appendingPathComponent(String(pattern.dropFirst(2))).path
        } else {
            expandedPattern = pattern
        }

        if expandedPattern.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPattern).standardizedFileURL
        }
        return URL(fileURLWithPath: expandedPattern, relativeTo: baseURL).standardizedFileURL
    }

    private func hasGlobSyntax(in path: String) -> Bool {
        path.contains("*") || path.contains("?") || path.contains("[")
    }

    private func enumerationRoot(for url: URL) -> URL {
        let components = url.pathComponents
        var prefix: [String] = []
        for component in components {
            if component.contains("*") || component.contains("?") || component.contains("[") {
                break
            }
            prefix.append(component)
        }
        guard !prefix.isEmpty else { return URL(fileURLWithPath: "/") }
        return URL(fileURLWithPath: NSString.path(withComponents: prefix))
    }

    private struct GlobMatcher {
        let pattern: Array<Character>

        init(pattern: String) {
            self.pattern = Array(pattern)
        }

        func matches(_ value: String) -> Bool {
            matches(patternIndex: 0, value: Array(value), valueIndex: 0)
        }

        private func matches(
            patternIndex: Int,
            value: [Character],
            valueIndex: Int
        ) -> Bool {
            guard patternIndex < pattern.count else { return valueIndex == value.count }
            let token = pattern[patternIndex]
            if token == "*" {
                if matches(patternIndex: patternIndex + 1, value: value, valueIndex: valueIndex) {
                    return true
                }
                guard valueIndex < value.count, value[valueIndex] != "/" else { return false }
                return matches(patternIndex: patternIndex, value: value, valueIndex: valueIndex + 1)
            }
            guard valueIndex < value.count else { return false }
            if token == "?" {
                return value[valueIndex] != "/"
                    && matches(patternIndex: patternIndex + 1, value: value, valueIndex: valueIndex + 1)
            }
            if token == "[" {
                guard let closingIndex = pattern[patternIndex...].firstIndex(of: "]"), closingIndex > patternIndex + 1 else {
                    return value[valueIndex] == "["
                        && matches(patternIndex: patternIndex + 1, value: value, valueIndex: valueIndex + 1)
                }
                let choices = pattern[(patternIndex + 1)..<closingIndex]
                guard choices.contains(value[valueIndex]) else { return false }
                return matches(patternIndex: closingIndex + 1, value: value, valueIndex: valueIndex + 1)
            }
            return token == value[valueIndex]
                && matches(patternIndex: patternIndex + 1, value: value, valueIndex: valueIndex + 1)
        }
    }
}
