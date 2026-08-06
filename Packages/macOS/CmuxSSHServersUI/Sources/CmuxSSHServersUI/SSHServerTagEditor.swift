import SwiftUI
import CmuxSSHServers

/// A compact editor for the comma-separated tags assigned to one SSH server.
struct SSHServerTagEditor: View {
    let server: SSHServer
    let onSave: @MainActor ([String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var tagText: String
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        server: SSHServer,
        onSave: @escaping @MainActor ([String]) async -> Bool
    ) {
        self.server = server
        self.onSave = onSave
        self._tagText = State(initialValue: server.presentation.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                String(
                    format: String(
                        localized: "tether.sidebar.tags.editor.title",
                        defaultValue: "Tags for %@"
                    ),
                    server.alias
                )
            )
            .font(.headline)

            TextField(
                String(
                    localized: "tether.sidebar.tags.editor.placeholder",
                    defaultValue: "production, web"
                ),
                text: $tagText
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("TetherServerTagEditorField")

            Text(
                String(
                    localized: "tether.sidebar.tags.editor.help",
                    defaultValue: "Separate tags with commas. Leave empty to remove all tags."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if saveFailed {
                Text(
                    String(
                        localized: "tether.sidebar.tags.editor.saveFailed",
                        defaultValue: "Could not save tags."
                    )
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            HStack {
                Spacer(minLength: 0)
                Button(
                    String(localized: "common.cancel", defaultValue: "Cancel")
                ) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("TetherServerTagEditorCancel")
                Button {
                    Task { @MainActor in
                        isSaving = true
                        saveFailed = !(await onSave(parsedTags))
                        isSaving = false
                        if !saveFailed {
                            dismiss()
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "tether.sidebar.tags.editor.save", defaultValue: "Save"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .accessibilityIdentifier("TetherServerTagEditorSave")
            }
        }
        .padding(16)
        .frame(width: 300)
        .accessibilityIdentifier("TetherServerTagEditor")
    }

    private var parsedTags: [String] {
        tagText.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
}
