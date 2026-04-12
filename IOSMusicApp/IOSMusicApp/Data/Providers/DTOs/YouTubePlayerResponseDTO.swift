import Foundation

struct YouTubePlayerResponseDTO: Decodable, Sendable {
    let streamingData: StreamingData?
    let playabilityStatus: PlayabilityStatus?

    struct StreamingData: Decodable, Sendable {
        let formats: [Format]
        let adaptiveFormats: [Format]

        init(
            formats: [Format] = [],
            adaptiveFormats: [Format] = []
        ) {
            self.formats = formats
            self.adaptiveFormats = adaptiveFormats
        }
    }

    struct PlayabilityStatus: Decodable, Sendable {
        let status: String?
        let reason: String?
    }

    struct Format: Decodable, Sendable {
        let itag: Int?
        let mimeType: String?
        let bitrate: Int?
        let averageBitrate: Int?
        let width: Int?
        let height: Int?
        let qualityLabel: String?
        let audioQuality: String?
        let url: String?
        let signatureCipher: String?
        let cipher: String?
        let contentLength: String?
    }
}
