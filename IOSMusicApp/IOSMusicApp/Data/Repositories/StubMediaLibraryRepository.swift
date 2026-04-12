import Foundation
import OSLog
import SwiftData

@MainActor
struct SwiftDataMediaLibraryRepository: MediaLibraryRepository {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "MediaLibraryRepository")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchItems() throws -> [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
    }

    func fetchItem(providerName: String, providerItemID: String, mediaType: MediaType) throws -> MediaItem? {
        let mediaTypeRawValue = mediaType.rawValue
        logger.debug(
            "Looking up MediaItem for provider \(providerName, privacy: .public), providerItemID \(providerItemID, privacy: .public), mediaTypeRawValue \(mediaTypeRawValue, privacy: .public)"
        )

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate<MediaItem> { item in
                    item.providerName == providerName &&
                    item.providerItemID == providerItemID &&
                    item.mediaTypeRawValue == mediaTypeRawValue
                }
            )

            if let item = try modelContext.fetch(descriptor).first {
                item.syncMediaTypeRawValueIfNeeded()
                logger.debug(
                    "Found existing MediaItem via raw-value query: \(item.id.uuidString, privacy: .public)"
                )
                return item
            }

            let fallbackDescriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate<MediaItem> { item in
                    item.providerName == providerName &&
                    item.providerItemID == providerItemID
                }
            )

            if let fallbackItem = try modelContext.fetch(fallbackDescriptor).first(where: { $0.mediaType == mediaType }) {
                logger.debug(
                    "Found existing MediaItem via fallback in-memory filter: \(fallbackItem.id.uuidString, privacy: .public)"
                )
                fallbackItem.syncMediaTypeRawValueIfNeeded()
                try modelContext.save()
                return fallbackItem
            }

            logger.debug(
                "No MediaItem found for providerItemID \(providerItemID, privacy: .public) and mediaTypeRawValue \(mediaTypeRawValue, privacy: .public)"
            )
            return nil
        } catch {
            logger.error(
                "MediaItem lookup failed for providerItemID \(providerItemID, privacy: .public) and mediaTypeRawValue \(mediaTypeRawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func upsertItem(from resolvedItem: ResolvedMediaItem, mediaType: MediaType) throws -> MediaItem {
        logger.debug(
            "Upserting MediaItem for providerItemID \(resolvedItem.providerItemId, privacy: .public) with mediaTypeRawValue \(mediaType.rawValue, privacy: .public)"
        )

        do {
            if let existingItem = try fetchItem(
                providerName: resolvedItem.provider,
                providerItemID: resolvedItem.providerItemId,
                mediaType: mediaType
            ) {
                existingItem.title = resolvedItem.title
                existingItem.creatorName = resolvedItem.creatorName
                existingItem.thumbnailRemoteURLString = resolvedItem.thumbnailURL?.absoluteString
                existingItem.setMediaType(mediaType)
                try modelContext.save()
                logger.debug(
                    "Updated existing MediaItem \(existingItem.id.uuidString, privacy: .public) for providerItemID \(resolvedItem.providerItemId, privacy: .public)"
                )
                return existingItem
            }

            let newItem = MediaItem(
                providerName: resolvedItem.provider,
                providerItemID: resolvedItem.providerItemId,
                title: resolvedItem.title,
                creatorName: resolvedItem.creatorName,
                mediaType: mediaType,
                downloadStatus: .notDownloaded,
                downloadProgress: nil,
                localFilePath: nil,
                thumbnailRemoteURLString: resolvedItem.thumbnailURL?.absoluteString,
                thumbnailLocalPath: nil,
                createdDate: .now,
                downloadedDate: nil
            )

            modelContext.insert(newItem)
            try modelContext.save()
            logger.debug(
                "Created new MediaItem \(newItem.id.uuidString, privacy: .public) for providerItemID \(resolvedItem.providerItemId, privacy: .public)"
            )
            return newItem
        } catch {
            logger.error(
                "MediaItem upsert failed for providerItemID \(resolvedItem.providerItemId, privacy: .public) and mediaTypeRawValue \(mediaType.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func updateDownloadState(
        for item: MediaItem,
        status: DownloadStatus,
        progress: Double?,
        localFilePath: String?,
        downloadedDate: Date?
    ) throws {
        do {
            item.downloadStatus = status
            item.downloadProgress = progress
            item.localFilePath = localFilePath
            item.downloadedDate = downloadedDate
            item.syncMediaTypeRawValueIfNeeded()

            try modelContext.save()
        } catch {
            logger.error(
                "Failed to persist download state for MediaItem \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func save(_ item: MediaItem) throws {
        // Callers either inserted the model already or are updating an existing one.
        do {
            item.syncMediaTypeRawValueIfNeeded()
            _ = item
            try modelContext.save()
        } catch {
            logger.error(
                "Failed to save MediaItem \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func deleteAll() throws {
        do {
            let items = try fetchItems()

            for item in items {
                modelContext.delete(item)
            }

            try modelContext.save()
        } catch {
            logger.error("Failed to delete all MediaItems: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
