import Foundation

protocol URLResolutionProvider {
    func resolve(url: URL) async throws -> ResolvedMediaItem
}
