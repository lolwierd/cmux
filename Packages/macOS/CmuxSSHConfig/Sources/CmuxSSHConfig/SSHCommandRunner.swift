import Foundation

/// The bounded result of one external command invocation.
public struct SSHCommandResult: Sendable, Equatable {
    /// The process exit status.
    public let status: Int32
    /// Standard output decoded as UTF-8.
    public let stdout: String
    /// Standard error decoded as UTF-8.
    public let stderr: String

    /// Creates a command result.
    ///
    /// - Parameters:
    ///   - status: The process exit status.
    ///   - stdout: Standard output.
    ///   - stderr: Standard error.
    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// The argument-array seam for system tools such as `/usr/bin/ssh`.
public protocol SSHCommandRunning: Sendable {
    /// Runs one executable without invoking a shell.
    ///
    /// - Parameters:
    ///   - executable: An absolute executable path.
    ///   - arguments: Argument tokens passed unchanged to the executable.
    /// - Returns: The bounded process result.
    /// - Throws: Process setup or launch errors.
    func run(executable: String, arguments: [String]) async throws -> SSHCommandResult
}

/// Runs local system commands from an isolated actor.
public actor LocalSSHCommandRunner: SSHCommandRunning {
    /// Creates a local command runner.
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> SSHCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let stdoutTask = Task.detached(priority: .utility) {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached(priority: .utility) {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value
        return SSHCommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self)
        )
    }
}
