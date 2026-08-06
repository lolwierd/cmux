public import Foundation

/// Discovers literal SSH aliases without attempting to reimplement OpenSSH evaluation.
public struct SSHConfigAliasDiscovery: Sendable {
    private let fileSystem: any SSHConfigFileSystem

    /// Creates an include-aware alias discoverer.
    ///
    /// - Parameter fileSystem: The injected filesystem used for reads and glob expansion.
    public init(fileSystem: any SSHConfigFileSystem) {
        self.fileSystem = fileSystem
    }

    /// Walks the root config and its recursive includes.
    ///
    /// Wildcard and negated host patterns affect OpenSSH but do not become rows.
    /// Missing, unreadable, and cyclic includes become diagnostics while aliases
    /// already found elsewhere remain available.
    ///
    /// - Parameter rootURL: The user's root SSH config.
    /// - Returns: A source-ordered discovery snapshot.
    public func discover(rootURL: URL) async -> SSHConfigDiscoverySnapshot {
        let state = DiscoveryState()
        await visit(
            url: rootURL,
            includingURL: nil,
            state: state
        )
        return state.snapshot
    }

    private func visit(
        url: URL,
        includingURL: URL?,
        state: DiscoveryState
    ) async {
        let canonicalURL = await fileSystem.canonicalURL(for: url)
        if state.visited.contains(canonicalURL) {
            if state.active.contains(canonicalURL) {
                state.diagnostics.append(
                    SSHConfigDiagnostic(
                        url: canonicalURL,
                        line: nil,
                        severity: .warning,
                        message: "SSH Include cycle ignored."
                    )
                )
            }
            return
        }

        state.visited.insert(canonicalURL)
        state.active.insert(canonicalURL)
        defer { state.active.remove(canonicalURL) }
        do {
            let text = try await fileSystem.readText(at: canonicalURL)
            state.includedFiles.append(canonicalURL)
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            for (offset, rawLine) in lines.enumerated() {
                let lineNumber = offset + 1
                let tokens = LineTokenizer(line: String(rawLine)).tokens
                guard let firstToken = tokens.first else { continue }
                let directiveParts = firstToken.split(separator: "=", maxSplits: 1)
                let keyword = String(directiveParts[0]).lowercased()
                let inlineValue = directiveParts.count == 2 ? [String(directiveParts[1])] : []
                let values = inlineValue + Array(tokens.dropFirst())
                if keyword == "host" {
                    for value in values where isLiteralAlias(value) {
                        state.aliases.append(
                            SSHDiscoveredAlias(
                                alias: value,
                                source: SSHConfigSourceLocation(url: canonicalURL, line: lineNumber)
                            )
                        )
                    }
                } else if keyword == "include" {
                    let baseURL = canonicalURL.deletingLastPathComponent()
                    for includePattern in values {
                        let matches = await fileSystem.matchingURLs(
                            for: includePattern,
                            relativeTo: baseURL
                        )
                        if matches.isEmpty {
                            state.diagnostics.append(
                                SSHConfigDiagnostic(
                                    url: canonicalURL,
                                    line: lineNumber,
                                    severity: .warning,
                                    message: "Included SSH file was not found: \(includePattern)"
                                )
                            )
                            continue
                        }
                        for match in matches {
                            await visit(url: match, includingURL: canonicalURL, state: state)
                        }
                    }
                }
            }
        } catch let error as SSHConfigFileSystemError {
            let message: String
            switch error {
            case .missing:
                message = includingURL == nil
                    ? "SSH config file was not found."
                    : "Included SSH file was not found."
            case .unreadable:
                message = "SSH config file could not be read."
            }
            state.diagnostics.append(
                SSHConfigDiagnostic(
                    url: canonicalURL,
                    line: nil,
                    severity: .warning,
                    message: message
                )
            )
        } catch {
            state.diagnostics.append(
                SSHConfigDiagnostic(
                    url: canonicalURL,
                    line: nil,
                    severity: .error,
                    message: "SSH config file could not be read."
                )
            )
        }
    }

    private func isLiteralAlias(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("!") else { return false }
        return !value.contains(where: { "*?[".contains($0) })
    }

    private final class DiscoveryState {
        var aliases: [SSHDiscoveredAlias] = []
        var includedFiles: [URL] = []
        var diagnostics: [SSHConfigDiagnostic] = []
        var visited: Set<URL> = []
        var active: Set<URL> = []

        var snapshot: SSHConfigDiscoverySnapshot {
            SSHConfigDiscoverySnapshot(
                aliases: aliases,
                includedFiles: includedFiles,
                diagnostics: diagnostics
            )
        }
    }

    private struct LineTokenizer {
        let tokens: [String]

        init(line: String) {
            var result: [String] = []
            var token = ""
            var quote: Character?
            var escaped = false
            for character in line {
                if escaped {
                    token.append(character)
                    escaped = false
                    continue
                }
                if character == "\\" {
                    escaped = true
                    continue
                }
                if let activeQuote = quote {
                    if character == activeQuote {
                        quote = nil
                    } else {
                        token.append(character)
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#" {
                    break
                } else if character.isWhitespace {
                    if !token.isEmpty {
                        result.append(token)
                        token = ""
                    }
                } else {
                    token.append(character)
                }
            }
            if escaped { token.append("\\") }
            if !token.isEmpty { result.append(token) }
            self.tokens = result
        }
    }
}
