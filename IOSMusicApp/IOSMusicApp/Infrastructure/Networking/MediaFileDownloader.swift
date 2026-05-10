import Foundation
import OSLog

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
    case invalidResponse(Int?)
    case networkOffline
    case requestTimedOut
    case serverRejected(Int?)
    case transportFailed(String?)
    case missingBundledSampleMedia(String)
    case unplayableDownloadedMedia

    var errorDescription: String? {
        switch self {
        case .invalidTemporaryFile:
            return "The downloaded file could not be prepared for offline storage."
        case .invalidResponse(let statusCode):
            if let statusCode {
                return "The remote server returned an invalid download response (HTTP \(statusCode))."
            }
            return "The remote server returned an invalid download response."
        case .networkOffline:
            return "You appear to be offline. Reconnect to the internet and try the download again."
        case .requestTimedOut:
            return "The file download timed out before the remote server finished responding."
        case .serverRejected(let statusCode):
            if let statusCode {
                return "The remote server could not deliver the download right now (HTTP \(statusCode))."
            }
            return "The remote server could not deliver the download right now."
        case .transportFailed(let message):
            return message ?? "The remote media file could not be downloaded."
        case .missingBundledSampleMedia(let name):
            return "The bundled sample media file \(name) is missing."
        case .unplayableDownloadedMedia:
            return "The downloaded media file could not be prepared for offline playback."
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
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "MediaFileDownloader")

    init(
        session: URLSession = MediaFileDownloader.makeDefaultSession(),
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
        onProgress?(0)

        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = BridgeConfig.current.downloadRequestTimeout

        logger.debug(
            """
            Download request started: url=\(remoteURL.absoluteString, privacy: .public) \
            path=\(remoteURL.path, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public)
            """
        )

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch {
            let mappedError = mapTransportError(error)
            logger.error(
                """
                Download request failed: url=\(remoteURL.absoluteString, privacy: .public) \
                path=\(remoteURL.path, privacy: .public) \
                mediaType=\(mediaType.rawValue, privacy: .public) \
                reason=\(String(describing: mappedError), privacy: .public) \
                underlying=\(String(describing: error), privacy: .public)
                """
            )
            throw mappedError
        }

        if let httpResponse = response as? HTTPURLResponse {
            logger.debug(
                """
                Download response received: url=\(remoteURL.absoluteString, privacy: .public) \
                path=\(remoteURL.path, privacy: .public) \
                status=\(httpResponse.statusCode, privacy: .public) \
                mediaType=\(mediaType.rawValue, privacy: .public)
                """
            )

            guard 200..<300 ~= httpResponse.statusCode else {
                let error = MediaFileDownloaderError.serverRejected(httpResponse.statusCode)
                logger.error(
                    """
                    Download server rejected request: url=\(remoteURL.absoluteString, privacy: .public) \
                    path=\(remoteURL.path, privacy: .public) \
                    mediaType=\(mediaType.rawValue, privacy: .public) \
                    status=\(httpResponse.statusCode, privacy: .public)
                    """
                )
                throw error
            }
        } else {
            logger.error(
                """
                Download response received: url=\(remoteURL.absoluteString, privacy: .public) \
                path=\(remoteURL.path, privacy: .public) \
                status=non-http \
                mediaType=\(mediaType.rawValue, privacy: .public)
                """
            )
            throw MediaFileDownloaderError.invalidResponse(nil)
        }

        if !fileManager.fileExists(atPath: temporaryURL.path) {
            throw MediaFileDownloaderError.invalidTemporaryFile
        }

        onProgress?(1)
        return temporaryURL
    }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = BridgeConfig.current.downloadRequestTimeout
        configuration.timeoutIntervalForResource = BridgeConfig.current.downloadResourceTimeout
        return URLSession(configuration: configuration)
    }

    private func mapTransportError(_ error: Error) -> MediaFileDownloaderError {
        guard let urlError = error as? URLError else {
            return .transportFailed(error.localizedDescription)
        }

        switch urlError.code {
        case .timedOut:
            return .requestTimedOut
        case .notConnectedToInternet, .dataNotAllowed:
            return .networkOffline
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            return .transportFailed("The remote download server could not be reached.")
        default:
            return .transportFailed(urlError.localizedDescription)
        }
    }
}
