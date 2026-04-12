import Foundation

enum DownloadOrchestratorError: Error, Equatable, LocalizedError {
    case activeDownloadInProgress
    case alreadyDownloaded
    case unsupportedMediaType
    case fileStorageFailed
    case persistenceFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .activeDownloadInProgress:
            return "Another download is already in progress."
        case .alreadyDownloaded:
            return "This item is already downloaded."
        case .unsupportedMediaType:
            return "This media type is not supported."
        case .fileStorageFailed:
            return "The downloaded file could not be stored locally."
        case .persistenceFailed:
            return "The media library could not be updated."
        case .downloadFailed:
            return "The file download failed."
        }
    }
}
