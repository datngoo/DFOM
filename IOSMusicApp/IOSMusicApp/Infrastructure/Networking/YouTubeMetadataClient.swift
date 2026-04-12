import Foundation

struct YouTubeMetadataClient {
    enum ClientError: Error, Equatable {
        case invalidRequestURL
        case transportFailure
        case invalidResponse
        case httpError(Int)
        case decodingFailure
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.decoder = decoder
    }

    func fetchMetadata(forVideoID videoID: String) async throws -> YouTubeVideoDTO {
        guard let requestURL = metadataURL(forVideoID: videoID) else {
            throw ClientError.invalidRequestURL
        }

        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await session.data(from: requestURL)
        } catch {
            throw ClientError.transportFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClientError.httpError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(YouTubeVideoDTO.self, from: responseData)
        } catch {
            throw ClientError.decodingFailure
        }
    }

    private func metadataURL(forVideoID videoID: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json")
        ]

        return components?.url
    }
}
