import Foundation
import Testing
@testable import CmuxSSHServers
@testable import CmuxSSHConfig

@Suite struct SSHServerSearchTests {
    @Test func aliasPrefixRanksAheadOfTagHostnameUserAndNoteMatches() {
        let source = SSHConfigSourceLocation(
            url: URL(fileURLWithPath: "/tmp/config"),
            line: 1
        )
        let servers = [
            SSHServer(
                alias: "database",
                source: source,
                effective: SSHEffectiveConfiguration(
                    alias: "database",
                    hostname: "db.example.com",
                    user: "deploy",
                    port: 22,
                    identityFiles: [],
                    proxyJump: nil
                ),
                presentation: TetherServerPresentation(tags: ["production"], note: "primary")
            ),
            SSHServer(
                alias: "prod-web",
                source: source,
                effective: SSHEffectiveConfiguration(
                    alias: "prod-web",
                    hostname: "web.example.com",
                    user: "admin",
                    port: 22,
                    identityFiles: [],
                    proxyJump: nil
                )
            ),
        ]

        let ranked = SSHServerSearch().rank(servers, query: "prod")

        #expect(ranked.map { $0.alias } == ["prod-web", "database"])
        #expect(SSHServerSearch().rank(servers, query: "production").first?.alias == "database")
        #expect(SSHServerSearch().rank(servers, query: "web.example").first?.alias == "prod-web")
    }

    @Test func tiesAreStableAndEmptyQueriesAreAlphabetical() {
        let source = SSHConfigSourceLocation(url: URL(fileURLWithPath: "/tmp/config"), line: 1)
        let servers = [
            SSHServer(alias: "zeta", source: source, effective: nil),
            SSHServer(alias: "alpha", source: source, effective: nil),
        ]

        #expect(SSHServerSearch().rank(servers, query: "").map { $0.alias } == ["alpha", "zeta"])
    }

    @Test @MainActor func tagFilterShowsAvailableTagsAndCombinesWithSearch() async {
        let source = SSHConfigSourceLocation(url: URL(fileURLWithPath: "/tmp/config"), line: 1)
        let catalogSource = StaticSSHServerCatalogSource(
            items: [
                SSHConfigurationCatalogItem(
                    alias: "prod-web",
                    source: source,
                    effective: nil,
                    presentation: TetherServerPresentation(tags: ["Production", "web"])
                ),
                SSHConfigurationCatalogItem(
                    alias: "prod-db",
                    source: source,
                    effective: nil,
                    presentation: TetherServerPresentation(tags: ["production", "database"])
                ),
                SSHConfigurationCatalogItem(
                    alias: "dev-web",
                    source: source,
                    effective: nil,
                    presentation: TetherServerPresentation(tags: ["web"])
                ),
            ]
        )
        let catalog = SSHServerCatalog(source: catalogSource)
        await catalog.refresh()

        #expect(catalog.availableTags == ["database", "Production", "web"])
        #expect(catalog.visibleServers.map(\.alias) == ["dev-web", "prod-db", "prod-web"])

        catalog.selectedTag = "Production"
        #expect(catalog.visibleServers.map(\.alias) == ["prod-db", "prod-web"])

        catalog.searchQuery = "web"
        #expect(catalog.visibleServers.map(\.alias) == ["prod-web"])

        catalog.selectedTag = nil
        #expect(catalog.visibleServers.map(\.alias) == ["dev-web", "prod-web"])

        let didUpdate = await catalog.updateTags(alias: "dev-web", tags: [" internal ", "Internal", "ops"])
        #expect(didUpdate)
        #expect(catalog.servers.first(where: { $0.alias == "dev-web" })?.presentation.tags == ["internal", "ops"])
        #expect(catalog.availableTags == ["database", "internal", "ops", "Production", "web"])
    }
}

private actor StaticSSHServerCatalogSource: SSHConfigurationCatalogProviding {
    private let payload: SSHConfigurationCatalogPayload

    init(items: [SSHConfigurationCatalogItem]) {
        payload = SSHConfigurationCatalogPayload(
            items: items,
            includedFiles: [],
            diagnostics: [],
            recentAliases: []
        )
    }

    func loadCatalog() async -> SSHConfigurationCatalogPayload {
        payload
    }

    func recordRecent(alias: String) async {}

    func updateTags(alias: String, tags: [String]) async -> Bool {
        true
    }

    func changes() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
