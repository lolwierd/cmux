import CmuxCommandPalette
import CmuxSSHServers
import Foundation

extension ContentView {
    /// Stable command ids let the normal command-palette search/indexing path
    /// handle every discovered server without introducing a second picker.
    static func tetherServerCommandID(alias: String) -> String {
        let encoded = Data(alias.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "palette.tether.connect.\(encoded)"
    }

    static func tetherServerSubtitle(_ server: SSHServer) -> String {
        let destination = [server.user, Optional(server.hostname)]
            .compactMap { $0 }
            .joined(separator: "@")
        let target: String
        if let port = server.port, port != 22 {
            target = "\(destination):\(port)"
        } else {
            target = destination
        }
        let format = String(
            localized: "tether.commandPalette.server.subtitle",
            defaultValue: "SSH Server • %@"
        )
        return String(format: format, target)
    }

    func tetherServerCommandPaletteContributions() -> [CommandPaletteCommandContribution] {
        tetherServerCatalog.servers.map { server in
            let commandID = Self.tetherServerCommandID(alias: server.alias)
            var keywords = ["tether", "ssh", "connect", server.alias, server.hostname]
            if let user = server.user { keywords.append(user) }
            keywords.append(contentsOf: server.presentation.tags)
            if let note = server.presentation.note { keywords.append(note) }
            return CommandPaletteCommandContribution(
                commandId: commandID,
                title: { _ in server.alias },
                subtitle: { _ in Self.tetherServerSubtitle(server) },
                keywords: keywords
            )
        }
    }

    func registerTetherServerCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        for server in tetherServerCatalog.servers {
            let commandID = Self.tetherServerCommandID(alias: server.alias)
            registry.register(commandId: commandID) {
                _ = tetherConnectionCoordinator.connect(server: server)
            }
        }
    }
}
