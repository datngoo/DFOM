import Foundation
import OSLog

struct YouTubeBridgeDownloadProvider: DownloadProvider {
    private let bridgeClient: any YouTubeExtractorBridgeResolving
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeBridgeDownloadProvider")

    init(bridgeClient: any YouTubeExtractorBridgeResolving = YouTubeExtractorBridgeClient()) {
        self.bridgeClient = bridgeClient
    }

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        guard item.provider == YouTubeURLResolutionProvider.providerName else {
            throw ProviderError.mappingFailed
        }

        guard item.availableMediaTypes.contains(mediaType), mediaType != .unknown else {
            throw ProviderError.unsupportedMediaType
        }

        let resolvedDownload: BridgeResolvedDownload
        do {
            resolvedDownload = try await bridgeClient.resolveDownload(for: item, mediaType: mediaType)
        } catch let error as ProviderError {
            throw error
        } catch {
            logger.error(
                "Bridge provider failed to resolve \(mediaType.rawValue, privacy: .public) for \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            throw ProviderError.downloadResolutionFailed(message)
        }

        logger.debug("Bridge provider mapped \(mediaType.rawValue, privacy: .public) descriptor for \(item.providerItemId, privacy: .public)")

        return DownloadDescriptor(
            remoteURL: resolvedDownload.remoteURL,
            mediaType: mediaType,
            suggestedFileExtension: resolvedDownload.suggestedFileExtension,
            mimeType: resolvedDownload.mimeType,
            provider: resolvedDownload.provider,
            providerItemId: resolvedDownload.providerItemId
        )
    }
}
