import Foundation

enum FileStorageError: LocalizedError {
    case applicationSupportDirectoryUnavailable
    case invalidFileExtension(String)
    case missingSourceFile(URL)
    case missingManagedFile(URL)
    case directoryCreationFailed(URL, underlying: Error)
    case fileMoveFailed(source: URL, destination: URL, underlying: Error)
    case fileWriteFailed(URL, underlying: Error)
    case fileDeletionFailed(URL, underlying: Error)
    case invalidManagedRelativePath(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "Application Support directory is unavailable."
        case .invalidFileExtension(let fileExtension):
            return "Invalid file extension: \(fileExtension)"
        case .missingSourceFile(let url):
            return "Missing source file at \(url.path)."
        case .missingManagedFile(let url):
            return "Managed file is missing at \(url.path)."
        case .directoryCreationFailed(let url, let underlying):
            return "Failed to create directory at \(url.path): \(underlying.localizedDescription)"
        case .fileMoveFailed(let source, let destination, let underlying):
            return "Failed to move file from \(source.lastPathComponent) to \(destination.path): \(underlying.localizedDescription)"
        case .fileWriteFailed(let url, let underlying):
            return "Failed to write file at \(url.path): \(underlying.localizedDescription)"
        case .fileDeletionFailed(let url, let underlying):
            return "Failed to delete file at \(url.path): \(underlying.localizedDescription)"
        case .invalidManagedRelativePath(let path):
            return "Invalid managed relative path: \(path)"
        }
    }
}
