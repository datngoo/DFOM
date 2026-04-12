import Foundation

struct FileStorageDebugHarness {
    private let storage: LocalFileStorage
    private let fileManager: FileManager

    init(
        storage: LocalFileStorage = ApplicationSupportFileStorage(),
        fileManager: FileManager = .default
    ) {
        self.storage = storage
        self.fileManager = fileManager
    }

    func runDemo() throws -> String {
        let itemID = UUID()
        let tempFileURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("mp3")

        let audioData = Data("KAN-6 local media storage demo".utf8)
        let thumbnailData = Data(repeating: 0xAB, count: 32)

        try audioData.write(to: tempFileURL, options: .atomic)
        _ = try storage.createBaseDirectories()

        let storedAudioURL = try storage.moveTemporaryDownloadedFile(
            at: tempFileURL,
            for: itemID,
            kind: .audio,
            fileExtension: "mp3"
        )
        try storage.ensureManagedFileExists(at: storedAudioURL)

        let storedThumbnailURL = try storage.writeThumbnailData(thumbnailData, for: itemID)
        try storage.ensureManagedFileExists(at: storedThumbnailURL)

        let storedAudioPath = try storage.persistedPath(forManagedFileAt: storedAudioURL)
        let resolvedAudioURL = try storage.resolveManagedFileURL(from: storedAudioPath)
        try storage.ensureManagedFileExists(at: resolvedAudioURL)

        let audioExistsAfterMove = storage.fileExists(at: storedAudioURL)
        let thumbnailExistsAfterWrite = storage.fileExists(at: storedThumbnailURL)

        try storage.deleteStoredFiles(for: itemID)

        let audioExistsAfterDelete = storage.fileExists(at: storedAudioURL)
        let thumbnailExistsAfterDelete = storage.fileExists(at: storedThumbnailURL)

        return """
        Item \(itemID.uuidString.prefix(8)): moved=\(audioExistsAfterMove), thumbnail=\(thumbnailExistsAfterWrite), deleted=\(!audioExistsAfterDelete && !thumbnailExistsAfterDelete)
        """
    }
}
