import Foundation

enum DownloadStatus: String, Codable, CaseIterable {
    case notDownloaded
    case queued
    case downloading
    case downloaded
    case failed
}
