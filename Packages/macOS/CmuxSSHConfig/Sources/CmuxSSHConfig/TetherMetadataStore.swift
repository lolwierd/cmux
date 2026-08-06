public import Foundation

/// Errors raised by the presentation metadata repository.
public enum TetherMetadataStoreError: Error, Sendable, Equatable {
    /// The file declares a schema version newer than this build understands.
    case unsupportedVersion(Int)
    /// The metadata file exists but is malformed.
    case malformed
}

/// The persistence seam for Tether's presentation-only metadata.
public protocol TetherMetadataStoring: Sendable {
    /// Loads metadata, returning empty current-version metadata when no file exists.
    ///
    /// - Returns: Versioned presentation metadata.
    /// - Throws: A malformed or unsupported-version error.
    func load() async throws -> TetherPresentationMetadata

    /// Atomically saves metadata.
    ///
    /// - Parameter metadata: The current-version metadata to save.
    /// - Throws: A filesystem error.
    func save(_ metadata: TetherPresentationMetadata) async throws
}

/// Stores Tether metadata as a small, inspectable JSON file.
public actor LocalTetherMetadataStore: TetherMetadataStoring {
    private let fileURL: URL
    private let fileManager: FileManager

    /// Creates a metadata store.
    ///
    /// - Parameters:
    ///   - fileURL: The JSON file to own.
    ///   - fileManager: The injected file manager used for directory creation.
    public init(fileURL: URL, fileManager: FileManager) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
    }

    /// Creates a metadata store backed by the standard file manager.
    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = FileManager.default
    }

    public func load() async throws -> TetherPresentationMetadata {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TetherPresentationMetadata()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let metadata = try JSONDecoder().decode(TetherPresentationMetadata.self, from: data)
            guard metadata.version <= TetherPresentationMetadata.currentVersion else {
                throw TetherMetadataStoreError.unsupportedVersion(metadata.version)
            }
            return metadata
        } catch let error as TetherMetadataStoreError {
            throw error
        } catch {
            throw TetherMetadataStoreError.malformed
        }
    }

    public func save(_ metadata: TetherPresentationMetadata) async throws {
        var normalized = metadata
        normalized.version = TetherPresentationMetadata.currentVersion
        normalized.recentAliases = Array(normalized.recentAliases.prefix(50))
        let data = try JSONEncoder().encode(normalized)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
    }
}
