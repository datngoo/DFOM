import Foundation
import OSLog

protocol YouTubeExtractorBridgeResolving {
    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> BridgeResolvedDownload
}

struct BridgeResolvedDownload: Equatable, Sendable {
    let remoteURL: URL
    let mimeType: String?
    let suggestedFileExtension: String?
    let provider: String
    let providerItemId: String
}

struct YouTubeExtractorBridgeClient: YouTubeExtractorBridgeResolving {
    enum ClientError: Error, Equatable, LocalizedError {
        case transportFailure(String?)
        case networkOffline
        case requestTimedOut
        case invalidResponse(Int?, String?)
        case missingDownloadURL(MediaType)
        case noDownloadableMedia(MediaType, String?)
        case extractorRejected(String?)
        case extractorFailed(String?)
        case serverUnavailable(Int, String?)

        var errorDescription: String? {
            switch self {
            case .transportFailure(let message):
                return message ?? "The YouTube extractor bridge could not be reached."
            case .networkOffline:
                return "You appear to be offline. Reconnect to the internet and try again."
            case .requestTimedOut:
                return "The bridge server took too long to respond. If it is waking up, try again in a moment."
            case .invalidResponse(let statusCode, let message):
                if let message {
                    return message
                }
                if let statusCode {
                    return "The YouTube extractor bridge returned an invalid response (HTTP \(statusCode))."
                }
                return "The YouTube extractor bridge returned an invalid response."
            case .missingDownloadURL(let mediaType):
                return "The bridge server did not return a downloadable \(mediaType.rawValue) file."
            case .noDownloadableMedia(let mediaType, let message):
                return message ?? "The extractor could not find a downloadable \(mediaType.rawValue) stream for this item."
            case .extractorRejected(let message):
                return message ?? "The extractor rejected this YouTube download request."
            case .extractorFailed(let message):
                return message ?? "The bridge server could not extract a downloadable stream for this item."
            case .serverUnavailable(let statusCode, let message):
                return message ?? "The bridge server is unavailable right now (HTTP \(statusCode))."
            }
        }
    }

    private let configuration: any YouTubeExtractorBridgeConfiguring
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeExtractorBridgeClient")

    init(
        configuration: any YouTubeExtractorBridgeConfiguring = YouTubeExtractorBridgeConfiguration(),
        session: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> BridgeResolvedDownload {
        let baseURL = try configuration.bridgeBaseURL()
        let apiStyle = configuration.bridgeAPIStyle()
        let totalAttempts = max(1, configuredAttemptCount(for: apiStyle))

        var lastError: ClientError?

        for attemptIndex in 0..<totalAttempts {
            do {
                return try await performResolveAttempt(
                    baseURL: baseURL,
                    apiStyle: apiStyle,
                    item: item,
                    mediaType: mediaType,
                    attemptNumber: attemptIndex + 1
                )
            } catch let error as ClientError {
                lastError = error

                guard shouldRetryResolve(
                    after: error,
                    apiStyle: apiStyle,
                    attemptIndex: attemptIndex,
                    totalAttempts: totalAttempts
                ) else {
                    throw error
                }

                await prepareForResolveRetry(
                    baseURL: baseURL,
                    item: item,
                    mediaType: mediaType,
                    attemptNumber: attemptIndex + 1,
                    error: error
                )
            }
        }

        throw lastError ?? ClientError.invalidResponse(nil, "The bridge request did not complete.")
    }

    private func performResolveAttempt(
        baseURL: URL,
        apiStyle: BridgeAPIStyle,
        item: ResolvedMediaItem,
        mediaType: MediaType,
        attemptNumber: Int
    ) async throws -> BridgeResolvedDownload {
        let endpointURL = endpointURL(for: baseURL, apiStyle: apiStyle)
        let request = try makeResolveRequest(
            endpointURL: endpointURL,
            apiStyle: apiStyle,
            item: item,
            mediaType: mediaType
        )

        logger.info(
            """
            Bridge request started: method=POST \
            url=\(endpointURL.absoluteString, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public) \
            itemID=\(item.providerItemId, privacy: .public) \
            sourceURL=\(item.sourcePageURL.absoluteString, privacy: .public) \
            attempt=\(attemptNumber, privacy: .public)
            """
        )

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            let clientError = mapTransportError(error)
            logger.error(
                """
                Bridge transport failed: baseURL=\(baseURL.absoluteString, privacy: .public) \
                path=\(endpointURL.path, privacy: .public) \
                mediaType=\(mediaType.rawValue, privacy: .public) \
                itemID=\(item.providerItemId, privacy: .public) \
                attempt=\(attemptNumber, privacy: .public) \
                reason=\(String(describing: clientError), privacy: .public) \
                underlying=\(String(describing: error), privacy: .public)
                """
            )
            throw clientError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error(
                """
                Bridge returned non-HTTP response: baseURL=\(baseURL.absoluteString, privacy: .public) \
                path=\(endpointURL.path, privacy: .public) \
                mediaType=\(mediaType.rawValue, privacy: .public) \
                itemID=\(item.providerItemId, privacy: .public) \
                attempt=\(attemptNumber, privacy: .public)
                """
            )
            throw ClientError.invalidResponse(nil, "The bridge server returned a non-HTTP response.")
        }

        logger.info(
            """
            Bridge response received: baseURL=\(baseURL.absoluteString, privacy: .public) \
            path=\(endpointURL.path, privacy: .public) \
            status=\(httpResponse.statusCode, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public) \
            itemID=\(item.providerItemId, privacy: .public) \
            attempt=\(attemptNumber, privacy: .public)
            """
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            let bridgeError = decodeBridgeError(from: responseData, statusCode: httpResponse.statusCode, mediaType: mediaType)
            logBridgeError(bridgeError, itemID: item.providerItemId, mediaType: mediaType, path: endpointURL.path)
            throw bridgeError
        }

        do {
            let resolvedDownload = try decodeResolvedDownload(
                from: responseData,
                statusCode: httpResponse.statusCode,
                apiStyle: apiStyle,
                item: item,
                mediaType: mediaType
            )
            logger.debug("Bridge resolved \(mediaType.rawValue, privacy: .public) download for \(item.providerItemId, privacy: .public)")
            return resolvedDownload
        } catch let error as ClientError {
            logBridgeError(error, itemID: item.providerItemId, mediaType: mediaType, path: endpointURL.path)
            throw error
        } catch {
            logger.error(
                """
                Bridge response decoding failed: baseURL=\(baseURL.absoluteString, privacy: .public) \
                path=\(endpointURL.path, privacy: .public) \
                mediaType=\(mediaType.rawValue, privacy: .public) \
                itemID=\(item.providerItemId, privacy: .public) \
                attempt=\(attemptNumber, privacy: .public) \
                reason=\(String(describing: error), privacy: .public)
                """
            )
            throw ClientError.invalidResponse(
                httpResponse.statusCode,
                "The bridge server returned unreadable JSON."
            )
        }
    }

    private func makeResolveRequest(
        endpointURL: URL,
        apiStyle: BridgeAPIStyle,
        item: ResolvedMediaItem,
        mediaType: MediaType
    ) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.resolveRequestTimeoutInterval()

        switch apiStyle {
        case .legacyResolveDownload:
            let requestBody = BridgeRequestDTO(
                provider: item.provider,
                providerItemId: item.providerItemId,
                sourcePageURL: item.sourcePageURL.absoluteString,
                mediaType: mediaType.rawValue
            )
            request.httpBody = try encoder.encode(requestBody)
        case .stableResolve:
            request.httpBody = try encoder.encode(
                StableBridgeResolveRequestDTO(url: item.sourcePageURL.absoluteString)
            )
        }

        return request
    }

    private func decodeBridgeError(from data: Data, statusCode: Int, mediaType: MediaType) -> ClientError {
        let legacyPayload = try? decoder.decode(BridgeErrorResponseDTO.self, from: data)
        let stablePayload = try? decoder.decode(StableBridgeErrorResponseDTO.self, from: data)

        let code = normalizedBridgeValue(legacyPayload?.error)
        let message = normalizedBridgeValue(legacyPayload?.message) ?? normalizedBridgeValue(stablePayload?.error)

        if statusCode == 404 || statusCode == 422 || code == "no_downloadable_media" {
            return .noDownloadableMedia(mediaType, message)
        }

        if code == "extractor_failure" || messageIndicatesExtractionFailure(message) {
            return .extractorFailed(message)
        }

        if (500...599).contains(statusCode) {
            return .serverUnavailable(statusCode, message)
        }

        if (400...499).contains(statusCode) {
            return .extractorRejected(message)
        }

        return .invalidResponse(
            statusCode,
            message ?? "The bridge server returned an unexpected response."
        )
    }

    private func decodeResolvedDownload(
        from data: Data,
        statusCode: Int,
        apiStyle: BridgeAPIStyle,
        item: ResolvedMediaItem,
        mediaType: MediaType
    ) throws -> BridgeResolvedDownload {
        let responseDTO: BridgeResponseDTO

        switch apiStyle {
        case .legacyResolveDownload:
            responseDTO = try decoder.decode(BridgeResponseDTO.self, from: data)
        case .stableResolve:
            let stableResponse = try decoder.decode(StableBridgeResolveResponseDTO.self, from: data)
            guard stableResponse.ok == true else {
                throw ClientError.invalidResponse(
                    statusCode,
                    "The bridge server returned an unsuccessful resolve response."
                )
            }

            guard let selectedResponse = stableResponse.response(for: mediaType) else {
                throw ClientError.noDownloadableMedia(
                    mediaType,
                    "The extractor could not find a downloadable \(mediaType.rawValue) stream for this item."
                )
            }

            responseDTO = selectedResponse
        }

        guard let downloadURLString = normalizedBridgeValue(responseDTO.downloadURL) else {
            throw ClientError.missingDownloadURL(mediaType)
        }

        guard let remoteURL = URL(string: downloadURLString),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw ClientError.invalidResponse(
                statusCode,
                "The bridge server returned an invalid download URL."
            )
        }

        let provider = normalizedBridgeValue(responseDTO.provider) ?? item.provider
        let providerItemId = normalizedBridgeValue(responseDTO.providerItemId) ?? item.providerItemId
        let mimeType = normalizedBridgeValue(responseDTO.mimeType)
        let suggestedFileExtension = normalizedBridgeValue(responseDTO.fileExtension)

        return BridgeResolvedDownload(
            remoteURL: remoteURL,
            mimeType: mimeType,
            suggestedFileExtension: suggestedFileExtension,
            provider: provider,
            providerItemId: providerItemId
        )
    }

    private func performHealthCheck(baseURL: URL) async {
        let healthURL = baseURL.appendingPathComponent("health", isDirectory: false)
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.healthRequestTimeoutInterval()

        logger.info(
            "Bridge health probe started: baseURL=\(baseURL.absoluteString, privacy: .public) path=\(healthURL.path, privacy: .public)"
        )

        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.info(
                "Bridge health probe completed: baseURL=\(baseURL.absoluteString, privacy: .public) path=\(healthURL.path, privacy: .public) status=\(statusCode, privacy: .public)"
            )
        } catch {
            logger.error(
                "Bridge health probe failed: baseURL=\(baseURL.absoluteString, privacy: .public) path=\(healthURL.path, privacy: .public) reason=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func shouldRetryResolve(
        after error: ClientError,
        apiStyle: BridgeAPIStyle,
        attemptIndex: Int,
        totalAttempts: Int
    ) -> Bool {
        guard apiStyle == .stableResolve else {
            return false
        }

        guard attemptIndex + 1 < totalAttempts else {
            return false
        }

        switch error {
        case .requestTimedOut, .transportFailure, .serverUnavailable:
            return true
        case .networkOffline, .invalidResponse, .missingDownloadURL, .noDownloadableMedia, .extractorRejected, .extractorFailed:
            return false
        }
    }

    private func prepareForResolveRetry(
        baseURL: URL,
        item: ResolvedMediaItem,
        mediaType: MediaType,
        attemptNumber: Int,
        error: ClientError
    ) async {
        logger.info(
            """
            Retrying bridge resolve request: baseURL=\(baseURL.absoluteString, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public) \
            itemID=\(item.providerItemId, privacy: .public) \
            previousAttempt=\(attemptNumber, privacy: .public) \
            reason=\(error.localizedDescription, privacy: .public)
            """
        )

        await performHealthCheck(baseURL: baseURL)

        let delayNanoseconds = UInt64(configuration.resolveRetryDelayInterval() * 1_000_000_000)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }

    private func configuredAttemptCount(for apiStyle: BridgeAPIStyle) -> Int {
        switch apiStyle {
        case .legacyResolveDownload:
            return 1
        case .stableResolve:
            return configuration.maxResolveRetries() + 1
        }
    }

    private func endpointURL(for baseURL: URL, apiStyle: BridgeAPIStyle) -> URL {
        switch apiStyle {
        case .legacyResolveDownload:
            return baseURL.appendingPathComponent("resolve-download", isDirectory: false)
        case .stableResolve:
            return baseURL.appendingPathComponent("resolve", isDirectory: false)
        }
    }

    private func normalizedBridgeValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapTransportError(_ error: Error) -> ClientError {
        guard let urlError = error as? URLError else {
            return .transportFailure(error.localizedDescription)
        }

        switch urlError.code {
        case .timedOut:
            return .requestTimedOut
        case .notConnectedToInternet, .dataNotAllowed:
            return .networkOffline
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            return .transportFailure("The bridge server could not be reached.")
        default:
            return .transportFailure(urlError.localizedDescription)
        }
    }

    private func messageIndicatesExtractionFailure(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else {
            return false
        }

        return message.contains("extract")
            || message.contains("yt-dlp")
            || message.contains("downloadable stream")
    }

    private func logBridgeError(_ error: ClientError, itemID: String, mediaType: MediaType, path: String) {
        logger.error(
            """
            Bridge request failed: path=\(path, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public) \
            itemID=\(itemID, privacy: .public) \
            reason=\(error.localizedDescription, privacy: .public)
            """
        )
    }
}

private struct BridgeRequestDTO: Encodable {
    let provider: String
    let providerItemId: String
    let sourcePageURL: String
    let mediaType: String
}

private struct StableBridgeResolveRequestDTO: Encodable {
    let url: String
}

private struct BridgeResponseDTO: Decodable {
    let downloadURL: String?
    let mimeType: String?
    let fileExtension: String?
    let provider: String?
    let providerItemId: String?
}

private struct StableBridgeResolveResponseDTO: Decodable {
    let ok: Bool?
    let provider: String?
    let providerItemId: String?
    let sourcePageURL: String?
    let availableMediaTypes: [String]?
    let audio: BridgeResponseDTO?
    let video: BridgeResponseDTO?

    func response(for mediaType: MediaType) -> BridgeResponseDTO? {
        switch mediaType {
        case .audio:
            return audio
        case .video:
            return video
        case .unknown:
            return nil
        }
    }
}

private struct BridgeErrorResponseDTO: Decodable {
    let error: String?
    let message: String?
}

private struct StableBridgeErrorResponseDTO: Decodable {
    let ok: Bool?
    let error: String?
}
