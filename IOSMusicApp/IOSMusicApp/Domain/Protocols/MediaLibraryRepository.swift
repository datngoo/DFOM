import Foundation

@MainActor
protocol MediaLibraryRepository {
    func fetchItems() throws -> [MediaItem]
    func fetchItem(providerName: String, providerItemID: String, mediaType: MediaType) throws -> MediaItem?
    func upsertItem(from resolvedItem: ResolvedMediaItem, mediaType: MediaType) throws -> MediaItem
    func updateDownloadState(
        for item: MediaItem,
        status: DownloadStatus,
        progress: Double?,
        localFilePath: String?,
        downloadedDate: Date?
    ) throws
    func save(_ item: MediaItem) throws
    func deleteAll() throws
}
