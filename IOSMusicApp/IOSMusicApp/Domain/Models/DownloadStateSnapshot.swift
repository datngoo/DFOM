import Foundation

struct DownloadStateSnapshot: Equatable, Sendable {
    let mediaType: MediaType
    let status: DownloadStatus
    let progress: Double?
    let localFilePath: String?
}
