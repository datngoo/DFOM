import Foundation

protocol LocalFileStorage {
    func createBaseDirectories() throws -> URL
    func createItemDirectory(for itemID: UUID) throws -> URL
    func mediaFileURL(for itemID: UUID, kind: StoredMediaKind, fileExtension: String) throws -> URL
    func thumbnailURL(for itemID: UUID) throws -> URL
    func persistedPath(forManagedFileAt url: URL) throws -> String
    func resolveManagedFileURL(from persistedPath: String) throws -> URL
    func moveTemporaryDownloadedFile(
        at temporaryURL: URL,
        for itemID: UUID,
        kind: StoredMediaKind,
        fileExtension: String
    ) throws -> URL
    func writeThumbnailData(_ data: Data, for itemID: UUID) throws -> URL
    func fileExists(at url: URL) -> Bool
    func ensureManagedFileExists(at url: URL) throws
    func deleteStoredFiles(for itemID: UUID) throws
}

extension LocalFileStorage {
    func normalizedManagedPathIfAvailable(_ persistedPath: String?) throws -> String? {
        guard let persistedPath = persistedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !persistedPath.isEmpty else {
            return nil
        }

        let fileURL = try resolveManagedFileURL(from: persistedPath)
        guard fileExists(at: fileURL) else {
            return nil
        }

        return try self.persistedPath(forManagedFileAt: fileURL)
    }

    func resolveExistingManagedFileURL(from persistedPath: String?) throws -> URL {
        guard let persistedPath = persistedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !persistedPath.isEmpty else {
            throw FileStorageError.invalidManagedRelativePath(persistedPath ?? "")
        }

        let fileURL = try resolveManagedFileURL(from: persistedPath)
        try ensureManagedFileExists(at: fileURL)
        return fileURL
    }
}
