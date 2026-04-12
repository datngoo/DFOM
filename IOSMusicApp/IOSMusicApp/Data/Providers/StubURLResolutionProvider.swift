import Foundation

struct StubURLResolutionProvider: URLResolutionProvider {
    func resolve(url: URL) async throws -> ResolvedMediaItem {
        throw ProviderError.notImplementedInSpike
    }
}
