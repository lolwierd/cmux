public import CmuxSSHConfig

/// A selectable SSH alias with effective OpenSSH values and local presentation data.
public struct SSHServer: Codable, Hashable, Sendable, Identifiable {
    /// The literal alias passed to OpenSSH.
    public let alias: String
    /// The first source location that declared the alias.
    public let source: SSHConfigSourceLocation
    /// Effective values from `ssh -G`, when resolution succeeded.
    public let effective: SSHEffectiveConfiguration?
    /// Presentation-only metadata.
    public let presentation: TetherServerPresentation

    /// The alias is unique within a catalog.
    public var id: String { alias }
    /// The resolved hostname, falling back to the alias when unresolved.
    public var hostname: String { effective?.hostname ?? alias }
    /// The resolved user, when OpenSSH supplied one.
    public var user: String? { effective?.user }
    /// The resolved port, when OpenSSH supplied one.
    public var port: Int? { effective?.port }
    /// The resolved jump host, when configured.
    public var proxyJump: String? { effective?.proxyJump }

    /// The resolved user, host, and non-default port shown during connection.
    public var displayDestination: String {
        let destination = [user, Optional(hostname)]
            .compactMap { $0 }
            .joined(separator: "@")
        guard let port, port != 22 else { return destination }
        return "\(destination):\(port)"
    }

    /// Creates a server from one configuration catalog item.
    ///
    /// - Parameter item: The assembled configuration item.
    public init(item: SSHConfigurationCatalogItem) {
        self.alias = item.alias
        self.source = item.source
        self.effective = item.effective
        self.presentation = item.presentation
    }

    /// Creates a server value directly for tests and injected catalogs.
    ///
    /// - Parameters:
    ///   - alias: The literal alias.
    ///   - source: The source location.
    ///   - effective: Effective OpenSSH values.
    ///   - presentation: Presentation metadata.
    public init(
        alias: String,
        source: SSHConfigSourceLocation,
        effective: SSHEffectiveConfiguration?,
        presentation: TetherServerPresentation = TetherServerPresentation()
    ) {
        self.alias = alias
        self.source = source
        self.effective = effective
        self.presentation = presentation
    }
}

/// A deterministic tag group for sidebar presentation.
public struct SSHServerTagGroup: Hashable, Sendable, Identifiable {
    /// The normalized display tag.
    public let tag: String
    /// Servers carrying the tag, sorted by alias.
    public let servers: [SSHServer]

    /// The tag itself is the stable group identity.
    public var id: String { tag }

    /// Creates a tag group.
    ///
    /// - Parameters:
    ///   - tag: The display tag.
    ///   - servers: Servers assigned to the tag.
    public init(tag: String, servers: [SSHServer]) {
        self.tag = tag
        self.servers = servers
    }
}
