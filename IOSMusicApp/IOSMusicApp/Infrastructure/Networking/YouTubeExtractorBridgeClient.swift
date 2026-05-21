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
    enum NetworkFailureReason: Equatable {
        case timedOut
        case cannotConnectToHost
        case networkConnectionLost
        case notConnectedToInternet
        case other

        var userFacingMessage: String {
            switch self {
            case .timedOut:
                return "Bridge request timed out."
            case .cannotConnectToHost:
                return "Bridge is not reachable."
            case .networkConnectionLost:
                return "Bridge connection was lost."
            case .notConnectedToInternet:
                return "No network connection."
            case .other:
                return "Bridge transport error."
            }
        }
    }

    enum BridgeErrorCode: String, Equatable {
        case videoUnavailable = "VIDEO_UNAVAILABLE"
        case videoPrivate = "VIDEO_PRIVATE"
        case videoAgeRestricted = "VIDEO_AGE_RESTRICTED"
        case formatUnavailable = "FORMAT_UNAVAILABLE"
        case providerBlocked = "PROVIDER_BLOCKED"
        case extractorFailed = "EXTRACTOR_FAILED"

        var userFacingMessage: String {
            switch self {
            case .videoUnavailable, .videoPrivate, .videoAgeRestricted, .formatUnavailable, .providerBlocked, .extractorFailed:
                return "This YouTube video is unavailable or cannot be downloaded."
            }
        }
    }

    enum ClientError: Error, Equatable, LocalizedError {
        case transportFailure(NetworkFailureReason)
        case healthCheckFailed(URL, NetworkFailureReason?)
        case invalidResponse(Int?)
        case noDownloadableMedia(MediaType, String?)
        case extractorFailure(BridgeErrorCode, String?)
        case extractorRejected(String?)

        var errorDescription: String? {
            switch self {
            case .transportFailure(let reason):
                return reason.userFacingMessage
            case .healthCheckFailed:
                return "Bridge is not reachable. Make sure the bridge is running, your iPhone and Mac are on the same Wi-Fi, and macOS Firewall allows incoming connections."
            case .invalidResponse(let statusCode):
                if let statusCode {
                    return "The YouTube extractor bridge returned an invalid response (HTTP \(statusCode))."
                }
                return "The YouTube extractor bridge returned an invalid response."
            case .noDownloadableMedia(let mediaType, let message):
                return message ?? "The extractor could not find a downloadable \(mediaType.rawValue) stream for this item."
            case .extractorFailure(let code, _):
                return code.userFacingMessage
            case .extractorRejected(let message):
                return message ?? "The extractor rejected this YouTube download request."
            }
        }
    }

    private let configuration: any YouTubeExtractorBridgeConfiguring
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeExtractorBridgeClient")
    private let requestTimeout: TimeInterval = 15

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
        let endpointURL = baseURL
            .appendingPathComponent("resolve-download", isDirectory: false)

        try await performHealthCheck(baseURL: baseURL, mediaType: mediaType, itemID: item.providerItemId)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let requestBody = BridgeRequestDTO(
            provider: item.provider,
            providerItemId: item.providerItemId,
            sourcePageURL: item.sourcePageURL.absoluteString,
            mediaType: mediaType.rawValue
        )
        request.httpBody = try encoder.encode(requestBody)
        logBridgeRequest(
            kind: "resolve-download",
            baseURL: baseURL,
            requestURL: endpointURL,
            mediaType: mediaType,
            itemID: item.providerItemId
        )

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            let reason = networkFailureReason(from: error)
            logger.error("Bridge transport failed for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public): \(reason.userFacingMessage, privacy: .public) \(String(describing: error), privacy: .public)")
            throw ClientError.transportFailure(reason)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Bridge returned non-HTTP response for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            throw ClientError.invalidResponse(nil)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let bridgeError = decodeBridgeError(from: responseData, statusCode: httpResponse.statusCode, mediaType: mediaType)
            logBridgeError(bridgeError, itemID: item.providerItemId, mediaType: mediaType)
            throw bridgeError
        }

        let responseDTO: BridgeResponseDTO
        do {
            responseDTO = try decoder.decode(BridgeResponseDTO.self, from: responseData)
        } catch {
            logger.error("Bridge response decoding failed for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            throw ClientError.invalidResponse(httpResponse.statusCode)
        }

        guard let downloadURLString = responseDTO.downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !downloadURLString.isEmpty,
              let remoteURL = URL(string: downloadURLString),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            logger.error("Bridge response missing valid downloadable URL for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public)")
            throw ClientError.invalidResponse(httpResponse.statusCode)
        }

        let provider = normalizedBridgeValue(responseDTO.provider) ?? item.provider
        let providerItemId = normalizedBridgeValue(responseDTO.providerItemId) ?? item.providerItemId
        let mimeType = normalizedBridgeValue(responseDTO.mimeType)
        let suggestedFileExtension = normalizedBridgeValue(responseDTO.fileExtension)

        logger.debug("Bridge resolved \(mediaType.rawValue, privacy: .public) download for \(item.providerItemId, privacy: .public)")

        return BridgeResolvedDownload(
            remoteURL: remoteURL,
            mimeType: mimeType,
            suggestedFileExtension: suggestedFileExtension,
            provider: provider,
            providerItemId: providerItemId
        )
    }

    private func performHealthCheck(baseURL: URL, mediaType: MediaType, itemID: String) async throws {
        let healthURL = baseURL.appendingPathComponent("health", isDirectory: false)
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logBridgeRequest(
            kind: "health",
            baseURL: baseURL,
            requestURL: healthURL,
            mediaType: mediaType,
            itemID: itemID
        )

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            let reason = networkFailureReason(from: error)
            logger.error("Bridge health check failed for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): url=\(healthURL.absoluteString, privacy: .public) reason=\(reason.userFacingMessage, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw ClientError.healthCheckFailed(healthURL, reason)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Bridge health check returned invalid response for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): url=\(healthURL.absoluteString, privacy: .public) status=\(statusCode, privacy: .public)")
            throw ClientError.healthCheckFailed(healthURL, nil)
        }
    }

    private func decodeBridgeError(from data: Data, statusCode: Int, mediaType: MediaType) -> ClientError {
        let payload = try? decoder.decode(BridgeErrorResponseDTO.self, from: data)
        let code = normalizedBridgeValue(payload?.error)
        let message = normalizedBridgeValue(payload?.message)

        if let code, let bridgeErrorCode = BridgeErrorCode(rawValue: code) {
            return .extractorFailure(bridgeErrorCode, message)
        }

        if statusCode == 404 || statusCode == 410 || statusCode == 422 || code == "no_downloadable_media" {
            return .noDownloadableMedia(mediaType, message)
        }

        if (400...499).contains(statusCode) {
            return .extractorRejected(message)
        }

        return .invalidResponse(statusCode)
    }

    private func normalizedBridgeValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func networkFailureReason(from error: Error) -> NetworkFailureReason {
        let urlError = error as? URLError
        switch urlError?.code {
        case .timedOut:
            return .timedOut
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .cannotConnectToHost
        case .networkConnectionLost:
            return .networkConnectionLost
        case .notConnectedToInternet:
            return .notConnectedToInternet
        default:
            return .other
        }
    }

    private func logBridgeRequest(
        kind: String,
        baseURL: URL,
        requestURL: URL,
        mediaType: MediaType,
        itemID: String
    ) {
        logger.debug(
            """
            Bridge \(kind, privacy: .public) request \
            device=\(runtimeEnvironmentLabel, privacy: .public) \
            mediaType=\(mediaType.rawValue, privacy: .public) \
            itemID=\(itemID, privacy: .public) \
            baseURL=\(baseURL.absoluteString, privacy: .public) \
            requestURL=\(requestURL.absoluteString, privacy: .public) \
            timeout=\(requestTimeout, privacy: .public)s
            """
        )
    }

    private var runtimeEnvironmentLabel: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "physical-device"
        #endif
    }

    private func logBridgeError(_ error: ClientError, itemID: String, mediaType: MediaType) {
        switch error {
        case .transportFailure(let reason):
            logger.error("Bridge transport failure for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): \(reason.userFacingMessage, privacy: .public)")
        case .healthCheckFailed(let url, let reason):
            logger.error("Bridge health check failure for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): url=\(url.absoluteString, privacy: .public) reason=\(reason?.userFacingMessage ?? "invalid response", privacy: .public)")
        case .invalidResponse(let statusCode):
            logger.error("Bridge invalid response for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): HTTP \(statusCode ?? -1, privacy: .public)")
        case .noDownloadableMedia:
            logger.error("Bridge reported no downloadable \(mediaType.rawValue, privacy: .public) media for \(itemID, privacy: .public)")
        case .extractorFailure(let code, let message):
            logger.error("Bridge extractor failure for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): \(code.rawValue, privacy: .public) \(message ?? "no message", privacy: .public)")
        case .extractorRejected(let message):
            logger.error("Bridge rejected \(mediaType.rawValue, privacy: .public) request for \(itemID, privacy: .public): \(message ?? "no message", privacy: .public)")
        }
    }
}

private struct BridgeRequestDTO: Encodable {
    let provider: String
    let providerItemId: String
    let sourcePageURL: String
    let mediaType: String
}

private struct BridgeResponseDTO: Decodable {
    let downloadURL: String?
    let mimeType: String?
    let fileExtension: String?
    let provider: String?
    let providerItemId: String?
}

private struct BridgeErrorResponseDTO: Decodable {
    let error: String?
    let message: String?
}
