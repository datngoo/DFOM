import Foundation
import Testing
import SwiftData
@testable import IOSMusicApp

struct IOSMusicAppTests {

    @Test
    func youTubeBridgeDownloadProviderMapsBridgeResponseToDownloadDescriptor() async throws {
        let provider = YouTubeBridgeDownloadProvider(
            bridgeClient: TestYouTubeExtractorBridgeClient(
                result: .success(
                    BridgeResolvedDownload(
                        remoteURL: URL(string: "https://bridge.example.com/media/audio.m4a")!,
                        mimeType: "audio/mp4",
                        suggestedFileExtension: "m4a",
                        provider: "youtube",
                        providerItemId: "bridge-audio"
                    )
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "bridge-audio",
            title: "Bridge Audio",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=bridge-audio")!,
            availableMediaTypes: [.audio]
        )

        let descriptor = try await provider.resolveDownload(for: item, mediaType: .audio)

        #expect(descriptor.remoteURL.absoluteString == "https://bridge.example.com/media/audio.m4a")
        #expect(descriptor.mediaType == .audio)
        #expect(descriptor.mimeType == "audio/mp4")
        #expect(descriptor.suggestedFileExtension == "m4a")
        #expect(descriptor.provider == "youtube")
        #expect(descriptor.providerItemId == "bridge-audio")
    }

    @Test
    func youTubeExtractorBridgeClientRejectsInvalidResponse() async throws {
        let session = makeBridgeTestSession { _ in
            (
                HTTPURLResponse(
                    url: URL(string: "https://bridge.example.com/resolve-download")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"mimeType":"audio/mp4","fileExtension":"m4a"}"#.utf8)
            )
        }
        let client = YouTubeExtractorBridgeClient(
            configuration: TestYouTubeExtractorBridgeConfiguration(
                baseURL: URL(string: "https://bridge.example.com")!
            ),
            session: session
        )

        await #expect(throws: YouTubeExtractorBridgeClient.ClientError.invalidResponse(200)) {
            try await client.resolveDownload(for: makeBridgeTestItem(), mediaType: .audio)
        }
    }

    @Test
    func youTubeExtractorBridgeClientSurfacesTransportFailure() async throws {
        let session = makeBridgeTestSession { _ in
            throw URLError(.cannotConnectToHost)
        }
        let client = YouTubeExtractorBridgeClient(
            configuration: TestYouTubeExtractorBridgeConfiguration(
                baseURL: URL(string: "https://bridge.example.com")!
            ),
            session: session
        )

        await #expect(throws: YouTubeExtractorBridgeClient.ClientError.transportFailure) {
            try await client.resolveDownload(for: makeBridgeTestItem(), mediaType: .audio)
        }
    }

    @Test
    func youTubeExtractorBridgeClientFailsWhenConfigurationIsMissing() async throws {
        let client = YouTubeExtractorBridgeClient(
            configuration: ThrowingYouTubeExtractorBridgeConfiguration(
                error: YouTubeExtractorBridgeConfiguration.ConfigurationError.missingBaseURL
            ),
            session: makeBridgeTestSession { _ in
                (
                    HTTPURLResponse(
                        url: URL(string: "https://bridge.example.com/resolve-download")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
        )

        await #expect(throws: YouTubeExtractorBridgeConfiguration.ConfigurationError.missingBaseURL) {
            try await client.resolveDownload(for: makeBridgeTestItem(), mediaType: .audio)
        }
    }

    @Test
    func youTubeRuntimeDownloadProviderResolvesBestDirectAudioStream() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: TestYouTubePlayerResponseProvider(
                response: YouTubePlayerResponseDTO(
                    streamingData: .init(
                        formats: [],
                        adaptiveFormats: [
                            .init(
                                itag: 140,
                                mimeType: "audio/mp4; codecs=\"mp4a.40.2\"",
                                bitrate: 128000,
                                averageBitrate: 128000,
                                width: nil,
                                height: nil,
                                qualityLabel: nil,
                                audioQuality: "AUDIO_QUALITY_MEDIUM",
                                url: "https://redirector.googlevideo.com/audio-low",
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            ),
                            .init(
                                itag: 141,
                                mimeType: "audio/mp4; codecs=\"mp4a.40.2\"",
                                bitrate: 256000,
                                averageBitrate: 256000,
                                width: nil,
                                height: nil,
                                qualityLabel: nil,
                                audioQuality: "AUDIO_QUALITY_HIGH",
                                url: "https://redirector.googlevideo.com/audio-high",
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            )
                        ]
                    ),
                    playabilityStatus: .init(status: "OK", reason: nil)
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-runtime",
            title: "Audio Runtime",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=audio-runtime")!,
            availableMediaTypes: [.audio]
        )

        let descriptor = try await provider.resolveDownload(for: item, mediaType: .audio)

        #expect(descriptor.mediaType == .audio)
        #expect(descriptor.remoteURL.absoluteString == "https://redirector.googlevideo.com/audio-high")
        #expect(descriptor.mimeType == "audio/mp4")
        #expect(descriptor.suggestedFileExtension == "m4a")
    }

    @Test
    func youTubeRuntimeDownloadProviderResolvesBestProgressiveMP4VideoStream() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: TestYouTubePlayerResponseProvider(
                response: YouTubePlayerResponseDTO(
                    streamingData: .init(
                        formats: [
                            .init(
                                itag: 18,
                                mimeType: "video/mp4; codecs=\"avc1.42001E, mp4a.40.2\"",
                                bitrate: 500000,
                                averageBitrate: nil,
                                width: 640,
                                height: 360,
                                qualityLabel: "360p",
                                audioQuality: nil,
                                url: "https://redirector.googlevideo.com/video-360",
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            ),
                            .init(
                                itag: 22,
                                mimeType: "video/mp4; codecs=\"avc1.64001F, mp4a.40.2\"",
                                bitrate: 2000000,
                                averageBitrate: nil,
                                width: 1280,
                                height: 720,
                                qualityLabel: "720p",
                                audioQuality: nil,
                                url: "https://redirector.googlevideo.com/video-720",
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            )
                        ],
                        adaptiveFormats: []
                    ),
                    playabilityStatus: .init(status: "OK", reason: nil)
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "video-runtime",
            title: "Video Runtime",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=video-runtime")!,
            availableMediaTypes: [.video]
        )

        let descriptor = try await provider.resolveDownload(for: item, mediaType: .video)

        #expect(descriptor.mediaType == .video)
        #expect(descriptor.remoteURL.absoluteString == "https://redirector.googlevideo.com/video-720")
        #expect(descriptor.mimeType == "video/mp4")
        #expect(descriptor.suggestedFileExtension == "mp4")
    }

    @Test
    func youTubeRuntimeDownloadProviderFailsCleanlyForCipherOnlyAudio() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: TestYouTubePlayerResponseProvider(
                response: YouTubePlayerResponseDTO(
                    streamingData: .init(
                        formats: [],
                        adaptiveFormats: [
                            .init(
                                itag: 140,
                                mimeType: "audio/mp4; codecs=\"mp4a.40.2\"",
                                bitrate: 128000,
                                averageBitrate: 128000,
                                width: nil,
                                height: nil,
                                qualityLabel: nil,
                                audioQuality: "AUDIO_QUALITY_MEDIUM",
                                url: nil,
                                signatureCipher: "url=https%3A%2F%2Fredirector.googlevideo.com%2Faudio&sp=sig&s=encrypted",
                                cipher: nil,
                                contentLength: nil
                            )
                        ]
                    ),
                    playabilityStatus: .init(status: "OK", reason: nil)
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "cipher-audio",
            title: "Cipher Audio",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=cipher-audio")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: YouTubeRuntimeDownloadProvider.RuntimeError.unsupportedCipheredStream(.audio)) {
            try await provider.resolveDownload(for: item, mediaType: .audio)
        }
    }

    @Test
    func youTubeRuntimeDownloadProviderRejectsUnsupportedAudioContainer() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: TestYouTubePlayerResponseProvider(
                response: YouTubePlayerResponseDTO(
                    streamingData: .init(
                        formats: [],
                        adaptiveFormats: [
                            .init(
                                itag: 251,
                                mimeType: "audio/webm; codecs=\"opus\"",
                                bitrate: 160000,
                                averageBitrate: 160000,
                                width: nil,
                                height: nil,
                                qualityLabel: nil,
                                audioQuality: "AUDIO_QUALITY_HIGH",
                                url: "https://redirector.googlevideo.com/audio-webm",
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            )
                        ]
                    ),
                    playabilityStatus: .init(status: "OK", reason: nil)
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-webm",
            title: "Audio WebM",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=audio-webm")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: YouTubeRuntimeDownloadProvider.RuntimeError.unsupportedContainer(.audio)) {
            try await provider.resolveDownload(for: item, mediaType: .audio)
        }
    }

    @Test
    func youTubeRuntimeDownloadProviderFailsGracefullyWhenNoDirectAudioStreamExists() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: TestYouTubePlayerResponseProvider(
                response: YouTubePlayerResponseDTO(
                    streamingData: .init(
                        formats: [],
                        adaptiveFormats: [
                            .init(
                                itag: 140,
                                mimeType: "audio/mp4; codecs=\"mp4a.40.2\"",
                                bitrate: 128000,
                                averageBitrate: 128000,
                                width: nil,
                                height: nil,
                                qualityLabel: nil,
                                audioQuality: "AUDIO_QUALITY_MEDIUM",
                                url: nil,
                                signatureCipher: nil,
                                cipher: nil,
                                contentLength: nil
                            )
                        ]
                    ),
                    playabilityStatus: .init(status: "OK", reason: nil)
                )
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-no-direct",
            title: "Audio No Direct",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=audio-no-direct")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: YouTubeRuntimeDownloadProvider.RuntimeError.noSupportedDirectStream(.audio)) {
            try await provider.resolveDownload(for: item, mediaType: .audio)
        }
    }

    @Test
    func youTubeWatchPageClientDecodesJSONParsePlayerResponse() throws {
        let client = YouTubeWatchPageClient()
        let html = #"""
        <html><body><script>
        window['ytInitialPlayerResponse'] = JSON.parse("{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{\"formats\":[],\"adaptiveFormats\":[]}}");
        </script></body></html>
        """#

        let response = try client.decodePlayerResponse(fromHTML: html)

        #expect(response.playabilityStatus?.status == "OK")
        #expect(response.streamingData?.formats.isEmpty == true)
        #expect(response.streamingData?.adaptiveFormats.isEmpty == true)
    }

    @Test
    func youTubeWatchPageClientRejectsMissingPlayerResponse() throws {
        let client = YouTubeWatchPageClient()
        let html = "<html><body><script>console.log('no player response');</script></body></html>"

        #expect(throws: YouTubeWatchPageClient.ClientError.missingPlayerResponse) {
            try client.decodePlayerResponse(fromHTML: html)
        }
    }

    @Test
    func youTubeWatchPageClientRejectsMalformedPlayerResponse() throws {
        let client = YouTubeWatchPageClient()
        let html = #"""
        <html><body><script>
        var ytInitialPlayerResponse = {"playabilityStatus":{"status":"OK"},"streamingData":{"formats":"oops","adaptiveFormats":[]}};
        </script></body></html>
        """#

        #expect(throws: YouTubeWatchPageClient.ClientError.decodingFailure) {
            try client.decodePlayerResponse(fromHTML: html)
        }
    }

    @Test
    func youTubeRuntimeDownloadProviderPropagatesWatchPageFailures() async throws {
        let provider = YouTubeRuntimeDownloadProvider(
            playerResponseProvider: ThrowingYouTubePlayerResponseProvider(
                error: YouTubeWatchPageClient.ClientError.missingPlayerResponse
            )
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "missing-player-response",
            title: "Missing Player Response",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://www.youtube.com/watch?v=missing-player-response")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: YouTubeWatchPageClient.ClientError.missingPlayerResponse) {
            try await provider.resolveDownload(for: item, mediaType: .audio)
        }
    }

    @Test
    @MainActor
    func audioDownloadUsesAudioPathAndPersistsDownloadedAudioItem() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .audio: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/audio")!,
                    mediaType: .audio,
                    suggestedFileExtension: "mp3",
                    mimeType: "audio/mpeg",
                    provider: "youtube",
                    providerItemId: "audio-success"
                )
            ]
        )
        let downloader = TestMediaFileDownloader(sampleAudioURL: sampleAudioURL())
        let fileStorage = TestLocalFileStorage()
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: downloader,
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: fileStorage
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-success",
            title: "Audio Success",
            creatorName: "Creator",
            thumbnailURL: nil,
            durationSeconds: 180,
            sourcePageURL: URL(string: "https://example.com/watch?v=audio-success")!,
            availableMediaTypes: [.audio, .video]
        )

        try await orchestrator.startDownload(for: item, mediaType: .audio)

        #expect(provider.requestedMediaTypes == [.audio])
        #expect(downloader.requestedMediaTypes == [.audio])
        #expect(downloader.requestedFileExtensions == ["mp3"])

        let savedItem = try #require(
            try repository.fetchItem(
                providerName: item.provider,
                providerItemID: item.providerItemId,
                mediaType: .audio
            )
        )
        #expect(savedItem.mediaType == .audio)
        #expect(savedItem.downloadStatus == .downloaded)
        #expect(savedItem.downloadProgress == 1.0)
        #expect(savedItem.downloadedDate != nil)
        #expect(savedItem.localFilePath == "\(savedItem.id.uuidString)/audio.mp3")
        #expect(repository.recordedStatuses == [.queued, .downloading, .downloading, .downloaded])
    }

    @Test
    @MainActor
    func unplayableDownloadedAudioFailsBeforeDownloadedStateIsPersisted() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .audio: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/audio-invalid")!,
                    mediaType: .audio,
                    suggestedFileExtension: "m4a",
                    mimeType: "audio/mp4",
                    provider: "youtube",
                    providerItemId: "audio-invalid"
                )
            ]
        )
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: TestMediaFileDownloader(),
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: TestLocalFileStorage()
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-invalid",
            title: "Audio Invalid",
            creatorName: "Creator",
            thumbnailURL: nil,
            durationSeconds: 180,
            sourcePageURL: URL(string: "https://example.com/watch?v=audio-invalid")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: DownloadOrchestratorError.downloadFailed) {
            try await orchestrator.startDownload(for: item, mediaType: .audio)
        }

        let savedItem = try #require(
            try repository.fetchItem(
                providerName: item.provider,
                providerItemID: item.providerItemId,
                mediaType: .audio
            )
        )
        #expect(savedItem.downloadStatus == .failed)
        #expect(savedItem.localFilePath == nil)
        #expect(savedItem.downloadedDate == nil)
    }

    @Test
    @MainActor
    func audioDownloadResolutionFailureMarksItemFailed() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(descriptorsByMediaType: [:], errorByMediaType: [.audio: ProviderError.downloadResolutionFailed])
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: TestMediaFileDownloader(),
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: TestLocalFileStorage()
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-failure",
            title: "Audio Failure",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://example.com/watch?v=audio-failure")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: ProviderError.downloadResolutionFailed) {
            try await orchestrator.startDownload(for: item, mediaType: .audio)
        }

        let savedItem = try #require(
            try repository.fetchItem(
                providerName: item.provider,
                providerItemID: item.providerItemId,
                mediaType: .audio
            )
        )
        #expect(savedItem.mediaType == .audio)
        #expect(savedItem.downloadStatus == .failed)
        #expect(savedItem.localFilePath == nil)
        #expect(savedItem.downloadedDate == nil)
    }

    @Test
    @MainActor
    func missingDownloadedFileDowngradesStateToFailed() async throws {
        let repository = TestMediaLibraryRepository()
        let mediaItem = MediaItem(
            providerName: "youtube",
            providerItemID: "missing-file",
            title: "Missing File",
            creatorName: nil,
            mediaType: .audio,
            downloadStatus: .downloaded,
            downloadProgress: 1,
            localFilePath: "/tmp/does-not-exist/audio.m4a",
            thumbnailLocalPath: nil,
            createdDate: .now,
            downloadedDate: .now
        )
        try repository.save(mediaItem)

        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: TestDownloadProvider(descriptorsByMediaType: [:]),
            downloader: TestMediaFileDownloader(),
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: TestLocalFileStorage()
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "missing-file",
            title: "Missing File",
            creatorName: nil,
            thumbnailURL: nil,
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://example.com/watch?v=missing-file")!,
            availableMediaTypes: [.audio]
        )

        let snapshot = try await orchestrator.currentState(for: item, mediaType: .audio)

        #expect(snapshot?.status == .failed)
        #expect(snapshot?.localFilePath == nil)
        #expect(mediaItem.downloadStatus == .failed)
        #expect(mediaItem.localFilePath == nil)
        #expect(mediaItem.downloadedDate == nil)
    }

    @Test
    @MainActor
    func videoDownloadUsesVideoPathAndCachesThumbnail() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .video: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/video")!,
                    mediaType: .video,
                    suggestedFileExtension: "mp4",
                    mimeType: "video/mp4",
                    provider: "youtube",
                    providerItemId: "video-success"
                )
            ]
        )
        let downloader = TestMediaFileDownloader(sampleVideoURL: sampleVideoURL())
        let thumbnailDataFetcher = TestThumbnailDataFetcher(result: .success(Data("thumbnail".utf8)))
        let fileStorage = TestLocalFileStorage()
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: downloader,
            thumbnailDataFetcher: thumbnailDataFetcher,
            fileStorage: fileStorage
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "video-success",
            title: "Video Success",
            creatorName: "Creator",
            thumbnailURL: URL(string: "https://example.com/thumbnail.jpg"),
            durationSeconds: 200,
            sourcePageURL: URL(string: "https://example.com/watch?v=video-success")!,
            availableMediaTypes: [.audio, .video]
        )

        try await orchestrator.startDownload(for: item, mediaType: .video)

        #expect(provider.requestedMediaTypes == [.video])
        #expect(downloader.requestedMediaTypes == [.video])
        #expect(downloader.requestedFileExtensions == ["mp4"])
        #expect(thumbnailDataFetcher.requestedURLs == [URL(string: "https://example.com/thumbnail.jpg")!])

        let savedItem = try #require(
            try repository.fetchItem(
                providerName: item.provider,
                providerItemID: item.providerItemId,
                mediaType: .video
            )
        )
        #expect(savedItem.mediaType == .video)
        #expect(savedItem.downloadStatus == .downloaded)
        #expect(savedItem.localFilePath == "\(savedItem.id.uuidString)/video.mp4")
        #expect(savedItem.thumbnailLocalPath == "\(savedItem.id.uuidString)/thumbnail.jpg")
        #expect(savedItem.thumbnailRemoteURLString == "https://example.com/thumbnail.jpg")
        #expect(savedItem.downloadedDate != nil)
    }

    @Test
    @MainActor
    func videoDownloadSurvivesThumbnailCacheFailure() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .video: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/video")!,
                    mediaType: .video,
                    suggestedFileExtension: "mp4",
                    mimeType: "video/mp4",
                    provider: "youtube",
                    providerItemId: "video-thumbnail-failure"
                )
            ]
        )
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: TestMediaFileDownloader(sampleVideoURL: sampleVideoURL()),
            thumbnailDataFetcher: TestThumbnailDataFetcher(result: .failure(ThumbnailDataFetcherError.transportFailed)),
            fileStorage: TestLocalFileStorage()
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "video-thumbnail-failure",
            title: "Video Thumbnail Failure",
            creatorName: nil,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg"),
            durationSeconds: nil,
            sourcePageURL: URL(string: "https://example.com/watch?v=video-thumbnail-failure")!,
            availableMediaTypes: [.video]
        )

        try await orchestrator.startDownload(for: item, mediaType: .video)

        let savedItem = try #require(
            try repository.fetchItem(
                providerName: item.provider,
                providerItemID: item.providerItemId,
                mediaType: .video
            )
        )
        #expect(savedItem.downloadStatus == .downloaded)
        #expect(savedItem.localFilePath == "\(savedItem.id.uuidString)/video.mp4")
        #expect(savedItem.thumbnailLocalPath == nil)
    }

    @Test
    @MainActor
    func launchReconciliationMarksMissingDownloadedMediaFailed() throws {
        let repository = TestMediaLibraryRepository()
        let fileStorage = TestLocalFileStorage()
        let item = MediaItem(
            providerName: "youtube",
            providerItemID: "reconcile-missing-audio",
            title: "Missing Audio",
            creatorName: nil,
            mediaType: .audio,
            downloadStatus: .downloaded,
            downloadProgress: 1,
            localFilePath: "missing-id/audio.m4a",
            thumbnailLocalPath: nil,
            createdDate: .now,
            downloadedDate: .now
        )
        try repository.save(item)

        let reconciler = LaunchMediaReconciler(repository: repository, fileStorage: fileStorage)

        try reconciler.reconcileDownloadedItems()

        #expect(item.downloadStatus == .failed)
        #expect(item.localFilePath == nil)
        #expect(item.downloadedDate == nil)
    }

    @Test
    @MainActor
    func launchReconciliationClearsMissingVideoThumbnailWithoutFailingVideo() throws {
        let repository = TestMediaLibraryRepository()
        let fileStorage = TestLocalFileStorage()
        let itemID = UUID()
        let storedVideoURL = try fileStorage.mediaFileURL(for: itemID, kind: .video, fileExtension: "mp4")
        try FileManager.default.createDirectory(at: storedVideoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("playable-video-placeholder".utf8).write(to: storedVideoURL, options: .atomic)

        let item = MediaItem(
            id: itemID,
            providerName: "youtube",
            providerItemID: "reconcile-video-thumbnail",
            title: "Video With Missing Thumbnail",
            creatorName: nil,
            mediaType: .video,
            downloadStatus: .downloaded,
            downloadProgress: 1,
            localFilePath: try fileStorage.persistedPath(forManagedFileAt: storedVideoURL),
            thumbnailLocalPath: "\(itemID.uuidString)/thumbnail.jpg",
            createdDate: .now,
            downloadedDate: .now
        )
        try repository.save(item)

        let reconciler = LaunchMediaReconciler(repository: repository, fileStorage: fileStorage)

        try reconciler.reconcileDownloadedItems()

        #expect(item.downloadStatus == .downloaded)
        #expect(item.localFilePath == "\(itemID.uuidString)/video.mp4")
        #expect(item.thumbnailLocalPath == nil)
        #expect(item.downloadedDate != nil)
    }

    @Test
    func applicationSupportFileStorageGeneratesStableManagedPaths() throws {
        let fileStorage = ApplicationSupportFileStorage()
        let itemID = UUID()

        let audioURL = try fileStorage.mediaFileURL(for: itemID, kind: .audio, fileExtension: "m4a")
        let videoURL = try fileStorage.mediaFileURL(for: itemID, kind: .video, fileExtension: "mp4")
        let thumbnailURL = try fileStorage.thumbnailURL(for: itemID)

        #expect(audioURL.lastPathComponent == "audio.m4a")
        #expect(videoURL.lastPathComponent == "video.mp4")
        #expect(thumbnailURL.lastPathComponent == "thumbnail.jpg")
        #expect(audioURL.path.contains("Application Support"))
        #expect(audioURL.path.contains("LocalMediaStorage/items/\(itemID.uuidString)"))
        #expect(try fileStorage.persistedPath(forManagedFileAt: audioURL) == "\(itemID.uuidString)/audio.m4a")
        #expect(try fileStorage.persistedPath(forManagedFileAt: videoURL) == "\(itemID.uuidString)/video.mp4")
        #expect(try fileStorage.persistedPath(forManagedFileAt: thumbnailURL) == "\(itemID.uuidString)/thumbnail.jpg")
    }

    @Test
    func applicationSupportFileStorageResolvesRelativeAndLegacyManagedAbsolutePaths() throws {
        let fileStorage = ApplicationSupportFileStorage()
        let itemID = UUID()
        let storedURL = try fileStorage.mediaFileURL(for: itemID, kind: .audio, fileExtension: "m4a")
        try fileStorage.createItemDirectory(for: itemID)
        try Data("playable-audio-placeholder".utf8).write(to: storedURL, options: .atomic)

        let relativePath = try fileStorage.persistedPath(forManagedFileAt: storedURL)
        let legacyAbsolutePath = "/var/mobile/Containers/Data/Application/LEGACY/Library/Application Support/LocalMediaStorage/items/\(relativePath)"

        #expect(try fileStorage.resolveManagedFileURL(from: relativePath) == storedURL)
        #expect(try fileStorage.resolveManagedFileURL(from: legacyAbsolutePath) == storedURL)
        #expect(try fileStorage.resolveExistingManagedFileURL(from: relativePath) == storedURL)
        #expect(try fileStorage.normalizedManagedPathIfAvailable(legacyAbsolutePath) == relativePath)
    }

    @Test
    func applicationSupportFileStorageRejectsUnmanagedAbsolutePaths() throws {
        let fileStorage = ApplicationSupportFileStorage()

        do {
            _ = try fileStorage.resolveManagedFileURL(from: "/tmp/audio.m4a")
            Issue.record("Expected unmanaged absolute path resolution to fail.")
        } catch let error as FileStorageError {
            switch error {
            case .invalidManagedRelativePath:
                break
            default:
                Issue.record("Unexpected file storage error: \(error.localizedDescription)")
            }
        }
    }

    @Test
    @MainActor
    func swiftDataRepositorySavesFetchesAndSortsMediaItems() throws {
        let repository = try makeSwiftDataRepository()

        let olderItem = MediaItem(
            providerName: "youtube",
            providerItemID: "older",
            title: "Older",
            creatorName: "Creator A",
            mediaType: .audio,
            downloadStatus: .failed,
            downloadProgress: nil,
            localFilePath: nil,
            thumbnailRemoteURLString: nil,
            thumbnailLocalPath: nil,
            createdDate: Date(timeIntervalSince1970: 100),
            downloadedDate: nil
        )
        repository.insertForTesting(olderItem)

        let newerItem = MediaItem(
            providerName: "youtube",
            providerItemID: "newer",
            title: "Newer",
            creatorName: "Creator B",
            mediaType: .video,
            downloadStatus: .downloaded,
            downloadProgress: 1,
            localFilePath: "newer/video.mp4",
            thumbnailRemoteURLString: "https://example.com/thumb.jpg",
            thumbnailLocalPath: "newer/thumbnail.jpg",
            createdDate: Date(timeIntervalSince1970: 200),
            downloadedDate: Date(timeIntervalSince1970: 250)
        )
        repository.insertForTesting(newerItem)

        let fetchedItem = try #require(
            try repository.fetchItem(providerName: "youtube", providerItemID: "newer", mediaType: .video)
        )
        let fetchedItems = try repository.fetchItems()

        #expect(fetchedItem.title == "Newer")
        #expect(fetchedItem.creatorName == "Creator B")
        #expect(fetchedItem.mediaType == .video)
        #expect(fetchedItem.downloadStatus == .downloaded)
        #expect(fetchedItem.localFilePath == "newer/video.mp4")
        #expect(fetchedItems.map(\.providerItemID) == ["newer", "older"])
    }

    @Test
    @MainActor
    func fileStorageMoveFailureDoesNotLeaveDownloadedSuccessState() async throws {
        let repository = TestMediaLibraryRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .audio: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/audio")!,
                    mediaType: .audio,
                    suggestedFileExtension: "m4a",
                    mimeType: "audio/mp4",
                    provider: "youtube",
                    providerItemId: "audio-storage-failure"
                )
            ]
        )
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: TestMediaFileDownloader(sampleAudioURL: sampleAudioURL()),
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: FailingLocalFileStorage()
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-storage-failure",
            title: "Audio Storage Failure",
            creatorName: "Creator",
            thumbnailURL: nil,
            durationSeconds: 180,
            sourcePageURL: URL(string: "https://example.com/watch?v=audio-storage-failure")!,
            availableMediaTypes: [.audio]
        )

        await #expect(throws: DownloadOrchestratorError.fileStorageFailed) {
            try await orchestrator.startDownload(for: item, mediaType: .audio)
        }

        let savedItem = try #require(
            try repository.fetchItem(providerName: item.provider, providerItemID: item.providerItemId, mediaType: .audio)
        )
        #expect(savedItem.downloadStatus == .failed)
        #expect(savedItem.localFilePath == nil)
        #expect(savedItem.downloadedDate == nil)
    }

    @Test
    @MainActor
    func integrationAudioDownloadFlowPersistsThroughSwiftDataRepository() async throws {
        let repository = try makeSwiftDataRepository()
        let provider = TestDownloadProvider(
            descriptorsByMediaType: [
                .audio: DownloadDescriptor(
                    remoteURL: URL(string: "https://example.com/audio-integration")!,
                    mediaType: .audio,
                    suggestedFileExtension: "m4a",
                    mimeType: "audio/mp4",
                    provider: "youtube",
                    providerItemId: "audio-integration"
                )
            ]
        )
        let fileStorage = TestLocalFileStorage()
        let orchestrator = DownloadOrchestrator(
            repository: repository,
            downloadProvider: provider,
            downloader: TestMediaFileDownloader(sampleAudioURL: sampleAudioURL()),
            thumbnailDataFetcher: TestThumbnailDataFetcher(),
            fileStorage: fileStorage
        )
        let item = ResolvedMediaItem(
            provider: "youtube",
            providerItemId: "audio-integration",
            title: "Integration Audio",
            creatorName: "Integration Creator",
            thumbnailURL: nil,
            durationSeconds: 90,
            sourcePageURL: URL(string: "https://example.com/watch?v=audio-integration")!,
            availableMediaTypes: [.audio]
        )

        try await orchestrator.startDownload(for: item, mediaType: .audio)

        let savedItem = try #require(
            try repository.fetchItem(providerName: item.provider, providerItemID: item.providerItemId, mediaType: .audio)
        )
        let storedURL = try fileStorage.resolveManagedFileURL(from: try #require(savedItem.localFilePath))

        #expect(savedItem.downloadStatus == .downloaded)
        #expect(savedItem.mediaType == .audio)
        #expect(savedItem.downloadedDate != nil)
        #expect(fileStorage.fileExists(at: storedURL))
    }
}

@MainActor
private final class TestMediaLibraryRepository: MediaLibraryRepository {
    private var itemsByKey: [String: MediaItem] = [:]
    private(set) var recordedStatuses: [DownloadStatus] = []

    func fetchItems() throws -> [MediaItem] {
        itemsByKey.values.sorted { $0.createdDate > $1.createdDate }
    }

    func fetchItem(providerName: String, providerItemID: String, mediaType: MediaType) throws -> MediaItem? {
        itemsByKey[key(providerName: providerName, providerItemID: providerItemID, mediaType: mediaType)]
    }

    func upsertItem(from resolvedItem: ResolvedMediaItem, mediaType: MediaType) throws -> MediaItem {
        let itemKey = key(
            providerName: resolvedItem.provider,
            providerItemID: resolvedItem.providerItemId,
            mediaType: mediaType
        )

        if let existingItem = itemsByKey[itemKey] {
            existingItem.title = resolvedItem.title
            existingItem.creatorName = resolvedItem.creatorName
            existingItem.setMediaType(mediaType)
            return existingItem
        }

        let newItem = MediaItem(
            providerName: resolvedItem.provider,
            providerItemID: resolvedItem.providerItemId,
            title: resolvedItem.title,
            creatorName: resolvedItem.creatorName,
            mediaType: mediaType,
            downloadStatus: .notDownloaded,
            downloadProgress: nil,
            localFilePath: nil,
            thumbnailRemoteURLString: resolvedItem.thumbnailURL?.absoluteString,
            thumbnailLocalPath: nil,
            createdDate: .now,
            downloadedDate: nil
        )
        itemsByKey[itemKey] = newItem
        return newItem
    }

    func updateDownloadState(
        for item: MediaItem,
        status: DownloadStatus,
        progress: Double?,
        localFilePath: String?,
        downloadedDate: Date?
    ) throws {
        recordedStatuses.append(status)
        item.downloadStatus = status
        item.downloadProgress = progress
        item.localFilePath = localFilePath
        item.downloadedDate = downloadedDate
        item.syncMediaTypeRawValueIfNeeded()
        itemsByKey[key(providerName: item.providerName, providerItemID: item.providerItemID, mediaType: item.mediaType)] = item
    }

    func save(_ item: MediaItem) throws {
        item.syncMediaTypeRawValueIfNeeded()
        itemsByKey[key(providerName: item.providerName, providerItemID: item.providerItemID, mediaType: item.mediaType)] = item
    }

    func deleteAll() throws {
        itemsByKey.removeAll()
    }

    private func key(providerName: String, providerItemID: String, mediaType: MediaType) -> String {
        "\(providerName)|\(providerItemID)|\(mediaType.rawValue)"
    }
}

@MainActor
private struct TestSwiftDataRepositoryFactory: MediaLibraryRepository {
    let container: ModelContainer
    let repository: SwiftDataMediaLibraryRepository

    func fetchItems() throws -> [MediaItem] {
        try repository.fetchItems()
    }

    func fetchItem(providerName: String, providerItemID: String, mediaType: MediaType) throws -> MediaItem? {
        try repository.fetchItem(providerName: providerName, providerItemID: providerItemID, mediaType: mediaType)
    }

    func upsertItem(from resolvedItem: ResolvedMediaItem, mediaType: MediaType) throws -> MediaItem {
        try repository.upsertItem(from: resolvedItem, mediaType: mediaType)
    }

    func updateDownloadState(
        for item: MediaItem,
        status: DownloadStatus,
        progress: Double?,
        localFilePath: String?,
        downloadedDate: Date?
    ) throws {
        try repository.updateDownloadState(
            for: item,
            status: status,
            progress: progress,
            localFilePath: localFilePath,
            downloadedDate: downloadedDate
        )
    }

    func save(_ item: MediaItem) throws {
        try repository.save(item)
    }

    func deleteAll() throws {
        try repository.deleteAll()
    }
}

@MainActor
private func makeSwiftDataRepository() throws -> TestSwiftDataRepositoryFactory {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: MediaItem.self, configurations: configuration)
    let repository = SwiftDataMediaLibraryRepository(modelContext: ModelContext(container))
    return TestSwiftDataRepositoryFactory(container: container, repository: repository)
}

private extension TestSwiftDataRepositoryFactory {
    func insertForTesting(_ item: MediaItem) {
        container.mainContext.insert(item)
        try? container.mainContext.save()
    }
}

private final class TestDownloadProvider: DownloadProvider {
    let descriptorsByMediaType: [MediaType: DownloadDescriptor]
    let errorByMediaType: [MediaType: ProviderError]
    private(set) var requestedMediaTypes: [MediaType] = []

    init(
        descriptorsByMediaType: [MediaType: DownloadDescriptor],
        errorByMediaType: [MediaType: ProviderError] = [:]
    ) {
        self.descriptorsByMediaType = descriptorsByMediaType
        self.errorByMediaType = errorByMediaType
    }

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        _ = item
        requestedMediaTypes.append(mediaType)

        if let error = errorByMediaType[mediaType] {
            throw error
        }

        guard let descriptor = descriptorsByMediaType[mediaType] else {
            throw ProviderError.downloadResolutionFailed
        }

        return descriptor
    }
}

private final class TestMediaFileDownloader: MediaFileDownloading {
    private(set) var requestedMediaTypes: [MediaType] = []
    private(set) var requestedFileExtensions: [String?] = []
    private let sampleAudioURL: URL?
    private let sampleVideoURL: URL?

    init(sampleAudioURL: URL? = nil, sampleVideoURL: URL? = nil) {
        self.sampleAudioURL = sampleAudioURL
        self.sampleVideoURL = sampleVideoURL
    }

    func download(
        from remoteURL: URL,
        mediaType: MediaType,
        suggestedFileExtension: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        _ = remoteURL
        requestedMediaTypes.append(mediaType)
        requestedFileExtensions.append(suggestedFileExtension)
        onProgress?(0.5)

        let fileExtension = suggestedFileExtension ?? "bin"
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if mediaType == .audio, let sampleAudioURL {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: sampleAudioURL, to: temporaryURL)
        } else if mediaType == .video, let sampleVideoURL {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: sampleVideoURL, to: temporaryURL)
        } else {
            try Data("test-payload".utf8).write(to: temporaryURL, options: .atomic)
        }

        onProgress?(1.0)
        return temporaryURL
    }
}

private final class TestThumbnailDataFetcher: ThumbnailDataFetching {
    private let result: Result<Data, Error>
    private(set) var requestedURLs: [URL] = []

    init(result: Result<Data, Error> = .success(Data("default-thumbnail".utf8))) {
        self.result = result
    }

    func fetchThumbnailData(from remoteURL: URL) async throws -> Data {
        requestedURLs.append(remoteURL)
        return try result.get()
    }
}

private struct TestYouTubePlayerResponseProvider: YouTubePlayerResponseProviding {
    let response: YouTubePlayerResponseDTO

    func fetchPlayerResponse(forVideoID videoID: String) async throws -> YouTubePlayerResponseDTO {
        _ = videoID
        return response
    }
}

private struct ThrowingYouTubePlayerResponseProvider: YouTubePlayerResponseProviding {
    let error: Error

    func fetchPlayerResponse(forVideoID videoID: String) async throws -> YouTubePlayerResponseDTO {
        _ = videoID
        throw error
    }
}

private struct TestYouTubeExtractorBridgeClient: YouTubeExtractorBridgeResolving {
    let result: Result<BridgeResolvedDownload, Error>

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> BridgeResolvedDownload {
        _ = item
        _ = mediaType
        return try result.get()
    }
}

private struct TestYouTubeExtractorBridgeConfiguration: YouTubeExtractorBridgeConfiguring {
    let baseURL: URL

    func bridgeBaseURL() throws -> URL {
        baseURL
    }
}

private struct ThrowingYouTubeExtractorBridgeConfiguration: YouTubeExtractorBridgeConfiguring {
    let error: Error

    func bridgeBaseURL() throws -> URL {
        throw error
    }
}

private func makeBridgeTestItem() -> ResolvedMediaItem {
    ResolvedMediaItem(
        provider: "youtube",
        providerItemId: "bridge-item",
        title: "Bridge Item",
        creatorName: nil,
        thumbnailURL: nil,
        durationSeconds: nil,
        sourcePageURL: URL(string: "https://www.youtube.com/watch?v=bridge-item")!,
        availableMediaTypes: [.audio, .video]
    )
}

private func makeBridgeTestSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    BridgeURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BridgeURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class BridgeURLProtocol: URLProtocol {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestLocalFileStorage: LocalFileStorage {
    private let fileManager = FileManager.default
    private let rootURL: URL

    init() {
        self.rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("IOSMusicAppTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func createBaseDirectories() throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    func createItemDirectory(for itemID: UUID) throws -> URL {
        let directoryURL = rootURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func mediaFileURL(for itemID: UUID, kind: StoredMediaKind, fileExtension: String) throws -> URL {
        try createItemDirectory(for: itemID)
            .appendingPathComponent(kind.fileNameStem, isDirectory: false)
            .appendingPathExtension(fileExtension)
    }

    func thumbnailURL(for itemID: UUID) throws -> URL {
        try createItemDirectory(for: itemID)
            .appendingPathComponent("thumbnail.jpg", isDirectory: false)
    }

    func persistedPath(forManagedFileAt url: URL) throws -> String {
        let standardizedRoot = rootURL.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path
        guard standardizedURL.hasPrefix(standardizedRoot + "/") else {
            throw FileStorageError.invalidManagedRelativePath(url.path)
        }

        return String(standardizedURL.dropFirst(standardizedRoot.count + 1))
    }

    func resolveManagedFileURL(from persistedPath: String) throws -> URL {
        let trimmedPath = persistedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw FileStorageError.invalidManagedRelativePath(persistedPath)
        }

        if trimmedPath.hasPrefix("/") {
            return URL(fileURLWithPath: trimmedPath)
        }

        return rootURL.appendingPathComponent(trimmedPath, isDirectory: false)
    }

    func moveTemporaryDownloadedFile(
        at temporaryURL: URL,
        for itemID: UUID,
        kind: StoredMediaKind,
        fileExtension: String
    ) throws -> URL {
        let destinationURL = try mediaFileURL(for: itemID, kind: kind, fileExtension: fileExtension)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    func writeThumbnailData(_ data: Data, for itemID: UUID) throws -> URL {
        let destinationURL = try thumbnailURL(for: itemID)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func ensureManagedFileExists(at url: URL) throws {
        if !fileExists(at: url) {
            throw FileStorageError.missingManagedFile(url)
        }
    }

    func deleteStoredFiles(for itemID: UUID) throws {
        let directoryURL = rootURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        try fileManager.removeItem(at: directoryURL)
    }
}

private struct FailingLocalFileStorage: LocalFileStorage {
    func createBaseDirectories() throws -> URL { FileManager.default.temporaryDirectory }
    func createItemDirectory(for itemID: UUID) throws -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true) }
    func mediaFileURL(for itemID: UUID, kind: StoredMediaKind, fileExtension: String) throws -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(itemID.uuidString).appendingPathComponent("\(kind.fileNameStem).\(fileExtension)") }
    func thumbnailURL(for itemID: UUID) throws -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(itemID.uuidString).appendingPathComponent("thumbnail.jpg") }
    func persistedPath(forManagedFileAt url: URL) throws -> String { url.lastPathComponent }
    func resolveManagedFileURL(from persistedPath: String) throws -> URL { URL(fileURLWithPath: persistedPath) }
    func moveTemporaryDownloadedFile(at temporaryURL: URL, for itemID: UUID, kind: StoredMediaKind, fileExtension: String) throws -> URL { throw FileStorageError.fileMoveFailed(source: temporaryURL, destination: temporaryURL, underlying: NSError(domain: "FailingLocalFileStorage", code: 1)) }
    func writeThumbnailData(_ data: Data, for itemID: UUID) throws -> URL { throw FileStorageError.fileWriteFailed(URL(fileURLWithPath: "/tmp/thumbnail.jpg"), underlying: NSError(domain: "FailingLocalFileStorage", code: 2)) }
    func fileExists(at url: URL) -> Bool { false }
    func ensureManagedFileExists(at url: URL) throws {}
    func deleteStoredFiles(for itemID: UUID) throws {}
}

private func sampleAudioURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("SampleAudio.m4a", isDirectory: false)
}

private func sampleVideoURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("SampleVideo.mp4", isDirectory: false)
}
