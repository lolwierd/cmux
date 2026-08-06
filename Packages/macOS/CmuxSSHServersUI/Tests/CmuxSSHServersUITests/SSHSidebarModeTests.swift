import Testing
@testable import CmuxSSHServersUI

@Suite struct SSHSidebarModeTests {
    @Test func modeRawValuesRemainStable() {
        #expect(SSHSidebarMode.workspaces.rawValue == "workspaces")
        #expect(SSHSidebarMode.servers.rawValue == "servers")
    }
}
