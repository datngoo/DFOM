import OSLog

struct StubDownloadStarter: DownloadOrchestrating {
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "DownloadStarter")

    func currentState(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadStateSnapshot? {
        nil
    }

    func startDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws {
        guard item.availableMediaTypes.contains(mediaType) else {
            throw ProviderError.unsupportedMediaType
        }

        logger.debug(
            "KAN-10 stub download entry for item \(item.providerItemId, privacy: .public) as \(mediaType.rawValue, privacy: .public)"
        )
    }
}
