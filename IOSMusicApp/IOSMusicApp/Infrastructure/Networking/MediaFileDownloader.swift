import Foundation

protocol MediaFileDownloading {
    func download(
        from remoteURL: URL,
        mediaType: MediaType,
        suggestedFileExtension: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL
}

enum MediaFileDownloaderError: Error, LocalizedError {
    case invalidTemporaryFile
    case transportFailed
    case missingBundledSampleMedia(String)
    case unplayableDownloadedMedia

    var errorDescription: String? {
        switch self {
        case .invalidTemporaryFile:
            return "A temporary file could not be created."
        case .transportFailed:
            return "The remote media file could not be downloaded."
        case .missingBundledSampleMedia(let name):
            return "The bundled sample media file \(name) is missing."
        case .unplayableDownloadedMedia:
            return "The downloaded media file is not playable."
        }
    }
}

protocol ThumbnailDataFetching {
    func fetchThumbnailData(from remoteURL: URL) async throws -> Data
}

enum ThumbnailDataFetcherError: Error, LocalizedError {
    case invalidResponse
    case transportFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The thumbnail response was invalid."
        case .transportFailed:
            return "The thumbnail could not be downloaded."
        }
    }
}

struct ThumbnailDataFetcher: ThumbnailDataFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchThumbnailData(from remoteURL: URL) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: remoteURL)
        } catch {
            throw ThumbnailDataFetcherError.transportFailed
        }

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              !data.isEmpty else {
            throw ThumbnailDataFetcherError.invalidResponse
        }

        return data
    }
}

struct MediaFileDownloader: MediaFileDownloading {
    private let session: URLSession
    private let fileManager: FileManager

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.fileManager = fileManager
    }

    func download(
        from remoteURL: URL,
        mediaType: MediaType,
        suggestedFileExtension: String?,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        _ = mediaType

        onProgress?(0)

        let temporaryURL: URL
        do {
            let (downloadedURL, _) = try await session.download(from: remoteURL)
            temporaryURL = downloadedURL
        } catch {
            throw MediaFileDownloaderError.transportFailed
        }

        onProgress?(1)
        return temporaryURL
    }
}
