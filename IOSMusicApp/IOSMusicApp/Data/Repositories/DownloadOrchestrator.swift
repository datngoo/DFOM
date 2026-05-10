import Foundation
import OSLog
import AVFoundation

@MainActor
final class DownloadOrchestrator: DownloadOrchestrating {
    private let repository: any MediaLibraryRepository
    private let downloadProvider: any DownloadProvider
    private let downloader: any MediaFileDownloading
    private let thumbnailDataFetcher: any ThumbnailDataFetching
    private let fileStorage: any LocalFileStorage
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "DownloadOrchestrator")

    private var activeDownloadKey: String?

    init(
        repository: any MediaLibraryRepository,
        downloadProvider: any DownloadProvider,
        downloader: any MediaFileDownloading = MediaFileDownloader(),
        thumbnailDataFetcher: any ThumbnailDataFetching = ThumbnailDataFetcher(),
        fileStorage: any LocalFileStorage = ApplicationSupportFileStorage()
    ) {
        self.repository = repository
        self.downloadProvider = downloadProvider
        self.downloader = downloader
        self.thumbnailDataFetcher = thumbnailDataFetcher
        self.fileStorage = fileStorage
    }

    func currentState(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadStateSnapshot? {
        guard let mediaItem = try repository.fetchItem(
            providerName: item.provider,
            providerItemID: item.providerItemId,
            mediaType: mediaType
        ) else {
            return nil
        }

        if mediaItem.downloadStatus == .downloaded,
           !isManagedFileAvailable(for: mediaItem) {
            logger.error("Downloaded file is missing for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public); downgrading state to failed")
            if mediaType == .video {
                mediaItem.thumbnailLocalPath = nil
            }
            try repository.updateDownloadState(
                for: mediaItem,
                status: .failed,
                progress: nil,
                localFilePath: nil,
                downloadedDate: nil
            )

            return DownloadStateSnapshot(
                mediaType: mediaType,
                status: .failed,
                progress: nil,
                localFilePath: nil
            )
        }

        let normalizedProgress: Double?
        switch mediaItem.downloadStatus {
        case .queued:
            normalizedProgress = mediaItem.downloadProgress ?? 0
        case .downloaded:
            normalizedProgress = 1
        default:
            normalizedProgress = mediaItem.downloadProgress
        }

        return DownloadStateSnapshot(
            mediaType: mediaType,
            status: mediaItem.downloadStatus,
            progress: normalizedProgress,
            localFilePath: mediaItem.localFilePath
        )
    }

    func startDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws {
        logger.debug("1. Entered startDownload for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")

        guard mediaType != .unknown else {
            logger.error("13. Unsupported media type requested")
            throw DownloadOrchestratorError.unsupportedMediaType
        }

        let downloadKey = makeDownloadKey(
            provider: item.provider,
            providerItemID: item.providerItemId,
            mediaType: mediaType
        )

        guard activeDownloadKey == nil else {
            logger.error("13. Active download already in progress for key \(self.activeDownloadKey ?? "none", privacy: .public)")
            throw DownloadOrchestratorError.activeDownloadInProgress
        }

        let mediaItem: MediaItem
        do {
            logger.debug("2. About to upsert/create/find MediaItem for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            mediaItem = try repository.upsertItem(from: item, mediaType: mediaType)
            logger.debug("3. MediaItem upserted \(mediaItem.id.uuidString, privacy: .public) for \(mediaType.rawValue, privacy: .public)")
        } catch {
            logger.error("13. Failed during MediaItem upsert for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            throw DownloadOrchestratorError.persistenceFailed
        }

        guard mediaItem.downloadStatus != .downloaded else {
            logger.error("13. MediaItem already downloaded for \(mediaType.rawValue, privacy: .public)")
            throw DownloadOrchestratorError.alreadyDownloaded
        }

        activeDownloadKey = downloadKey
        defer { activeDownloadKey = nil }

        do {
            _ = try fileStorage.createBaseDirectories()
        } catch {
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "base directory setup",
                underlyingError: error
            )
            throw DownloadOrchestratorError.fileStorageFailed
        }

        do {
            try clearPersistedArtifactsIfNeeded(for: mediaItem, mediaType: mediaType)
            logger.debug("4. About to set queued for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            try repository.updateDownloadState(
                for: mediaItem,
                status: .queued,
                progress: 0,
                localFilePath: nil,
                downloadedDate: nil
            )
            logger.debug("5. Queued saved for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
        } catch {
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "queued save",
                underlyingError: error
            )
            throw DownloadOrchestratorError.persistenceFailed
        }

        let transferMediaType = effectiveTransferMediaType(for: item, requestedMediaType: mediaType)
        let descriptor: DownloadDescriptor
        do {
            logger.debug("6. About to prepare/resolve transfer descriptor for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            descriptor = try await transferDescriptor(for: item, mediaType: transferMediaType)
            logger.debug("7. Descriptor ready for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public) using transfer type \(transferMediaType.rawValue, privacy: .public) with extension \(descriptor.suggestedFileExtension ?? "nil", privacy: .public)")
        } catch {
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "descriptor preparation",
                underlyingError: error
            )
            throw error
        }

        let downloadedTransferFileFormat = descriptor.resolvedFileFormat
        let finalStorageFileFormat = mediaType == .audio && transferMediaType == .video
            ? ManagedMediaFileFormat.defaultFormat(for: .audio)
            : descriptor.resolvedFileFormat
        do {
            try repository.updateDownloadState(
                for: mediaItem,
                status: .downloading,
                progress: 0,
                localFilePath: nil,
                downloadedDate: nil
            )
            logger.debug("8. About to start downloader for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
        } catch {
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "downloading state save",
                underlyingError: error
            )
            throw DownloadOrchestratorError.persistenceFailed
        }

        let temporaryFileURL: URL
        do {
            temporaryFileURL = try await downloader.download(
                from: descriptor.remoteURL,
                mediaType: transferMediaType,
                suggestedFileExtension: descriptor.resolvedFileFormat.fileExtension
            ) { [weak self] progress in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    guard let currentItem = try? self.repository.fetchItem(
                        providerName: item.provider,
                        providerItemID: item.providerItemId,
                        mediaType: mediaType
                    ) else {
                        self.logger.error("13. Failed to refetch MediaItem during progress update for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
                        return
                    }

                    do {
                        try self.repository.updateDownloadState(
                            for: currentItem,
                            status: .downloading,
                            progress: progress,
                            localFilePath: nil,
                            downloadedDate: nil
                        )
                        self.logger.debug("8. Downloader progress \(Int(progress * 100), privacy: .public)% for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
                    } catch {
                        self.logger.error("13. Failed to persist progress for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }
            logger.debug("9. Downloader returned temp file at \(temporaryFileURL.path, privacy: .public)")
        } catch {
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "downloader transport",
                underlyingError: error
            )
            throw DownloadOrchestratorError.downloadFailed(userFacingDownloadFailureMessage(for: error, mediaType: mediaType))
        }

        let storedMediaKind = try storedMediaKind(for: mediaType)
        let initiallyStoredFileURL: URL
        do {
            logger.debug("10. About to move file into Application Support for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            initiallyStoredFileURL = try fileStorage.moveTemporaryDownloadedFile(
                at: temporaryFileURL,
                for: mediaItem.id,
                kind: storedMediaKind,
                fileExtension: downloadedTransferFileFormat.fileExtension
            )
            try fileStorage.ensureManagedFileExists(at: initiallyStoredFileURL)
            logger.debug("11. Moved file successfully to \(initiallyStoredFileURL.path, privacy: .public)")
        } catch {
            cleanupTemporaryFileIfNeeded(at: temporaryFileURL)
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "Application Support move",
                underlyingError: error
            )
            throw DownloadOrchestratorError.fileStorageFailed
        }

        let storedFileURL: URL
        do {
            storedFileURL = try await finalizeStoredFileIfNeeded(
                initiallyStoredFileURL,
                requestedMediaType: mediaType,
                transferMediaType: transferMediaType,
                mediaItemID: mediaItem.id,
                providerItemID: item.providerItemId,
                finalFileFormat: finalStorageFileFormat
            )
        } catch {
            cleanupStoredFilesIfNeeded(for: mediaItem)
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "download post-processing",
                underlyingError: error
            )
            throw DownloadOrchestratorError.downloadFailed(userFacingDownloadFailureMessage(for: error, mediaType: mediaType))
        }

        do {
            try await validatePlayableMediaIfNeeded(at: storedFileURL, mediaType: mediaType)
        } catch {
            cleanupStoredFilesIfNeeded(for: mediaItem)
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "playability validation",
                underlyingError: error
            )
            throw DownloadOrchestratorError.downloadFailed(userFacingDownloadFailureMessage(for: error, mediaType: mediaType))
        }

        do {
            let persistedLocalFilePath = try fileStorage.persistedPath(forManagedFileAt: storedFileURL)
            try repository.updateDownloadState(
                for: mediaItem,
                status: .downloaded,
                progress: 1,
                localFilePath: persistedLocalFilePath,
                downloadedDate: .now
            )
            await cacheThumbnailIfNeeded(for: mediaItem, resolvedItem: item, mediaType: mediaType)
            logger.debug("12. Saved downloaded state for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
        } catch {
            cleanupStoredFilesIfNeeded(for: mediaItem)
            markFailedIfPossible(
                for: mediaItem,
                mediaType: mediaType,
                providerItemID: item.providerItemId,
                stage: "downloaded state save",
                underlyingError: error
            )
            throw DownloadOrchestratorError.persistenceFailed
        }
    }

    private func storedMediaKind(for mediaType: MediaType) throws -> StoredMediaKind {
        switch mediaType {
        case .audio:
            return .audio
        case .video:
            return .video
        case .unknown:
            throw DownloadOrchestratorError.unsupportedMediaType
        }
    }

    private func makeDownloadKey(provider: String, providerItemID: String, mediaType: MediaType) -> String {
        "\(provider)|\(providerItemID)|\(mediaType.rawValue)"
    }

    private func effectiveTransferMediaType(for item: ResolvedMediaItem, requestedMediaType: MediaType) -> MediaType {
        if requestedMediaType == .audio, item.provider == YouTubeURLResolutionProvider.providerName {
            return .video
        }

        return requestedMediaType
    }

    private func transferDescriptor(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        do {
            return try await downloadProvider.resolveDownload(for: item, mediaType: mediaType)
        } catch {
            logger.error("6. Descriptor resolution failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func finalizeStoredFileIfNeeded(
        _ storedTransferFileURL: URL,
        requestedMediaType: MediaType,
        transferMediaType: MediaType,
        mediaItemID: UUID,
        providerItemID: String,
        finalFileFormat: ManagedMediaFileFormat
    ) async throws -> URL {
        guard requestedMediaType == .audio, transferMediaType == .video else {
            return storedTransferFileURL
        }

        logger.debug("11a. Exporting audio track from stored video for \(providerItemID, privacy: .public)")
        let exportedAudioURL = try await exportAudioTrack(fromVideoAt: storedTransferFileURL)

        let finalStoredAudioURL = try fileStorage.moveTemporaryDownloadedFile(
            at: exportedAudioURL,
            for: mediaItemID,
            kind: .audio,
            fileExtension: finalFileFormat.fileExtension
        )
        try fileStorage.ensureManagedFileExists(at: finalStoredAudioURL)

        cleanupTemporaryFileIfNeeded(at: storedTransferFileURL)
        logger.debug("11b. Exported audio track successfully for \(providerItemID, privacy: .public) to \(finalStoredAudioURL.path, privacy: .public)")
        return finalStoredAudioURL
    }

    private func exportAudioTrack(fromVideoAt videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)

        guard !audioTracks.isEmpty else {
            throw MediaFileDownloaderError.unplayableDownloadedMedia
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaFileDownloaderError.unplayableDownloadedMedia
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(ManagedMediaFileFormat.m4a.fileExtension)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = false

        try await exportSession.exportCompat()

        guard exportSession.status == .completed,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                cleanupTemporaryFileIfNeeded(at: outputURL)
            }
            throw exportSession.error ?? MediaFileDownloaderError.unplayableDownloadedMedia
        }

        return outputURL
    }

    private func validatePlayableMediaIfNeeded(at fileURL: URL, mediaType: MediaType) async throws {
        guard mediaType == .audio || mediaType == .video else {
            return
        }

        let asset = AVURLAsset(url: fileURL)
        let isPlayable = try await asset.load(.isPlayable)

        guard isPlayable else {
            throw MediaFileDownloaderError.unplayableDownloadedMedia
        }
    }

    private func isManagedFileAvailable(for mediaItem: MediaItem) -> Bool {
        guard let localFileURL = try? fileStorage.resolveExistingManagedFileURL(from: mediaItem.localFilePath) else {
            return false
        }

        return fileStorage.fileExists(at: localFileURL)
    }

    private func cacheThumbnailIfNeeded(
        for mediaItem: MediaItem,
        resolvedItem: ResolvedMediaItem,
        mediaType: MediaType
    ) async {
        guard mediaType == .video else {
            return
        }

        guard let thumbnailURL = resolvedItem.thumbnailURL else {
            do {
                mediaItem.thumbnailLocalPath = nil
                try repository.save(mediaItem)
            } catch {
                logger.error("12. Failed to clear thumbnail path for \(mediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return
        }

        let thumbnailData: Data

        do {
            thumbnailData = try await thumbnailDataFetcher.fetchThumbnailData(from: thumbnailURL)
        } catch {
            logger.error("12. Thumbnail fetch failed for \(mediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        do {
            let storedThumbnailURL = try fileStorage.writeThumbnailData(thumbnailData, for: mediaItem.id)
            try fileStorage.ensureManagedFileExists(at: storedThumbnailURL)
            mediaItem.thumbnailLocalPath = try fileStorage.persistedPath(forManagedFileAt: storedThumbnailURL)
            try repository.save(mediaItem)
            logger.debug("12. Cached thumbnail successfully for \(mediaItem.id.uuidString, privacy: .public)")
        } catch {
            mediaItem.thumbnailLocalPath = nil
            do {
                try repository.save(mediaItem)
            } catch {
                logger.error("12. Thumbnail save rollback failed for \(mediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            logger.error("12. Thumbnail cache failed for \(mediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func clearPersistedArtifactsIfNeeded(for mediaItem: MediaItem, mediaType: MediaType) throws {
        mediaItem.localFilePath = nil

        if mediaType == .video {
            mediaItem.thumbnailLocalPath = nil
        }

        try repository.save(mediaItem)
    }

    private func cleanupTemporaryFileIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("13. Failed to remove temporary file at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func cleanupStoredFilesIfNeeded(for mediaItem: MediaItem) {
        do {
            try fileStorage.deleteStoredFiles(for: mediaItem.id)
        } catch {
            logger.error("13. Failed to clean stored files for \(mediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func userFacingDownloadFailureMessage(for error: Error, mediaType: MediaType) -> String {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }

        return "The \(mediaType.rawValue) download failed."
    }

    private func markFailedIfPossible(
        for mediaItem: MediaItem,
        mediaType: MediaType,
        providerItemID: String,
        stage: String,
        underlyingError: Error
    ) {
        do {
            if mediaType == .video {
                mediaItem.thumbnailLocalPath = nil
            }
            try repository.updateDownloadState(
                for: mediaItem,
                status: .failed,
                progress: nil,
                localFilePath: nil,
                downloadedDate: nil
            )
            logger.error("13. Failed during \(stage, privacy: .public) for \(mediaType.rawValue, privacy: .public) \(providerItemID, privacy: .public): \(String(describing: underlyingError), privacy: .public)")
        } catch {
            logger.error(
                "13. Failed during \(stage, privacy: .public) for \(mediaType.rawValue, privacy: .public) \(providerItemID, privacy: .public): \(String(describing: underlyingError), privacy: .public). Also failed to persist failed state: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

private extension AVAssetExportSession {
    func exportCompat() async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportAsynchronously {
                switch self.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: self.error ?? MediaFileDownloaderError.unplayableDownloadedMedia)
                case .cancelled:
                    continuation.resume(throwing: MediaFileDownloaderError.transportFailed("The download was cancelled before the media file could be prepared."))
                default:
                    continuation.resume(throwing: self.error ?? MediaFileDownloaderError.unplayableDownloadedMedia)
                }
            }
        }
    }
}
