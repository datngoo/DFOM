import Foundation

struct YouTubeVideoDTO: Decodable, Equatable, Sendable {
    let title: String
    let authorName: String?
    let authorURL: URL?
    let type: String?
    let version: String?
    let providerName: String?
    let providerURL: URL?
    let thumbnailURL: URL?
    let thumbnailWidth: Int?
    let thumbnailHeight: Int?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case authorURL = "author_url"
        case type
        case version
        case providerName = "provider_name"
        case providerURL = "provider_url"
        case thumbnailURL = "thumbnail_url"
        case thumbnailWidth = "thumbnail_width"
        case thumbnailHeight = "thumbnail_height"
        case width
        case height
    }
}
