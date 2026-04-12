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
        case transportFailure
        case invalidResponse(Int?)
        case noDownloadableMedia(MediaType, String?)
        case extractorRejected(String?)

        var errorDescription: String? {
            switch self {
            case .transportFailure:
                return "The YouTube extractor bridge could not be reached."
            case .invalidResponse(let statusCode):
                if let statusCode {
                    return "The YouTube extractor bridge returned an invalid response (HTTP \(statusCode))."
                }
                return "The YouTube extractor bridge returned an invalid response."
            case .noDownloadableMedia(let mediaType, let message):
                return message ?? "The extractor could not find a downloadable \(mediaType.rawValue) stream for this item."
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

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let requestBody = BridgeRequestDTO(
            provider: item.provider,
            providerItemId: item.providerItemId,
            sourcePageURL: item.sourcePageURL.absoluteString,
            mediaType: mediaType.rawValue
        )
        request.httpBody = try encoder.encode(requestBody)

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            logger.error("Bridge transport failed for \(mediaType.rawValue, privacy: .public) \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            throw ClientError.transportFailure
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

    private func decodeBridgeError(from data: Data, statusCode: Int, mediaType: MediaType) -> ClientError {
        let payload = try? decoder.decode(BridgeErrorResponseDTO.self, from: data)
        let code = normalizedBridgeValue(payload?.error)
        let message = normalizedBridgeValue(payload?.message)

        if statusCode == 404 || statusCode == 422 || code == "no_downloadable_media" {
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

    private func logBridgeError(_ error: ClientError, itemID: String, mediaType: MediaType) {
        switch error {
        case .transportFailure:
            logger.error("Bridge transport failure for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public)")
        case .invalidResponse(let statusCode):
            logger.error("Bridge invalid response for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): HTTP \(statusCode ?? -1, privacy: .public)")
        case .noDownloadableMedia:
            logger.error("Bridge reported no downloadable \(mediaType.rawValue, privacy: .public) media for \(itemID, privacy: .public)")
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
