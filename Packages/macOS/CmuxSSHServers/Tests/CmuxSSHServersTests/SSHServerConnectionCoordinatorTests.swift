import Foundation
import Testing
@testable import CmuxSSHServers
@testable import CmuxSSHConfig

@MainActor @Suite struct SSHServerConnectionCoordinatorTests {
    @Test func acceptedLaunchUsesExactAliasAndRecordsRecency() async {
        let source = RecordingCatalogSource(payload: Self.payload(alias: "prod-box"))
        let catalog = SSHServerCatalog(source: source)
        await catalog.refresh()
        let launcher = RecordingLauncher(accepted: true)
        let coordinator = SSHServerConnectionCoordinator(catalog: catalog, launcher: launcher)

        #expect(coordinator.connect(alias: "prod-box"))
        #expect(launcher.aliases == ["prod-box"])
        #expect(launcher.focusValues == [true])
        #expect(coordinator.status(for: "prod-box") == .connecting(target: "dev@example.com"))

        for _ in 0..<8 where catalog.recentAliases != ["prod-box"] {
            await Task.yield()
        }
        #expect(catalog.recentAliases == ["prod-box"])
        #expect(await source.recordedAliases() == ["prod-box"])
    }

    @Test func launchCompletionUpdatesOnlyTheCurrentRequest() async {
        let source = RecordingCatalogSource(payload: Self.payload(alias: "prod-box"))
        let catalog = SSHServerCatalog(source: source)
        await catalog.refresh()
        let launcher = RecordingLauncher(accepted: true)
        let coordinator = SSHServerConnectionCoordinator(catalog: catalog, launcher: launcher)

        #expect(coordinator.connect(alias: "prod-box"))
        #expect(coordinator.connect(alias: "prod-box"))
        launcher.finish(.failed(message: "old failure"), requestIndex: 0)
        await Task.yield()
        #expect(coordinator.status(for: "prod-box") == .connecting(target: "dev@example.com"))

        launcher.finish(.ready, requestIndex: 1)
        for _ in 0..<8 where coordinator.status(for: "prod-box") != .ready(target: "dev@example.com") {
            await Task.yield()
        }
        #expect(coordinator.status(for: "prod-box") == .ready(target: "dev@example.com"))
    }

    @Test func rejectedLaunchDoesNotRecordRecency() async {
        let source = RecordingCatalogSource(payload: Self.payload(alias: "offline"))
        let catalog = SSHServerCatalog(source: source)
        await catalog.refresh()
        let launcher = RecordingLauncher(accepted: false)
        let coordinator = SSHServerConnectionCoordinator(catalog: catalog, launcher: launcher)

        #expect(!coordinator.connect(alias: "offline"))
        await Task.yield()
        #expect(catalog.recentAliases.isEmpty)
        #expect(await source.recordedAliases().isEmpty)
    }

    private static func payload(alias: String) -> SSHConfigurationCatalogPayload {
        SSHConfigurationCatalogPayload(
            items: [
                SSHConfigurationCatalogItem(
                    alias: alias,
                    source: SSHConfigSourceLocation(
                        url: URL(fileURLWithPath: "/tmp/config"),
                        line: 1
                    ),
                    effective: SSHEffectiveConfiguration(
                        alias: alias,
                        hostname: "example.com",
                        user: "dev",
                        port: 22,
                        identityFiles: [],
                        proxyJump: nil
                    ),
                    presentation: TetherServerPresentation()
                )
            ],
            includedFiles: [],
            diagnostics: [],
            recentAliases: []
        )
    }
}

private actor RecordingCatalogSource: SSHConfigurationCatalogProviding {
    private let payload: SSHConfigurationCatalogPayload
    private var aliases: [String] = []

    init(payload: SSHConfigurationCatalogPayload) {
        self.payload = payload
    }

    func loadCatalog() async -> SSHConfigurationCatalogPayload {
        payload
    }

    func recordRecent(alias: String) async {
        aliases.append(alias)
    }

    func updateTags(alias: String, tags: [String]) async -> Bool {
        true
    }

    func changes() async -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func recordedAliases() -> [String] {
        aliases
    }
}

@MainActor private final class RecordingLauncher: SSHServerConnectionLaunching {
    let accepted: Bool
    private(set) var aliases: [String] = []
    private var continuations: [AsyncStream<SSHServerConnectionLaunchEvent>.Continuation] = []

    init(accepted: Bool) {
        self.accepted = accepted
    }

    func launchSSH(alias: String, focus: Bool) -> SSHServerConnectionLaunch {
        aliases.append(alias)
        focusValues.append(focus)
        let (events, continuation) = AsyncStream<SSHServerConnectionLaunchEvent>.makeStream()
        continuations.append(continuation)
        return SSHServerConnectionLaunch(accepted: accepted, events: events)
    }

    func finish(_ event: SSHServerConnectionLaunchEvent, requestIndex: Int) {
        guard continuations.indices.contains(requestIndex) else { return }
        continuations[requestIndex].yield(event)
        continuations[requestIndex].finish()
    }

    private(set) var focusValues: [Bool] = []
}
