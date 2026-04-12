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
