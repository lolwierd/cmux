import Foundation
import Testing
@testable import CmuxSSHConfig

@Suite struct SSHConfigAliasDiscoveryTests {
    @Test func discoversNestedIncludesGlobbedFilesAndLiteralAliases() async throws {
        let root = try TemporaryConfigTree()
        try root.write(
            """
            Host prod-web deploy@prod
                HostName web.example.com
            Include config.d/*.conf
            """,
            at: "config"
        )
        try root.write(
            """
            # Wildcards affect resolution but are not selectable aliases.
            Host *.example.com !ignored
            Include nested.conf
            """,
            at: "config.d/servers.conf"
        )
        try root.write("Host staging\n", at: "config.d/nested.conf")

        let snapshot = await SSHConfigAliasDiscovery(
            fileSystem: LocalSSHConfigFileSystem(homeDirectory: root.url)
        ).discover(rootURL: root.url.appendingPathComponent("config"))

        #expect(snapshot.aliases.map { $0.alias } == ["prod-web", "deploy@prod", "staging"])
        #expect(snapshot.includedFiles.count == 3)
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test func cyclesAndMissingIncludesKeepValidAliases() async throws {
        let root = try TemporaryConfigTree()
        try root.write("Host first\nInclude second.conf\nInclude missing.conf\n", at: "config")
        try root.write("Host second\nInclude config\n", at: "second.conf")

        let snapshot = await SSHConfigAliasDiscovery(
            fileSystem: LocalSSHConfigFileSystem(homeDirectory: root.url)
        ).discover(rootURL: root.url.appendingPathComponent("config"))

        #expect(snapshot.aliases.map { $0.alias } == ["first", "second"])
        #expect(snapshot.diagnostics.contains { $0.message.contains("cycle") })
        #expect(snapshot.diagnostics.contains { $0.message.contains("not found") })
    }

    @Test func parsesQuotedAndEqualsSyntaxWithoutTreatingWildcardsAsRows() async throws {
        let root = try TemporaryConfigTree()
        try root.write(
            """
            Host=quoted-name "second name"
            Host !excluded * ?wildcard
            """,
            at: "config"
        )

        let snapshot = await SSHConfigAliasDiscovery(
            fileSystem: LocalSSHConfigFileSystem(homeDirectory: root.url)
        ).discover(rootURL: root.url.appendingPathComponent("config"))

        #expect(snapshot.aliases.map { $0.alias } == ["quoted-name", "second name"])
    }
}

private struct TemporaryConfigTree {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-ssh-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ contents: String, at relativePath: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
    }
}
