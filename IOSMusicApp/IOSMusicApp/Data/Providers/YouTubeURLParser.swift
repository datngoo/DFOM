import Foundation

struct YouTubeURLParser {
    private let supportedHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "youtu.be",
        "www.youtu.be"
    ]

    func validate(url: URL) throws {
        _ = try videoID(from: url)
    }

    func videoID(from url: URL) throws -> String {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ProviderError.invalidURL
        }

        guard let host = url.host?.lowercased(), supportedHosts.contains(host) else {
            throw ProviderError.unsupportedURL
        }

        if host.contains("youtu.be") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard let candidate = pathComponents.first, isPlausibleVideoID(candidate) else {
                throw ProviderError.invalidURL
            }

            return candidate
        }

        let normalizedPath = url.path.lowercased()

        if normalizedPath == "/watch" || normalizedPath == "/watch/" {
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
                isPlausibleVideoID(videoID)
            else {
                throw ProviderError.invalidURL
            }

            return videoID
        }

        if normalizedPath.hasPrefix("/shorts/") || normalizedPath.hasPrefix("/embed/") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard let candidate = pathComponents.last, isPlausibleVideoID(candidate) else {
                throw ProviderError.invalidURL
            }

            return candidate
        }

        throw ProviderError.unsupportedURL
    }

    private func isPlausibleVideoID(_ value: String) -> Bool {
        let allowedCharacterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let scalars = value.unicodeScalars

        return value.count >= 6 && value.count <= 32 && scalars.allSatisfy(allowedCharacterSet.contains)
    }
}
