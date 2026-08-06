import Foundation

/// Errors raised while asking OpenSSH to resolve an alias.
public enum SSHConfigurationResolutionError: Error, Sendable, Equatable {
    /// The alias could be interpreted as a command-line option or contains control characters.
    case invalidAlias
    /// OpenSSH returned a non-zero status.
    case commandFailed(String)
    /// OpenSSH returned no usable effective configuration.
    case emptyResult
}

/// Resolves effective values through the installed OpenSSH client.
public actor OpenSSHConfigurationResolver: SSHEffectiveConfigurationResolving {
    private let commandRunner: any SSHCommandRunning
    private let executable: String

    /// Creates an OpenSSH resolver.
    ///
    /// - Parameters:
    ///   - commandRunner: The injected argument-array command runner.
    ///   - executable: The OpenSSH executable, defaulting to the system client.
    public init(
        commandRunner: any SSHCommandRunning,
        executable: String = "/usr/bin/ssh"
    ) {
        self.commandRunner = commandRunner
        self.executable = executable
    }

    /// Resolves one alias with `ssh -G`.
    ///
    /// - Parameter alias: The original literal alias.
    /// - Returns: The effective OpenSSH values.
    /// - Throws: ``SSHConfigurationResolutionError`` or a command setup error.
    public func resolve(alias: String) async throws -> SSHEffectiveConfiguration {
        guard isSafeAlias(alias) else {
            throw SSHConfigurationResolutionError.invalidAlias
        }
        let result = try await commandRunner.run(
            executable: executable,
            arguments: ["-G", alias]
        )
        guard result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHConfigurationResolutionError.commandFailed(detail.isEmpty ? "OpenSSH failed." : detail)
        }
        let values = EffectiveValues(output: result.stdout).values
        guard !values.isEmpty else {
            throw SSHConfigurationResolutionError.emptyResult
        }
        return SSHEffectiveConfiguration(
            alias: alias,
            hostname: values["hostname"]?.first,
            user: values["user"]?.first,
            port: values["port"]?.first.flatMap(Int.init),
            identityFiles: values["identityfile"] ?? [],
            proxyJump: values["proxyjump"]?.first
        )
    }

    private func isSafeAlias(_ alias: String) -> Bool {
        !alias.isEmpty
            && !alias.hasPrefix("-")
            && !alias.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    private struct EffectiveValues {
        var values: [String: [String]] = [:]

        init(output: String) {
            for line in output.split(whereSeparator: \.isNewline) {
                let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard pieces.count == 2 else { continue }
                values[String(pieces[0]).lowercased(), default: []].append(String(pieces[1]))
            }
        }
    }
}

/// Resolves effective OpenSSH settings for a literal alias.
public protocol SSHEffectiveConfigurationResolving: Sendable {
    /// Resolves the alias through OpenSSH.
    ///
    /// - Parameter alias: The literal alias passed to OpenSSH.
    /// - Returns: The effective configuration.
    /// - Throws: A resolution or command error.
    func resolve(alias: String) async throws -> SSHEffectiveConfiguration
}
