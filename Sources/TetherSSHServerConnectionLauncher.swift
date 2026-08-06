import AppKit
import CmuxSSHServers

/// App-target adapter for Tether's shared server connection action.
///
/// The existing bundled CLI remains the owner of SSH workspace creation. This
/// adapter only supplies the selected alias and the current window for errors.
@MainActor
final class TetherSSHServerConnectionLauncher: SSHServerConnectionLaunching {
    func launchSSH(alias: String, focus: Bool) -> SSHServerConnectionLaunch {
        let (events, continuation) = AsyncStream<SSHServerConnectionLaunchEvent>.makeStream()
        let accepted = CmuxSSHURLProcessLauncher.shared.startSSH(
            destination: alias,
            preferredWindow: NSApp.keyWindow ?? NSApp.mainWindow,
            focus: focus,
            onCompletion: { event in
                continuation.yield(event)
                continuation.finish()
            }
        )
        if !accepted {
            continuation.finish()
        }
        return SSHServerConnectionLaunch(accepted: accepted, events: events)
    }
}
