import Foundation

struct YouTubeURLResolutionProvider: URLResolutionProvider {
    static let providerName = "youtube"

    private let parser: YouTubeURLParser
    private let metadataClient: YouTubeMetadataClient
    private let mapper: YouTubeResolvedMediaMapper

    init(
        parser: YouTubeURLParser = YouTubeURLParser(),
        metadataClient: YouTubeMetadataClient = YouTubeMetadataClient(),
        mapper: YouTubeResolvedMediaMapper = YouTubeResolvedMediaMapper()
    ) {
        self.parser = parser
        self.metadataClient = metadataClient
        self.mapper = mapper
    }

    func resolve(url: URL) async throws -> ResolvedMediaItem {
        let videoID = try parser.videoID(from: url)
        let canonicalURL = canonicalWatchURL(for: videoID)

        let dto: YouTubeVideoDTO
        do {
            dto = try await metadataClient.fetchMetadata(forVideoID: videoID)
        } catch let error as YouTubeMetadataClient.ClientError {
            switch error {
            case .invalidRequestURL:
                throw ProviderError.invalidURL
            case .transportFailure, .invalidResponse, .httpError, .decodingFailure:
                throw ProviderError.metadataFetchFailed
            }
        } catch {
            throw ProviderError.metadataFetchFailed
        }

        do {
            return try mapper.map(
                dto: dto,
                videoID: videoID,
                sourcePageURL: canonicalURL
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.mappingFailed
        }
    }

    private func canonicalWatchURL(for videoID: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}
