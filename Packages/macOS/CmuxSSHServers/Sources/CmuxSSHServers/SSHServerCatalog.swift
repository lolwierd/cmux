public import Observation
public import CmuxSSHConfig

/// The main-actor catalog model consumed by the Servers sidebar.
@MainActor @Observable public final class SSHServerCatalog {
    private let source: any SSHConfigurationCatalogProviding
    private let search = SSHServerSearch()
    private var changeTask: Task<Void, Never>?

    /// All currently discovered literal aliases.
    public private(set) var servers: [SSHServer] = []
    /// Diagnostics from discovery, metadata loading, and OpenSSH resolution.
    public private(set) var diagnostics: [SSHConfigDiagnostic] = []
    /// The current sidebar search query.
    public var searchQuery = ""
    /// The selected tag filter, or `nil` to show every tag.
    public var selectedTag: String? = nil
    /// Whether an initial or external-change refresh is in flight.
    public private(set) var isLoading = false
    /// The bounded most-recently-used aliases from metadata.
    public private(set) var recentAliases: [String] = []

    /// Creates a catalog with an injected configuration source.
    ///
    /// - Parameter source: The actor-backed source of catalog payloads and change events.
    public init(source: any SSHConfigurationCatalogProviding) {
        self.source = source
    }

    /// Starts initial loading and subscribes to include-graph changes.
    public func start() {
        guard changeTask == nil else { return }
        changeTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.source.changes()
            await self.refresh()
            for await _ in stream {
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// Stops the catalog's external-change subscription.
    public func stop() {
        changeTask?.cancel()
        changeTask = nil
    }

    /// Loads a fresh snapshot from the source.
    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let payload = await source.loadCatalog()
        servers = payload.items.map(SSHServer.init)
        if let selectedTag,
           !availableTags.contains(where: { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) {
            self.selectedTag = nil
        }
        diagnostics = payload.diagnostics
        recentAliases = payload.recentAliases
        isLoading = false
    }

    /// Records an accepted connection and updates the visible recency snapshot.
    ///
    /// - Parameter alias: The literal alias accepted by the cmux SSH launcher.
    public func recordRecent(alias: String) async {
        guard servers.contains(where: { $0.alias == alias }) else { return }
        await source.recordRecent(alias: alias)
        recentAliases = [alias] + recentAliases.filter { $0 != alias }
        recentAliases = Array(recentAliases.prefix(50))
    }

    /// Persists and applies normalized tags for a discovered server.
    ///
    /// - Parameters:
    ///   - alias: The literal alias whose tags should change.
    ///   - tags: User-entered tag names. Empty values and case-insensitive duplicates are removed.
    /// - Returns: Whether persistence succeeded.
    public func updateTags(alias: String, tags: [String]) async -> Bool {
        guard let index = servers.firstIndex(where: { $0.alias == alias }) else { return false }
        let cleanTags = normalizedTags(tags)
        guard await source.updateTags(alias: alias, tags: cleanTags) else { return false }

        let server = servers[index]
        servers[index] = SSHServer(
            alias: server.alias,
            source: server.source,
            effective: server.effective,
            presentation: TetherServerPresentation(
                tags: cleanTags,
                favorite: server.presentation.favorite,
                note: server.presentation.note,
                color: server.presentation.color,
                confirmBeforeConnect: server.presentation.confirmBeforeConnect
            )
        )
        return true
    }

    /// Servers matching the current query in deterministic relevance order.
    public var visibleServers: [SSHServer] {
        let ranked = search.rank(servers, query: searchQuery)
        guard let selectedTag else { return ranked }
        let normalizedTag = selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ranked.filter { server in
            server.presentation.tags.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTag
            }
        }
    }

    /// All distinct presentation tags in deterministic display order.
    public var availableTags: [String] {
        var displayNameByTag: [String: String] = [:]
        for server in servers {
            for rawTag in server.presentation.tags {
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { continue }
                displayNameByTag[tag.lowercased()] = displayNameByTag[tag.lowercased()] ?? tag
            }
        }
        return displayNameByTag.keys.sorted().compactMap { displayNameByTag[$0] }
    }

    /// Favorite servers matching the current query.
    public var favoriteServers: [SSHServer] {
        visibleServers.filter { $0.presentation.favorite }
    }

    /// Recent servers matching the current query and still present in the catalog.
    public var recentServers: [SSHServer] {
        let byAlias = Dictionary(uniqueKeysWithValues: servers.map { ($0.alias, $0) })
        let visibleAliases = Set(visibleServers.map(\.alias))
        return recentAliases.compactMap { alias in
            guard let server = byAlias[alias], visibleAliases.contains(alias) else { return nil }
            return server
        }
    }

    /// Tag groups containing at least one matching server.
    public var tagGroups: [SSHServerTagGroup] {
        var serversByTag: [String: [SSHServer]] = [:]
        var displayNameByTag: [String: String] = [:]

        for server in visibleServers {
            for rawTag in server.presentation.tags {
                let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { continue }
                let key = tag.lowercased()
                serversByTag[key, default: []].append(server)
                displayNameByTag[key] = displayNameByTag[key] ?? tag
            }
        }

        return serversByTag.keys.sorted().compactMap { key in
            guard let servers = serversByTag[key] else { return nil }
            return SSHServerTagGroup(
                tag: displayNameByTag[key] ?? key,
                servers: servers.sorted { $0.alias < $1.alias }
            )
        }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = tag.lowercased()
            guard !tag.isEmpty, seen.insert(key).inserted else { return nil }
            return tag
        }
    }
}
