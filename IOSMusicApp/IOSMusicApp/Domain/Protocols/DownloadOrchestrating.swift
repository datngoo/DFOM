import Foundation

protocol DownloadOrchestrating: DownloadStarter {
    func currentState(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadStateSnapshot?
}
