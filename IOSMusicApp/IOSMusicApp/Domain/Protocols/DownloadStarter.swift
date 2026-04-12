protocol DownloadStarter {
    func startDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws
}
