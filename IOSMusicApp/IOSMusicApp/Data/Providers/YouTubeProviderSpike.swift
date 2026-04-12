import Foundation

struct YouTubeProviderSpike: URLResolutionProvider, DownloadProvider {
    static let providerName = "youtube"

    private let parser: YouTubeURLParser

    init(parser: YouTubeURLParser = YouTubeURLParser()) {
        self.parser = parser
    }

    func resolve(url: URL) async throws -> ResolvedMediaItem {
        let videoID = try parser.videoID(from: url)

        return ResolvedMediaItem(
            provider: Self.providerName,
            providerItemId: videoID,
            title: "YouTube Spike Item \(videoID.prefix(6))",
            creatorName: "KAN-7 Spike Channel",
            thumbnailURL: URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"),
            durationSeconds: 245,
            sourcePageURL: canonicalWatchURL(for: videoID),
            availableMediaTypes: [.audio, .video]
        )
    }

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        guard item.provider == Self.providerName else {
            throw ProviderError.mappingFailed
        }

        guard item.availableMediaTypes.contains(mediaType) else {
            throw ProviderError.unsupportedMediaType
        }

        switch mediaType {
        case .audio:
            return DownloadDescriptor(
                remoteURL: URL(string: "https://example.invalid/kan7/youtube/\(item.providerItemId)/audio")!,
                mediaType: .audio,
                suggestedFileExtension: "m4a",
                mimeType: "audio/mp4",
                provider: item.provider,
                providerItemId: item.providerItemId
            )
        case .video:
            return DownloadDescriptor(
                remoteURL: URL(string: "https://example.invalid/kan7/youtube/\(item.providerItemId)/video")!,
                mediaType: .video,
                suggestedFileExtension: "mp4",
                mimeType: "video/mp4",
                provider: item.provider,
                providerItemId: item.providerItemId
            )
        case .unknown:
            throw ProviderError.unsupportedMediaType
        }
    }

    private func canonicalWatchURL(for videoID: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}
