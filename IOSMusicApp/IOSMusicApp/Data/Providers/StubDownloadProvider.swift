struct StubDownloadProvider: DownloadProvider {
    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        throw ProviderError.notImplementedInSpike
    }
}
