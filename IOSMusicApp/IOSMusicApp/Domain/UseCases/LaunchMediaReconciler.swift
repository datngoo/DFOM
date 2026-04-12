import Foundation
import OSLog

@MainActor
struct LaunchMediaReconciler {
    private let repository: any MediaLibraryRepository
    private let fileStorage: any LocalFileStorage
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "LaunchMediaReconciler")

    init(
        repository: any MediaLibraryRepository,
        fileStorage: any LocalFileStorage = ApplicationSupportFileStorage()
    ) {
        self.repository = repository
        self.fileStorage = fileStorage
    }

    func reconcileDownloadedItems() throws {
        let items = try repository.fetchItems()
        var reconciledDownloadedCount = 0
        var downgradedMissingMediaCount = 0
        var clearedThumbnailCount = 0

        for item in items where item.downloadStatus == .downloaded {
            let result = try reconcile(item)
            switch result {
            case .stillDownloaded:
                reconciledDownloadedCount += 1
            case .markedUnavailable:
                downgradedMissingMediaCount += 1
            case .clearedMissingThumbnail:
                reconciledDownloadedCount += 1
                clearedThumbnailCount += 1
            }
        }

        logger.debug(
            "Launch reconciliation finished. downloaded_ok=\(reconciledDownloadedCount, privacy: .public) downgraded_missing_media=\(downgradedMissingMediaCount, privacy: .public) cleared_missing_thumbnails=\(clearedThumbnailCount, privacy: .public)"
        )
    }

    private func reconcile(_ item: MediaItem) throws -> ReconciliationResult {
        guard let localFileURL = resolvedManagedURLIfAvailable(for: item.localFilePath) else {
            try markMediaUnavailable(item)
            return .markedUnavailable
        }

        var hasMetadataChanges = false
        var clearedMissingThumbnail = false

        if let normalizedLocalPath = try? fileStorage.persistedPath(forManagedFileAt: localFileURL),
           normalizedLocalPath != item.localFilePath {
            item.localFilePath = normalizedLocalPath
            hasMetadataChanges = true
        }

        if item.mediaType == .video {
            if let thumbnailURL = resolvedManagedURLIfAvailable(for: item.thumbnailLocalPath) {
                if let normalizedThumbnailPath = try? fileStorage.persistedPath(forManagedFileAt: thumbnailURL),
                   normalizedThumbnailPath != item.thumbnailLocalPath {
                    item.thumbnailLocalPath = normalizedThumbnailPath
                    hasMetadataChanges = true
                }
            } else if item.thumbnailLocalPath != nil {
                item.thumbnailLocalPath = nil
                hasMetadataChanges = true
                clearedMissingThumbnail = true
            }
        }

        if hasMetadataChanges {
            try repository.save(item)
        }

        return clearedMissingThumbnail ? .clearedMissingThumbnail : .stillDownloaded
    }

    private func resolvedManagedURLIfAvailable(for persistedPath: String?) -> URL? {
        guard let persistedPath, !persistedPath.isEmpty else {
            return nil
        }

        do {
            let resolvedURL = try fileStorage.resolveExistingManagedFileURL(from: persistedPath)
            return resolvedURL
        } catch {
            logger.error("Managed file resolution failed during reconciliation: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func markMediaUnavailable(_ item: MediaItem) throws {
        if item.mediaType == .video {
            item.thumbnailLocalPath = nil
        }

        do {
            try repository.updateDownloadState(
                for: item,
                status: .failed,
                progress: nil,
                localFilePath: nil,
                downloadedDate: nil
            )
        } catch {
            logger.error("Failed to reconcile missing media item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}

private enum ReconciliationResult {
    case stillDownloaded
    case markedUnavailable
    case clearedMissingThumbnail
}
