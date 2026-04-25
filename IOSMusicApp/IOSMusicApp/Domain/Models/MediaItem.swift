import Foundation
import SwiftData

@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var providerName: String
    var providerItemID: String
    var title: String
    var creatorName: String?
    var mediaType: MediaType
    var mediaTypeRawValue: String
    var downloadStatus: DownloadStatus
    var downloadProgress: Double?
    var localFilePath: String?
    var thumbnailRemoteURLString: String?
    var thumbnailLocalPath: String?
    var createdDate: Date
    var downloadedDate: Date?
    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.mediaItem) var playlistEntries: [PlaylistEntry]

    init(
        id: UUID = UUID(),
        providerName: String,
        providerItemID: String,
        title: String,
        creatorName: String? = nil,
        mediaType: MediaType = .unknown,
        downloadStatus: DownloadStatus = .notDownloaded,
        downloadProgress: Double? = nil,
        localFilePath: String? = nil,
        thumbnailRemoteURLString: String? = nil,
        thumbnailLocalPath: String? = nil,
        createdDate: Date = .now,
        downloadedDate: Date? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.providerItemID = providerItemID
        self.title = title
        self.creatorName = creatorName
        self.mediaType = mediaType
        self.mediaTypeRawValue = mediaType.rawValue
        self.downloadStatus = downloadStatus
        self.downloadProgress = downloadProgress
        self.localFilePath = localFilePath
        self.thumbnailRemoteURLString = thumbnailRemoteURLString
        self.thumbnailLocalPath = thumbnailLocalPath
        self.createdDate = createdDate
        self.downloadedDate = downloadedDate
        self.playlistEntries = []
    }

    var thumbnailRemoteURL: URL? {
        guard let thumbnailRemoteURLString, !thumbnailRemoteURLString.isEmpty else {
            return nil
        }

        return URL(string: thumbnailRemoteURLString)
    }

    func setMediaType(_ mediaType: MediaType) {
        self.mediaType = mediaType
        self.mediaTypeRawValue = mediaType.rawValue
    }

    func syncMediaTypeRawValueIfNeeded() {
        if mediaTypeRawValue != mediaType.rawValue {
            mediaTypeRawValue = mediaType.rawValue
        }
    }
}

@Model
final class Playlist {
    static let podcastsName = "Podcasts"

    @Attribute(.unique) var id: UUID
    var name: String
    var mediaType: MediaType
    var mediaTypeRawValue: String
    var createdDate: Date
    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist) var entries: [PlaylistEntry]

    init(
        id: UUID = UUID(),
        name: String,
        mediaType: MediaType = .unknown,
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.mediaType = mediaType
        self.mediaTypeRawValue = mediaType.rawValue
        self.createdDate = createdDate
        self.entries = []
    }

    var sortedEntries: [PlaylistEntry] {
        entries.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdDate < $1.createdDate
            }

            return $0.sortOrder < $1.sortOrder
        }
    }

    var itemCount: Int {
        sortedEntries.count
    }

    var isPodcastsPlaylist: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(Self.podcastsName) == .orderedSame
    }

    func setMediaType(_ mediaType: MediaType) {
        self.mediaType = mediaType
        self.mediaTypeRawValue = mediaType.rawValue
    }

    func syncMediaTypeRawValueIfNeeded() {
        if mediaTypeRawValue != mediaType.rawValue {
            mediaTypeRawValue = mediaType.rawValue
        }
    }

    func syncMediaTypeFromEntriesIfNeeded() {
        let nextMediaType = sortedEntries.compactMap(\.mediaItem?.mediaType).first ?? .unknown
        setMediaType(nextMediaType)
    }

    func canAccept(_ item: MediaItem) -> Bool {
        mediaType == .unknown || mediaType == item.mediaType
    }

    func contains(_ item: MediaItem) -> Bool {
        sortedEntries.contains { $0.mediaItem?.id == item.id }
    }
}

@Model
final class PlaylistEntry {
    @Attribute(.unique) var id: UUID
    var createdDate: Date
    var sortOrder: Int
    var playlist: Playlist?
    var mediaItem: MediaItem?

    init(
        id: UUID = UUID(),
        createdDate: Date = .now,
        sortOrder: Int,
        playlist: Playlist? = nil,
        mediaItem: MediaItem? = nil
    ) {
        self.id = id
        self.createdDate = createdDate
        self.sortOrder = sortOrder
        self.playlist = playlist
        self.mediaItem = mediaItem
    }
}
