import Foundation
import OSLog

struct YouTubeRuntimeDownloadProvider: DownloadProvider {
    enum RuntimeError: Equatable, LocalizedError {
        case unavailablePlayback(String?)
        case unsupportedCipheredStream(MediaType)
        case unsupportedContainer(MediaType)
        case noSupportedDirectStream(MediaType)

        var errorDescription: String? {
            switch self {
            case .unavailablePlayback(let reason):
                return reason ?? "This YouTube item is not available for playback right now."
            case .unsupportedCipheredStream(let mediaType):
                return "YouTube returned a protected \(mediaType.rawValue) stream that this build cannot resolve yet."
            case .unsupportedContainer(let mediaType):
                return "YouTube returned only unsupported \(mediaType.rawValue) container formats for this item."
            case .noSupportedDirectStream(let mediaType):
                return "No supported downloadable \(mediaType.rawValue) stream was available for this YouTube item."
            }
        }
    }

    private let playerResponseProvider: any YouTubePlayerResponseProviding
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeRuntimeDownloadProvider")

    init(playerResponseProvider: any YouTubePlayerResponseProviding = YouTubeWatchPageClient()) {
        self.playerResponseProvider = playerResponseProvider
    }

    func resolveDownload(for item: ResolvedMediaItem, mediaType: MediaType) async throws -> DownloadDescriptor {
        guard item.provider == YouTubeURLResolutionProvider.providerName else {
            throw ProviderError.mappingFailed
        }

        guard item.availableMediaTypes.contains(mediaType), mediaType != .unknown else {
            throw ProviderError.unsupportedMediaType
        }

        let playerResponse: YouTubePlayerResponseDTO
        do {
            playerResponse = try await playerResponseProvider.fetchPlayerResponse(forVideoID: item.providerItemId)
        } catch let error as YouTubeWatchPageClient.ClientError {
            logger.error(
                "Failed to fetch player response for \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        } catch {
            logger.error(
                "Unexpected player response failure for \(item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw error
        }

        if let status = playerResponse.playabilityStatus?.status?.uppercased(),
           status != "OK" {
            logger.error(
                "Player response unavailable for \(item.providerItemId, privacy: .public) with status \(status, privacy: .public)"
            )
            throw RuntimeError.unavailablePlayback(playerResponse.playabilityStatus?.reason)
        }

        let resolvedStream: ResolvedStream
        do {
            resolvedStream = try selectStream(from: playerResponse, mediaType: mediaType)
        } catch let error as RuntimeError {
            logRuntimeError(error, itemID: item.providerItemId, mediaType: mediaType)
            throw error
        }

        logger.debug(
            "Resolved direct \(mediaType.rawValue, privacy: .public) stream for \(item.providerItemId, privacy: .public) using MIME type \(resolvedStream.mimeType, privacy: .public)"
        )

        return DownloadDescriptor(
            remoteURL: resolvedStream.url,
            mediaType: mediaType,
            suggestedFileExtension: ManagedMediaFileFormat.resolve(
                mediaType: mediaType,
                suggestedFileExtension: nil,
                mimeType: resolvedStream.mimeType
            ).fileExtension,
            mimeType: resolvedStream.mimeType,
            provider: item.provider,
            providerItemId: item.providerItemId
        )
    }

    private func selectStream(
        from playerResponse: YouTubePlayerResponseDTO,
        mediaType: MediaType
    ) throws -> ResolvedStream {
        let streamingData = playerResponse.streamingData ?? .init()

        switch mediaType {
        case .audio:
            return try selectAudioStream(from: streamingData.adaptiveFormats)
        case .video:
            return try selectVideoStream(from: streamingData.formats)
        case .unknown:
            throw ProviderError.unsupportedMediaType
        }
    }

    private func selectAudioStream(from formats: [YouTubePlayerResponseDTO.Format]) throws -> ResolvedStream {
        let audioFormats = formats.filter { isCandidate($0, for: .audio) }
        let supportedCandidates = formats.compactMap { format -> ResolvedStream? in
            guard let mimeType = normalizedMimeType(from: format.mimeType),
                  mimeType == ManagedMediaFileFormat.m4a.mimeType || mimeType == ManagedMediaFileFormat.mp3.mimeType,
                  let url = resolvedURL(for: format) else {
                return nil
            }

            let bitrate = format.averageBitrate ?? format.bitrate ?? 0
            return ResolvedStream(url: url, mimeType: mimeType, score: bitrate)
        }

        if let bestCandidate = supportedCandidates.max(by: { $0.score < $1.score }) {
            return bestCandidate
        }

        if containsUnsupportedCipheredCandidate(in: formats, mediaType: .audio) {
            throw RuntimeError.unsupportedCipheredStream(.audio)
        }

        if containsUnsupportedDirectContainer(in: audioFormats, mediaType: .audio) {
            throw RuntimeError.unsupportedContainer(.audio)
        }

        throw RuntimeError.noSupportedDirectStream(.audio)
    }

    private func selectVideoStream(from formats: [YouTubePlayerResponseDTO.Format]) throws -> ResolvedStream {
        let videoFormats = formats.filter { isCandidate($0, for: .video) }
        let supportedCandidates = formats.compactMap { format -> ResolvedStream? in
            guard let mimeType = normalizedMimeType(from: format.mimeType),
                  mimeType == ManagedMediaFileFormat.mp4.mimeType,
                  let url = resolvedURL(for: format) else {
                return nil
            }

            let score = (format.height ?? 0) * 10_000 + (format.bitrate ?? 0)
            return ResolvedStream(url: url, mimeType: mimeType, score: score)
        }

        if let bestCandidate = supportedCandidates.max(by: { $0.score < $1.score }) {
            return bestCandidate
        }

        if containsUnsupportedCipheredCandidate(in: formats, mediaType: .video) {
            throw RuntimeError.unsupportedCipheredStream(.video)
        }

        if containsUnsupportedDirectContainer(in: videoFormats, mediaType: .video) {
            throw RuntimeError.unsupportedContainer(.video)
        }

        throw RuntimeError.noSupportedDirectStream(.video)
    }

    private func normalizedMimeType(from rawMimeType: String?) -> String? {
        guard let rawMimeType else {
            return nil
        }

        let trimmedMimeType = rawMimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMimeType.isEmpty else {
            return nil
        }

        return trimmedMimeType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func containsUnsupportedCipheredCandidate(
        in formats: [YouTubePlayerResponseDTO.Format],
        mediaType: MediaType
    ) -> Bool {
        formats.contains { format in
            guard isCandidate(format, for: mediaType) else {
                return false
            }
            return resolvedURL(for: format) == nil && hasUnsupportedCipher(format)
        }
    }

    private func containsUnsupportedDirectContainer(
        in formats: [YouTubePlayerResponseDTO.Format],
        mediaType: MediaType
    ) -> Bool {
        formats.contains { format in
            guard resolvedURL(for: format) != nil,
                  let mimeType = normalizedMimeType(from: format.mimeType) else {
                return false
            }

            switch mediaType {
            case .audio:
                return mimeType.hasPrefix("audio/") && mimeType != ManagedMediaFileFormat.m4a.mimeType && mimeType != ManagedMediaFileFormat.mp3.mimeType
            case .video:
                return mimeType.hasPrefix("video/") && mimeType != ManagedMediaFileFormat.mp4.mimeType
            case .unknown:
                return false
            }
        }
    }

    private func isCandidate(_ format: YouTubePlayerResponseDTO.Format, for mediaType: MediaType) -> Bool {
        guard let mimeType = normalizedMimeType(from: format.mimeType) else {
            return false
        }

        switch mediaType {
        case .audio:
            return mimeType.hasPrefix("audio/")
        case .video:
            return mimeType.hasPrefix("video/")
        case .unknown:
            return false
        }
    }

    private func resolvedURL(for format: YouTubePlayerResponseDTO.Format) -> URL? {
        if let urlString = format.url,
           let directURL = validatedDirectURL(from: urlString) {
            return directURL
        }

        guard let cipherString = format.signatureCipher ?? format.cipher,
              !cipherString.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.query = cipherString

        guard let queryItems = components.queryItems,
              let rawURL = queryItems.first(where: { $0.name == "url" })?.value,
              let baseURL = validatedDirectURL(from: rawURL),
              var resolvedComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let protectedSignature = queryItems.first(where: { $0.name == "s" })?.value
        if protectedSignature != nil {
            return nil
        }

        if let signature = queryItems.first(where: { $0.name == "sig" || $0.name == "signature" })?.value {
            let signatureParameterName = queryItems.first(where: { $0.name == "sp" })?.value ?? "signature"
            var resolvedQueryItems = resolvedComponents.queryItems ?? []
            resolvedQueryItems.append(URLQueryItem(name: signatureParameterName, value: signature))
            resolvedComponents.queryItems = resolvedQueryItems
        }

        guard let resolvedURL = resolvedComponents.url else {
            return nil
        }

        return validatedDirectURL(from: resolvedURL.absoluteString)
    }

    private func validatedDirectURL(from rawURL: String) -> URL? {
        let candidates = [rawURL, rawURL.removingPercentEncoding].compactMap { candidate -> String? in
            guard let candidate else {
                return nil
            }

            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        for candidate in candidates {
            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else {
                continue
            }

            return url
        }

        return nil
    }

    private func hasUnsupportedCipher(_ format: YouTubePlayerResponseDTO.Format) -> Bool {
        let cipherString = format.signatureCipher ?? format.cipher
        return cipherString?.contains("s=") == true
    }

    private func logRuntimeError(_ error: RuntimeError, itemID: String, mediaType: MediaType) {
        switch error {
        case .unavailablePlayback(let reason):
            logger.error(
                "Unavailable playback for \(mediaType.rawValue, privacy: .public) \(itemID, privacy: .public): \(reason ?? "unknown reason", privacy: .public)"
            )
        case .unsupportedCipheredStream:
            logger.error(
                "Unsupported ciphered \(mediaType.rawValue, privacy: .public) stream for \(itemID, privacy: .public)"
            )
        case .unsupportedContainer:
            logger.error(
                "Unsupported \(mediaType.rawValue, privacy: .public) container for \(itemID, privacy: .public)"
            )
        case .noSupportedDirectStream:
            logger.error(
                "No supported direct \(mediaType.rawValue, privacy: .public) stream for \(itemID, privacy: .public)"
            )
        }
    }

    private struct ResolvedStream {
        let url: URL
        let mimeType: String
        let score: Int
    }
}
