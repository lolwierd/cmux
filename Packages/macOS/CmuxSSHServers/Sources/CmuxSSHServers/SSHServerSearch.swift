import Foundation
import CmuxSSHConfig

/// Deterministic token scoring for server aliases and presentation metadata.
public struct SSHServerSearch: Sendable {
    /// Creates a scorer with no external state.
    public init() {}

    /// Ranks servers for a query.
    ///
    /// Exact alias matches and alias prefixes receive the strongest scores,
    /// followed by alias substrings, tags, hostname, user, and notes. Every
    /// query token must match at least one field. Ties use stable ASCII-folded
    /// alias and source-path ordering.
    ///
    /// - Parameters:
    ///   - servers: The catalog candidates.
    ///   - query: User-entered search text.
    /// - Returns: Servers in deterministic descending relevance order.
    public func rank(_ servers: [SSHServer], query: String) -> [SSHServer] {
        let normalizedQuery = NormalizedText(query)
        guard !normalizedQuery.tokens.isEmpty else {
            return servers.sorted(by: stableOrder)
        }

        let scored: [ScoredServer] = servers.compactMap { server in
            let fields = SearchFields(server: server)
            var score = 0
            for token in normalizedQuery.tokens {
                guard let tokenScore = fields.score(for: token) else { return nil }
                score += tokenScore
            }
            return ScoredServer(server: server, score: score)
        }
        return scored
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return stableOrder(lhs.server, rhs.server)
        }
        .map(\.server)
    }

    private func stableOrder(_ lhs: SSHServer, _ rhs: SSHServer) -> Bool {
        let leftAlias = NormalizedText(lhs.alias).joined
        let rightAlias = NormalizedText(rhs.alias).joined
        if leftAlias != rightAlias { return leftAlias < rightAlias }
        return lhs.source.url.path < rhs.source.url.path
            || (lhs.source.url.path == rhs.source.url.path && lhs.source.line < rhs.source.line)
    }

    private struct ScoredServer {
        let server: SSHServer
        let score: Int
    }

    private struct SearchFields {
        let alias: NormalizedText
        let hostname: NormalizedText
        let user: NormalizedText
        let tags: [NormalizedText]
        let note: NormalizedText

        init(server: SSHServer) {
            alias = NormalizedText(server.alias)
            hostname = NormalizedText(server.hostname)
            user = NormalizedText(server.user ?? "")
            tags = server.presentation.tags.map(NormalizedText.init)
            note = NormalizedText(server.presentation.note ?? "")
        }

        func score(for token: String) -> Int? {
            if alias.joined == token { return 1_000 }
            if alias.joined.hasPrefix(token) { return 800 }
            if alias.joined.contains(token) { return 600 }
            if tags.contains(where: { $0.joined == token }) { return 520 }
            if tags.contains(where: { $0.joined.contains(token) }) { return 460 }
            if hostname.joined == token { return 430 }
            if hostname.joined.contains(token) { return 390 }
            if user.joined == token { return 360 }
            if user.joined.contains(token) { return 320 }
            if note.joined.contains(token) { return 260 }
            return nil
        }
    }

    private struct NormalizedText {
        let tokens: [String]
        let joined: String

        init(_ value: String) {
            var current = ""
            var values: [String] = []
            for scalar in value.lowercased().unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) {
                    current.append(String(scalar))
                } else if !current.isEmpty {
                    values.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { values.append(current) }
            tokens = values
            joined = values.joined(separator: " ")
        }
    }
}
