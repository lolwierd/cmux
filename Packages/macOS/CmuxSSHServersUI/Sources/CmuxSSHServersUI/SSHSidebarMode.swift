public import SwiftUI

/// The two primary surfaces exposed by the left sidebar.
public enum SSHSidebarMode: String, CaseIterable, Sendable, Equatable {
    /// The existing cmux workspace list.
    case workspaces
    /// The read-only Tether server catalog.
    case servers
}

/// A compact mode switcher for the existing cmux sidebar.
public struct SSHSidebarModePicker: View {
    @Binding private var selection: SSHSidebarMode

    /// Creates a mode picker.
    ///
    /// - Parameter selection: The persisted sidebar mode binding.
    public init(selection: Binding<SSHSidebarMode>) {
        self._selection = selection
    }

    public var body: some View {
        Picker(
            String(localized: "tether.sidebar.mode.label", defaultValue: "Sidebar mode"),
            selection: $selection
        ) {
            Text(String(localized: "tether.sidebar.mode.workspaces", defaultValue: "Workspaces"))
                .tag(SSHSidebarMode.workspaces)
            Text(String(localized: "tether.sidebar.mode.servers", defaultValue: "Servers"))
                .tag(SSHSidebarMode.servers)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(String(localized: "tether.sidebar.mode.label", defaultValue: "Sidebar mode"))
    }
}
