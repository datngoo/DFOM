import Foundation

struct ApplicationSupportFileStorage: LocalFileStorage {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createBaseDirectories() throws -> URL {
        let baseDirectory = try baseDirectoryURL()

        do {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw FileStorageError.directoryCreationFailed(baseDirectory, underlying: error)
        }

        try excludeDirectoryFromBackupIfPossible(at: baseDirectory)

        return baseDirectory
    }

    func createItemDirectory(for itemID: UUID) throws -> URL {
        _ = try createBaseDirectories()
        let directoryURL = try itemDirectoryURL(for: itemID)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw FileStorageError.directoryCreationFailed(directoryURL, underlying: error)
        }

        return directoryURL
    }

    func mediaFileURL(for itemID: UUID, kind: StoredMediaKind, fileExtension: String) throws -> URL {
        let sanitizedExtension = try sanitizedFileExtension(fileExtension)
        let directoryURL = try itemDirectoryURL(for: itemID)

        return directoryURL
            .appendingPathComponent(kind.fileNameStem, isDirectory: false)
            .appendingPathExtension(sanitizedExtension)
    }

    func thumbnailURL(for itemID: UUID) throws -> URL {
        let directoryURL = try itemDirectoryURL(for: itemID)

        return directoryURL.appendingPathComponent("thumbnail.jpg", isDirectory: false)
    }

    func persistedPath(forManagedFileAt url: URL) throws -> String {
        guard let relativePath = managedRelativePath(from: url.path) else {
            throw FileStorageError.invalidManagedRelativePath(url.path)
        }

        return try validatedManagedRelativePath(relativePath)
    }

    func resolveManagedFileURL(from persistedPath: String) throws -> URL {
        let trimmedPath = persistedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw FileStorageError.invalidManagedRelativePath(persistedPath)
        }

        if !trimmedPath.hasPrefix("/") {
            let validatedPath = try validatedManagedRelativePath(trimmedPath)
            return try managedFileURL(forValidatedRelativePath: validatedPath)
        }

        if let relativePath = managedRelativePath(from: trimmedPath) {
            let validatedPath = try validatedManagedRelativePath(relativePath)
            return try managedFileURL(forValidatedRelativePath: validatedPath)
        }

        throw FileStorageError.invalidManagedRelativePath(persistedPath)
    }

    func moveTemporaryDownloadedFile(
        at temporaryURL: URL,
        for itemID: UUID,
        kind: StoredMediaKind,
        fileExtension: String
    ) throws -> URL {
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw FileStorageError.missingSourceFile(temporaryURL)
        }

        let destinationURL = try mediaFileURL(
            for: itemID,
            kind: kind,
            fileExtension: fileExtension
        )

        _ = try createItemDirectory(for: itemID)
        try removeItemIfNeeded(at: destinationURL)

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw FileStorageError.fileMoveFailed(
                source: temporaryURL,
                destination: destinationURL,
                underlying: error
            )
        }

        return destinationURL
    }

    func writeThumbnailData(_ data: Data, for itemID: UUID) throws -> URL {
        let fileURL = try thumbnailURL(for: itemID)

        _ = try createItemDirectory(for: itemID)

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FileStorageError.fileWriteFailed(fileURL, underlying: error)
        }

        return fileURL
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func ensureManagedFileExists(at url: URL) throws {
        guard fileExists(at: url) else {
            throw FileStorageError.missingManagedFile(url)
        }
    }

    func deleteStoredFiles(for itemID: UUID) throws {
        let directoryURL = try itemDirectoryURL(for: itemID)

        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw FileStorageError.fileDeletionFailed(directoryURL, underlying: error)
        }
    }

    private func baseDirectoryURL() throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw FileStorageError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent("LocalMediaStorage", isDirectory: true)
            .appendingPathComponent("items", isDirectory: true)
    }

    private func itemDirectoryURL(for itemID: UUID) throws -> URL {
        try baseDirectoryURL()
            .appendingPathComponent(itemID.uuidString, isDirectory: true)
    }

    private func managedRelativePath(from storedPath: String) -> String? {
        let normalizedPath = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else {
            return nil
        }

        if !normalizedPath.hasPrefix("/") {
            return normalizedPath
        }

        let normalizedComponents = URL(fileURLWithPath: normalizedPath).standardized.pathComponents
        guard let localMediaStorageIndex = normalizedComponents.firstIndex(of: "LocalMediaStorage"),
              normalizedComponents.indices.contains(localMediaStorageIndex + 1),
              normalizedComponents[localMediaStorageIndex + 1] == "items" else {
            return nil
        }

        let relativeComponents = normalizedComponents.suffix(from: localMediaStorageIndex + 2)
        guard !relativeComponents.isEmpty else {
            return nil
        }

        return relativeComponents.joined(separator: "/")
    }

    private func sanitizedFileExtension(_ fileExtension: String) throws -> String {
        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtension = trimmedExtension.hasPrefix(".")
            ? String(trimmedExtension.dropFirst())
            : trimmedExtension

        guard !normalizedExtension.isEmpty else {
            throw FileStorageError.invalidFileExtension(fileExtension)
        }

        let allowedCharacters = CharacterSet.alphanumerics
        guard normalizedExtension.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            throw FileStorageError.invalidFileExtension(fileExtension)
        }

        return normalizedExtension.lowercased()
    }

    private func validatedManagedRelativePath(_ relativePath: String) throws -> String {
        let pathComponents = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !pathComponents.isEmpty,
              pathComponents.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw FileStorageError.invalidManagedRelativePath(relativePath)
        }

        return pathComponents.joined(separator: "/")
    }

    private func managedFileURL(forValidatedRelativePath relativePath: String) throws -> URL {
        let baseURL = try baseDirectoryURL()

        return relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .reduce(baseURL) { partialURL, component in
                partialURL.appendingPathComponent(component, isDirectory: false)
            }
    }

    private func excludeDirectoryFromBackupIfPossible(at url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true

        do {
            var mutableURL = url
            try mutableURL.setResourceValues(resourceValues)
        } catch {
            throw FileStorageError.directoryCreationFailed(url, underlying: error)
        }
    }

    private func removeItemIfNeeded(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileStorageError.fileDeletionFailed(url, underlying: error)
        }
    }
}
