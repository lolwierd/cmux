public import SwiftUI
public import CmuxSSHServers

/// A native sidebar surface for the read-only Tether server catalog.
public struct SSHServersSidebar: View {
    @Bindable private var catalog: SSHServerCatalog
    @Bindable private var connectionCoordinator: SSHServerConnectionCoordinator
    private let onSelect: @MainActor (SSHServer) -> Void
    private let onSelectInBackground: @MainActor (SSHServer) -> Void
    @State private var editingServer: SSHServer?

    /// Creates a Servers sidebar.
    ///
    /// - Parameters:
    ///   - catalog: The injected main-actor catalog model.
    ///   - connectionCoordinator: The shared connection model whose status is rendered beside each server.
    ///   - onSelect: The shared foreground connection action used by row clicks
    ///     and the context menu.
    ///   - onSelectInBackground: The shared background connection action used
    ///     by the context menu.
    public init(
        catalog: SSHServerCatalog,
        connectionCoordinator: SSHServerConnectionCoordinator,
        onSelect: @escaping @MainActor (SSHServer) -> Void = { _ in },
        onSelectInBackground: @escaping @MainActor (SSHServer) -> Void = { _ in }
    ) {
        self._catalog = Bindable(wrappedValue: catalog)
        self._connectionCoordinator = Bindable(wrappedValue: connectionCoordinator)
        self.onSelect = onSelect
        self.onSelectInBackground = onSelectInBackground
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if !catalog.availableTags.isEmpty {
                tagFilterBar
            }
            Divider()
            if catalog.isLoading && catalog.servers.isEmpty {
                loadingState
            } else if catalog.servers.isEmpty {
                emptyState
            } else if catalog.visibleServers.isEmpty {
                noResultsState
            } else {
                catalogList
            }
            diagnosticsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { catalog.start() }
        .onDisappear { catalog.stop() }
        .popover(item: $editingServer) { server in
            SSHServerTagEditor(server: server) { tags in
                let didSave = await catalog.updateTags(alias: server.alias, tags: tags)
                if didSave {
                    editingServer = nil
                }
                return didSave
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .foregroundStyle(.secondary)
            Text(String(localized: "tether.sidebar.title", defaultValue: "Servers"))
                .font(.headline)
            Spacer(minLength: 0)
            Button {
                Task { await catalog.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "tether.sidebar.reload", defaultValue: "Reload SSH configuration"))
            .accessibilityLabel(String(localized: "tether.sidebar.reload", defaultValue: "Reload SSH configuration"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "tether.sidebar.search.placeholder", defaultValue: "Search servers"),
                text: $catalog.searchQuery
            )
            .textFieldStyle(.plain)
            .accessibilityIdentifier("TetherServerSearchField")
            if !catalog.searchQuery.isEmpty {
                Button {
                    catalog.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "tether.sidebar.search.clear", defaultValue: "Clear search"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagFilterChip(
                    title: String(localized: "tether.sidebar.tagFilter.all", defaultValue: "All tags"),
                    isSelected: catalog.selectedTag == nil
                ) {
                    catalog.selectedTag = nil
                }
                ForEach(catalog.availableTags, id: \.self) { tag in
                    tagFilterChip(
                        title: tag,
                        isSelected: catalog.selectedTag == tag
                    ) {
                        catalog.selectedTag = catalog.selectedTag == tag ? nil : tag
                    }
                    .accessibilityIdentifier("TetherServerTagFilter.\(tag)")
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 8)
        .accessibilityIdentifier("TetherServerTagFilters")
    }

    private func tagFilterChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark" : "tag")
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.14),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                section(
                    title: String(localized: "tether.sidebar.favorites", defaultValue: "Favorites"),
                    icon: "star.fill",
                    servers: catalog.favoriteServers
                )
                section(
                    title: String(localized: "tether.sidebar.recent", defaultValue: "Recent"),
                    icon: "clock",
                    servers: catalog.recentServers
                )
                if catalog.selectedTag == nil {
                    ForEach(catalog.tagGroups) { group in
                        section(title: group.tag, icon: "tag", servers: group.servers)
                    }
                }
                section(
                    title: String(localized: "tether.sidebar.all", defaultValue: "All servers"),
                    icon: "server.rack",
                    servers: catalog.visibleServers
                )
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("TetherServerList")
    }

    @ViewBuilder
    private func section(title: String, icon: String, servers: [SSHServer]) -> some View {
        if !servers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 2)
                ForEach(servers) { server in
                    SSHServerRow(
                        server: server,
                        connectionStatus: connectionCoordinator.status(for: server.alias)
                    ) {
                        onSelect(server)
                    } onSelectInBackground: {
                        onSelectInBackground(server)
                    } onEditTags: {
                        editingServer = server
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(String(localized: "tether.sidebar.loading", defaultValue: "Reading SSH configuration…"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "tether.sidebar.empty.title", defaultValue: "No SSH servers found"))
                .font(.headline)
            Text(String(localized: "tether.sidebar.empty.subtitle", defaultValue: "Literal Host aliases from ~/.ssh/config and its includes will appear here."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("TetherServerEmptyState")
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "tether.sidebar.empty.search.title", defaultValue: "No matching servers"))
                .font(.headline)
            Text(String(localized: "tether.sidebar.empty.search.subtitle", defaultValue: "Try a different alias, hostname, tag, or note."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("TetherServerNoResultsState")
    }

    @ViewBuilder
    private var diagnosticsFooter: some View {
        if !catalog.diagnostics.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(
                    String(
                        format: String(
                            localized: "tether.sidebar.diagnostics.count",
                            defaultValue: "%lld configuration diagnostics",
                            comment: "Count of non-fatal SSH configuration diagnostics"
                        ),
                        Int64(catalog.diagnostics.count)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35))
            .accessibilityLabel(String(localized: "tether.sidebar.diagnostics.label", defaultValue: "SSH configuration diagnostics"))
        }
    }
}

private struct SSHServerRow: View {
    let server: SSHServer
    let connectionStatus: SSHServerConnectionStatus?
    let action: () -> Void
    let backgroundAction: () -> Void
    let editTagsAction: () -> Void

    init(
        server: SSHServer,
        connectionStatus: SSHServerConnectionStatus?,
        action: @escaping () -> Void,
        onSelectInBackground backgroundAction: @escaping () -> Void,
        onEditTags editTagsAction: @escaping () -> Void
    ) {
        self.server = server
        self.connectionStatus = connectionStatus
        self.action = action
        self.backgroundAction = backgroundAction
        self.editTagsAction = editTagsAction
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: server.presentation.favorite ? "star.fill" : "server.rack")
                    .foregroundStyle(server.presentation.favorite ? .yellow : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(server.alias)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        ForEach(displayTags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        if server.proxyJump != nil {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help(String(localized: "tether.sidebar.proxyJump", defaultValue: "Uses a jump host"))
                        }
                    }
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if case .some(.connecting) = connectionStatus {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                action()
            } label: {
                Label(
                    String(localized: "tether.sidebar.server.connect", defaultValue: "Connect"),
                    systemImage: "arrow.up.right"
                )
            }
            Button {
                backgroundAction()
            } label: {
                Label(
                    String(localized: "tether.sidebar.server.connectBackground", defaultValue: "Connect in Background"),
                    systemImage: "arrow.down.right.and.arrow.up.left"
                )
            }
            Button {
                editTagsAction()
            } label: {
                Label(
                    String(localized: "tether.sidebar.server.editTags", defaultValue: "Edit Tags…"),
                    systemImage: "tag"
                )
            }
        }
        .accessibilityIdentifier("TetherServerRow.\(server.alias)")
        .accessibilityLabel(
            String(
                format: String(
                    localized: "tether.sidebar.server.accessibility",
                    defaultValue: "%@, %@",
                    comment: "Accessibility label for a server row"
                ),
                server.alias,
                detailText
            )
        )
    }

    private var detailText: String {
        switch connectionStatus {
        case .some(.connecting):
            return String(
                format: String(
                    localized: "tether.sidebar.server.connecting",
                    defaultValue: "Connecting as %@…"
                ),
                server.displayDestination
            )
        case .some(.ready):
            return String(
                format: String(
                    localized: "tether.sidebar.server.ready",
                    defaultValue: "SSH terminal opened for %@"
                ),
                server.displayDestination
            )
        case let .some(.failed(_, message)):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = detail.isEmpty
                ? String(
                    localized: "tether.sidebar.server.failed.start",
                    defaultValue: " cmux could not start the SSH terminal."
                )
                : " \(detail)"
            return String(
                format: String(
                    localized: "tether.sidebar.server.failed",
                    defaultValue: "SSH connection failed:%@"
                ),
                suffix
            )
        case nil:
            return server.displayDestination
        }
    }

    private var displayTags: [String] {
        var seen: Set<String> = []
        return server.presentation.tags.compactMap { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
    }

    private var detailColor: Color {
        switch connectionStatus {
        case .some(.failed):
            return .red
        case .some(.connecting), .some(.ready), nil:
            return .secondary
        }
    }
}
