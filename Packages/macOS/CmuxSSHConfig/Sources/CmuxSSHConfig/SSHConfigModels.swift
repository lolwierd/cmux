public import Foundation

/// Identifies the file and line that contributed an SSH configuration value.
public struct SSHConfigSourceLocation: Codable, Hashable, Sendable {
    /// The configuration file containing the directive.
    public let url: URL
    /// The one-based line number of the directive.
    public let line: Int

    /// Creates a source location for an SSH configuration directive.
    ///
    /// - Parameters:
    ///   - url: The configuration file URL.
    ///   - line: The one-based line number.
    public init(url: URL, line: Int) {
        self.url = url
        self.line = line
    }
}

/// A literal alias found in an SSH `Host` declaration.
public struct SSHDiscoveredAlias: Codable, Hashable, Sendable, Identifiable {
    /// The alias passed to `/usr/bin/ssh`.
    public let alias: String
    /// The source location of the `Host` declaration.
    public let source: SSHConfigSourceLocation

    /// A stable identity for the occurrence, including its source location.
    public var id: String {
        "\(source.url.standardizedFileURL.path):\(source.line):\(alias)"
    }

    /// Creates a discovered alias.
    ///
    /// - Parameters:
    ///   - alias: The literal SSH alias.
    ///   - source: The source location of its declaration.
    public init(alias: String, source: SSHConfigSourceLocation) {
        self.alias = alias
        self.source = source
    }
}

/// The severity of a diagnostic found while walking the SSH include graph.
public enum SSHConfigDiagnosticSeverity: String, Codable, Sendable, Equatable {
    /// The catalog can continue using the affected part of the graph.
    case warning
    /// The affected file or alias could not be inspected.
    case error
}

/// A non-fatal problem encountered while reading or resolving SSH configuration.
public struct SSHConfigDiagnostic: Codable, Hashable, Sendable, Identifiable {
    /// The file associated with the problem, when one is known.
    public let url: URL?
    /// The line associated with the problem, when one is known.
    public let line: Int?
    /// The severity of the problem.
    public let severity: SSHConfigDiagnosticSeverity
    /// A safe, user-facing explanation that excludes command environments.
    public let message: String

    /// A stable identity for presenting and diffing diagnostics.
    public var id: String {
        "\(url?.path ?? ""):\(line.map(String.init) ?? ""):\(severity.rawValue):\(message)"
    }

    /// Creates a configuration diagnostic.
    ///
    /// - Parameters:
    ///   - url: The relevant file URL.
    ///   - line: The relevant one-based line number.
    ///   - severity: The diagnostic severity.
    ///   - message: A safe explanation of the problem.
    public init(
        url: URL?,
        line: Int?,
        severity: SSHConfigDiagnosticSeverity,
        message: String
    ) {
        self.url = url
        self.line = line
        self.severity = severity
        self.message = message
    }
}

/// The result of walking an SSH configuration and all reachable includes.
public struct SSHConfigDiscoverySnapshot: Sendable, Equatable {
    /// Every literal alias occurrence, in source traversal order.
    public let aliases: [SSHDiscoveredAlias]
    /// Existing files visited while walking the include graph.
    public let includedFiles: [URL]
    /// Problems encountered without discarding valid aliases.
    public let diagnostics: [SSHConfigDiagnostic]

    /// Creates a discovery snapshot.
    ///
    /// - Parameters:
    ///   - aliases: Alias occurrences in traversal order.
    ///   - includedFiles: Existing files in the include graph.
    ///   - diagnostics: Non-fatal diagnostics collected during traversal.
    public init(
        aliases: [SSHDiscoveredAlias],
        includedFiles: [URL],
        diagnostics: [SSHConfigDiagnostic]
    ) {
        self.aliases = aliases
        self.includedFiles = includedFiles
        self.diagnostics = diagnostics
    }
}

/// The effective values returned by `ssh -G` for a selected alias.
public struct SSHEffectiveConfiguration: Codable, Hashable, Sendable {
    /// The original alias used for resolution.
    public let alias: String
    /// The final hostname selected by OpenSSH.
    public let hostname: String?
    /// The effective login user.
    public let user: String?
    /// The effective TCP port.
    public let port: Int?
    /// Identity paths in the order reported by OpenSSH.
    public let identityFiles: [String]
    /// The effective jump host, if configured.
    public let proxyJump: String?

    /// Creates an effective OpenSSH configuration value.
    ///
    /// - Parameters:
    ///   - alias: The alias passed to OpenSSH.
    ///   - hostname: The resolved hostname.
    ///   - user: The resolved user.
    ///   - port: The resolved port.
    ///   - identityFiles: Identity paths reported by OpenSSH.
    ///   - proxyJump: The resolved jump host.
    public init(
        alias: String,
        hostname: String?,
        user: String?,
        port: Int?,
        identityFiles: [String],
        proxyJump: String?
    ) {
        self.alias = alias
        self.hostname = hostname
        self.user = user
        self.port = port
        self.identityFiles = identityFiles
        self.proxyJump = proxyJump
    }
}

/// Presentation-only data associated with an SSH alias.
public struct TetherServerPresentation: Codable, Hashable, Sendable {
    /// User-defined tags used for grouping and search.
    public var tags: [String]
    /// Whether the alias belongs in the favorites group.
    public var favorite: Bool
    /// A local note used for recognition and search.
    public var note: String?
    /// An optional row color name reserved for the UI.
    public var color: String?
    /// Whether a later connection action should ask for confirmation.
    public var confirmBeforeConnect: Bool

    /// Creates presentation metadata with empty, non-disruptive defaults.
    ///
    /// - Parameters:
    ///   - tags: User-defined tags.
    ///   - favorite: Whether the alias is a favorite.
    ///   - note: An optional local note.
    ///   - color: An optional local color name.
    ///   - confirmBeforeConnect: Whether a future connect action confirms first.
    public init(
        tags: [String] = [],
        favorite: Bool = false,
        note: String? = nil,
        color: String? = nil,
        confirmBeforeConnect: Bool = false
    ) {
        self.tags = tags
        self.favorite = favorite
        self.note = note
        self.color = color
        self.confirmBeforeConnect = confirmBeforeConnect
    }
}

/// Versioned presentation metadata stored separately from SSH configuration.
public struct TetherPresentationMetadata: Codable, Hashable, Sendable {
    /// The metadata schema version.
    public var version: Int
    /// Presentation metadata keyed by literal alias.
    public var servers: [String: TetherServerPresentation]
    /// Bounded most-recently-used aliases.
    public var recentAliases: [String]

    /// The current metadata schema version.
    public static let currentVersion = 1

    /// Creates empty metadata for the current schema.
    ///
    /// - Parameters:
    ///   - servers: Metadata keyed by alias.
    ///   - recentAliases: Most-recently-used aliases.
    public init(
        servers: [String: TetherServerPresentation] = [:],
        recentAliases: [String] = []
    ) {
        self.version = Self.currentVersion
        self.servers = servers
        self.recentAliases = Array(recentAliases.prefix(50))
    }
}

/// One fully assembled catalog item ready for the domain layer.
public struct SSHConfigurationCatalogItem: Codable, Hashable, Sendable, Identifiable {
    /// The literal alias.
    public let alias: String
    /// The source location of the first literal declaration.
    public let source: SSHConfigSourceLocation
    /// The effective values returned by OpenSSH, when resolution succeeded.
    public let effective: SSHEffectiveConfiguration?
    /// Presentation metadata keyed by the alias.
    public let presentation: TetherServerPresentation

    /// The alias is unique within an assembled catalog.
    public var id: String { alias }

    /// Creates a catalog item.
    ///
    /// - Parameters:
    ///   - alias: The literal alias.
    ///   - source: The first source location for the alias.
    ///   - effective: The resolved OpenSSH values.
    ///   - presentation: Presentation metadata.
    public init(
        alias: String,
        source: SSHConfigSourceLocation,
        effective: SSHEffectiveConfiguration?,
        presentation: TetherServerPresentation
    ) {
        self.alias = alias
        self.source = source
        self.effective = effective
        self.presentation = presentation
    }
}

/// The assembled read-only catalog and its diagnostics.
public struct SSHConfigurationCatalogPayload: Codable, Sendable, Equatable {
    /// Catalog items in discovery order.
    public let items: [SSHConfigurationCatalogItem]
    /// Files in the current include graph.
    public let includedFiles: [URL]
    /// Discovery and resolution diagnostics.
    public let diagnostics: [SSHConfigDiagnostic]
    /// Aliases ordered from newest to oldest use.
    public let recentAliases: [String]

    /// Creates a catalog payload.
    ///
    /// - Parameters:
    ///   - items: Catalog items.
    ///   - includedFiles: Include graph files.
    ///   - diagnostics: Collected diagnostics.
    ///   - recentAliases: Bounded recent alias history.
    public init(
        items: [SSHConfigurationCatalogItem],
        includedFiles: [URL],
        diagnostics: [SSHConfigDiagnostic],
        recentAliases: [String]
    ) {
        self.items = items
        self.includedFiles = includedFiles
        self.diagnostics = diagnostics
        self.recentAliases = Array(recentAliases.prefix(50))
    }
}
