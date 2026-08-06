public import Foundation

/// Supplies assembled read-only SSH catalog payloads to the domain layer.
public protocol SSHConfigurationCatalogProviding: Sendable {
    /// Loads aliases, effective OpenSSH values, metadata, and diagnostics.
    ///
    /// - Returns: The assembled catalog payload.
    func loadCatalog() async -> SSHConfigurationCatalogPayload

    /// Records an accepted connection for the bounded recent-server list.
    ///
    /// The source owns metadata persistence so connection callers do not need
    /// to know where Tether stores its presentation data.
    ///
    /// - Parameter alias: The literal alias accepted by the cmux SSH launcher.
    func recordRecent(alias: String) async

    /// Replaces the user-defined tags for one discovered alias.
    ///
    /// - Parameters:
    ///   - alias: The literal alias whose presentation metadata should change.
    ///   - tags: The normalized, user-defined tags to persist.
    /// - Returns: Whether the metadata was saved successfully.
    func updateTags(alias: String, tags: [String]) async -> Bool

    /// Creates a stream of external configuration changes.
    ///
    /// - Returns: A stream that yields after any watched graph path changes.
    func changes() async -> AsyncStream<Void>
}

/// Composes discovery, OpenSSH resolution, metadata, and include-graph watching.
public actor SSHConfigurationCatalogSource: SSHConfigurationCatalogProviding {
    private let rootURL: URL
    private let discovery: SSHConfigAliasDiscovery
    private let resolver: any SSHEffectiveConfigurationResolving
    private let metadataStore: any TetherMetadataStoring
    private let watcher: any SSHConfigWatching

    /// Creates a catalog source.
    ///
    /// - Parameters:
    ///   - rootURL: The user's root SSH config.
    ///   - fileSystem: The injected configuration filesystem.
    ///   - resolver: The injected OpenSSH effective-config resolver.
    ///   - metadataStore: The presentation metadata repository.
    ///   - watcher: The include-graph watcher.
    public init(
        rootURL: URL,
        fileSystem: any SSHConfigFileSystem,
        resolver: any SSHEffectiveConfigurationResolving,
        metadataStore: any TetherMetadataStoring,
        watcher: any SSHConfigWatching
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.discovery = SSHConfigAliasDiscovery(fileSystem: fileSystem)
        self.resolver = resolver
        self.metadataStore = metadataStore
        self.watcher = watcher
    }

    public func loadCatalog() async -> SSHConfigurationCatalogPayload {
        let discoverySnapshot = await discovery.discover(rootURL: rootURL)
        var diagnostics = discoverySnapshot.diagnostics
        let metadata: TetherPresentationMetadata
        do {
            metadata = try await metadataStore.load()
        } catch let error as TetherMetadataStoreError {
            metadata = TetherPresentationMetadata()
            let message: String
            switch error {
            case .unsupportedVersion:
                message = "Tether metadata is from a newer version."
            case .malformed:
                message = "Tether metadata could not be read."
            }
            diagnostics.append(
                SSHConfigDiagnostic(
                    url: nil,
                    line: nil,
                    severity: .warning,
                    message: message
                )
            )
        } catch {
            metadata = TetherPresentationMetadata()
            diagnostics.append(
                SSHConfigDiagnostic(
                    url: nil,
                    line: nil,
                    severity: .warning,
                    message: "Tether metadata could not be read."
                )
            )
        }

        var seenAliases: Set<String> = []
        var items: [SSHConfigurationCatalogItem] = []
        for discovered in discoverySnapshot.aliases where seenAliases.insert(discovered.alias).inserted {
            var effective: SSHEffectiveConfiguration?
            do {
                effective = try await resolver.resolve(alias: discovered.alias)
            } catch let error as SSHConfigurationResolutionError {
                let message: String
                switch error {
                case .invalidAlias:
                    message = "SSH alias could not be resolved safely."
                case .commandFailed(let detail):
                    message = detail
                case .emptyResult:
                    message = "OpenSSH returned no effective configuration."
                }
                diagnostics.append(
                    SSHConfigDiagnostic(
                        url: discovered.source.url,
                        line: discovered.source.line,
                        severity: .warning,
                        message: message
                    )
                )
            } catch {
                diagnostics.append(
                    SSHConfigDiagnostic(
                        url: discovered.source.url,
                        line: discovered.source.line,
                        severity: .warning,
                        message: "OpenSSH could not resolve this alias."
                    )
                )
            }
            items.append(
                SSHConfigurationCatalogItem(
                    alias: discovered.alias,
                    source: discovered.source,
                    effective: effective,
                    presentation: metadata.servers[discovered.alias] ?? TetherServerPresentation()
                )
            )
        }

        await watcher.watch(urls: discoverySnapshot.includedFiles + [rootURL])
        return SSHConfigurationCatalogPayload(
            items: items,
            includedFiles: discoverySnapshot.includedFiles,
            diagnostics: diagnostics,
            recentAliases: metadata.recentAliases
        )
    }

    public func recordRecent(alias: String) async {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty else { return }
        guard var metadata = try? await metadataStore.load() else { return }
        metadata.recentAliases = [trimmedAlias] + metadata.recentAliases.filter { $0 != trimmedAlias }
        try? await metadataStore.save(metadata)
    }

    public func updateTags(alias: String, tags: [String]) async -> Bool {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlias.isEmpty,
              var metadata = try? await metadataStore.load() else {
            return false
        }
        var presentation = metadata.servers[trimmedAlias] ?? TetherServerPresentation()
        presentation.tags = tags
        metadata.servers[trimmedAlias] = presentation
        do {
            try await metadataStore.save(metadata)
            return true
        } catch {
            return false
        }
    }

    public func changes() async -> AsyncStream<Void> {
        await watcher.changes()
    }
}
