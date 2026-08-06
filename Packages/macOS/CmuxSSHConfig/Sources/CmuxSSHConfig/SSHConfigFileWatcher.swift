import Darwin
public import Foundation

/// A stream of external SSH configuration changes.
public protocol SSHConfigWatching: Sendable {
    /// Replaces the include-graph paths being watched.
    ///
    /// - Parameter urls: Existing configuration files and directories to watch.
    func watch(urls: [URL]) async

    /// Creates a stream that yields after an observed change.
    ///
    /// - Returns: A cancellable change stream.
    func changes() async -> AsyncStream<Void>
}

/// Watches the current include graph using DispatchSource file events.
public actor SSHConfigFileWatcher: SSHConfigWatching {
    private var sources: [URL: any DispatchSourceFileSystemObject] = [:]
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Creates an empty file watcher.
    public init() {}

    public func watch(urls: [URL]) async {
        for source in sources.values { source.cancel() }
        sources.removeAll(keepingCapacity: true)
        let paths = Set(urls.flatMap { [$0.standardizedFileURL, $0.deletingLastPathComponent().standardizedFileURL] })
        for url in paths where !sources.keys.contains(url) {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            // DispatchSource is the macOS-native filesystem event seam. Events
            // are forwarded into this actor before they reach catalog callers.
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                Task { await self?.emitChange() }
            }
            source.setCancelHandler { close(descriptor) }
            sources[url] = source
            source.resume()
        }
    }

    public func changes() async -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    private func emitChange() {
        for continuation in continuations.values {
            continuation.yield(())
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
