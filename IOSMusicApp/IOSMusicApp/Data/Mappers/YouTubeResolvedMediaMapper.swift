import Foundation

struct YouTubeResolvedMediaMapper {
    func map(
        dto: YouTubeVideoDTO,
        videoID: String,
        sourcePageURL: URL
    ) throws -> ResolvedMediaItem {
        let trimmedTitle = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            throw ProviderError.mappingFailed
        }

        return ResolvedMediaItem(
            provider: YouTubeURLResolutionProvider.providerName,
            providerItemId: videoID,
            title: trimmedTitle,
            creatorName: dto.authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
            thumbnailURL: dto.thumbnailURL,
            durationSeconds: nil,
            sourcePageURL: sourcePageURL,
            availableMediaTypes: [.audio, .video]
        )
    }
}
