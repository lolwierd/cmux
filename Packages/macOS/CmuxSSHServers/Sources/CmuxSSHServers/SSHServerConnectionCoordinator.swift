import Foundation
public import Observation

/// Reports the terminal-side outcome of an accepted SSH launch.
public enum SSHServerConnectionLaunchEvent: Equatable, Sendable {
    /// The SSH terminal launch was accepted by cmux.
    case ready
    /// The SSH workspace launch failed before it could be accepted.
    case failed(message: String)
}

/// Carries immediate acceptance and later lifecycle events for one SSH launch.
public struct SSHServerConnectionLaunch: Sendable {
    /// Whether cmux accepted the launch request and started its SSH workflow.
    public let accepted: Bool
    /// Later completion events from the app-owned SSH launcher.
    public let events: AsyncStream<SSHServerConnectionLaunchEvent>

    /// Creates a launch result.
    ///
    /// - Parameters:
    ///   - accepted: Whether the SSH workflow started.
    ///   - events: The stream that reports the eventual workflow result.
    public init(
        accepted: Bool,
        events: AsyncStream<SSHServerConnectionLaunchEvent>
    ) {
        self.accepted = accepted
        self.events = events
    }
}

/// The app-owned launch seam for an accepted Tether server connection.
///
/// The concrete app adapter is responsible for invoking cmux's existing SSH
/// workflow. Keeping that adapter outside this package lets the catalog and UI
/// remain testable without starting a process or opening a real remote host.
@MainActor public protocol SSHServerConnectionLaunching {
    /// Starts cmux's SSH terminal workflow for a literal alias.
    ///
    /// - Parameters:
    ///   - alias: The exact alias selected by the user.
    ///   - focus: Whether the accepted workspace should become foreground.
    /// - Returns: Immediate acceptance plus later launch lifecycle events.
    func launchSSH(alias: String, focus: Bool) -> SSHServerConnectionLaunch
}

    /// The state shown beside a server while its SSH terminal is being opened.
public enum SSHServerConnectionStatus: Equatable, Sendable {
    /// The cmux SSH workflow has started for the resolved target.
    case connecting(target: String)
    /// The SSH terminal was created in the selected workspace.
    case ready(target: String)
    /// The workflow failed before the SSH terminal was created.
    case failed(target: String, message: String)
}

/// The single connection action shared by Tether entry points.
@MainActor @Observable public final class SSHServerConnectionCoordinator {
    private let catalog: SSHServerCatalog
    private let launcher: any SSHServerConnectionLaunching
    private var activeRequestIDs: [String: UUID] = [:]

    /// The latest launch status keyed by the literal SSH alias.
    public private(set) var statuses: [String: SSHServerConnectionStatus] = [:]

    /// Creates a coordinator with an injected catalog and app launcher.
    ///
    /// - Parameters:
    ///   - catalog: The catalog used to resolve aliases and record recency.
    ///   - launcher: The app-owned adapter for cmux's SSH workflow.
    public init(
        catalog: SSHServerCatalog,
        launcher: any SSHServerConnectionLaunching
    ) {
        self.catalog = catalog
        self.launcher = launcher
    }

    /// Connects the catalog server identified by `alias`.
    ///
    /// Recency is recorded only after the launcher accepts the request. A
    /// later SSH authentication or network failure therefore cannot make a
    /// server look recently used merely because its row was clicked.
    ///
    /// - Parameters:
    ///   - alias: The literal SSH alias.
    ///   - focus: Whether the accepted workspace should become foreground.
    /// - Returns: `true` when cmux accepted the launch request.
    @discardableResult
    public func connect(alias: String, focus: Bool = true) -> Bool {
        guard let server = catalog.servers.first(where: { $0.alias == alias }) else {
            return false
        }
        return connect(server: server, focus: focus)
    }

    /// Connects one catalog server through the shared action path.
    ///
    /// - Parameters:
    ///   - server: The server selected by a row, palette entry, or another UI
    ///     entry point.
    ///   - focus: Whether the accepted workspace should become foreground.
    /// - Returns: `true` when cmux accepted the launch request.
    @discardableResult
    public func connect(server: SSHServer, focus: Bool = true) -> Bool {
        let requestID = UUID()
        activeRequestIDs[server.alias] = requestID
        let target = server.displayDestination
        let launch = launcher.launchSSH(alias: server.alias, focus: focus)
        guard launch.accepted else {
            statuses[server.alias] = .failed(
                target: target,
                message: ""
            )
            return false
        }

        statuses[server.alias] = .connecting(target: target)
        Task { @MainActor [weak self, events = launch.events, alias = server.alias, requestID, target] in
            for await event in events {
                guard let self, self.activeRequestIDs[alias] == requestID else { return }
                switch event {
                case .ready:
                    self.statuses[alias] = .ready(target: target)
                case let .failed(message):
                    self.statuses[alias] = .failed(
                        target: target,
                        message: message
                    )
                }
            }
        }
        Task { [catalog, alias = server.alias] in
            await catalog.recordRecent(alias: alias)
        }
        return true
    }

    /// Returns the latest visible connection status for one alias.
    ///
    /// - Parameter alias: The literal SSH alias.
    /// - Returns: The latest status, when the alias has been launched in this app session.
    public func status(for alias: String) -> SSHServerConnectionStatus? {
        statuses[alias]
    }
}
