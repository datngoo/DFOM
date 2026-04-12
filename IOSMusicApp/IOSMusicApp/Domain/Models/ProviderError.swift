import Foundation

enum ProviderError: Error, Equatable, LocalizedError {
    case invalidURL
    case unsupportedURL
    case metadataFetchFailed
    case mappingFailed
    case downloadResolutionFailed
    case unsupportedMediaType
    case notImplementedInSpike

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is invalid."
        case .unsupportedURL:
            return "The URL is not supported by the current provider."
        case .metadataFetchFailed:
            return "The provider could not fetch media metadata."
        case .mappingFailed:
            return "The provider could not map source data into app models."
        case .downloadResolutionFailed:
            return "The provider could not resolve a downloadable media variant."
        case .unsupportedMediaType:
            return "The requested media type is not supported."
        case .notImplementedInSpike:
            return "This behavior is intentionally not implemented in the KAN-7 spike."
        }
    }
}
