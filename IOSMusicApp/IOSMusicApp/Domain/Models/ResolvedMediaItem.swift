import Foundation

struct ResolvedMediaItem: Equatable, Hashable, Sendable {
    let provider: String
    let providerItemId: String
    let title: String
    let creatorName: String?
    let thumbnailURL: URL?
    let durationSeconds: Double?
    let sourcePageURL: URL
    let availableMediaTypes: [MediaType]
}
