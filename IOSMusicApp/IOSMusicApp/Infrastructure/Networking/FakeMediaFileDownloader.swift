import Foundation
import OSLog
import AVFoundation

struct FakeMediaFileDownloader: MediaFileDownloading {
    private let fileManager: FileManager
    private let logger: Logger
    private let stepDurationsNanoseconds: UInt64
    private let bundle: Bundle

    init(
        fileManager: FileManager = .default,
        stepDurationsNanoseconds: UInt64 = 140_000_000,
        logger: Logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "FakeMediaFileDownloader"),
        bundle: Bundle = .main
    ) {
        self.fileManager = fileManager
        self.stepDurationsNanoseconds = stepDurationsNanoseconds
        self.logger = logger
        self.bundle = bundle
    }

    func download(
        from remoteURL: URL,
        mediaType: MediaType,
        suggestedFileExtension: String?,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        _ = remoteURL

        let fileExtension = preferredFileExtension(
            for: mediaType,
            suggestedFileExtension: suggestedFileExtension
        )

        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(fileExtension)

        logger.debug("Starting simulated \(mediaType.rawValue, privacy: .public) download")

        for progress in [0.15, 0.45, 0.75, 1.0] {
            try await Task.sleep(nanoseconds: stepDurationsNanoseconds)
            logger.debug("Simulated progress \(Int(progress * 100), privacy: .public)%")
            onProgress?(progress)
        }

        do {
            try materializeSimulatedMedia(at: temporaryURL, mediaType: mediaType)
            try await validatePlayableSimulatedMediaIfNeeded(at: temporaryURL, mediaType: mediaType)
            logger.debug("Created simulated temp file at \(temporaryURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to create simulated temp file: \(String(describing: error), privacy: .public)")
            throw error
        }

        return temporaryURL
    }

    private func preferredFileExtension(for mediaType: MediaType, suggestedFileExtension: String?) -> String {
        if mediaType == .audio {
            return ManagedMediaFileFormat.defaultFormat(for: .audio).fileExtension
        }

        if let suggestedFileExtension, !suggestedFileExtension.isEmpty {
            return suggestedFileExtension
        }

        return ManagedMediaFileFormat.defaultFormat(for: mediaType).fileExtension
    }

    private func materializeSimulatedMedia(at temporaryURL: URL, mediaType: MediaType) throws {
        switch mediaType {
        case .audio:
            let bundledSampleURL = try bundledSampleURL(named: "SampleAudio", withExtension: "m4a")
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try fileManager.removeItem(at: temporaryURL)
            }
            try fileManager.copyItem(at: bundledSampleURL, to: temporaryURL)
        case .video:
            let bundledSampleURL = try bundledSampleURL(named: "SampleVideo", withExtension: "mp4")
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try fileManager.removeItem(at: temporaryURL)
            }
            try fileManager.copyItem(at: bundledSampleURL, to: temporaryURL)
        case .unknown:
            try Data("KAN-11 simulated payload".utf8).write(to: temporaryURL, options: .atomic)
        }
    }

    private func bundledSampleURL(named name: String, withExtension fileExtension: String) throws -> URL {
        if let sampleURL = bundle.url(forResource: name, withExtension: fileExtension) {
            return sampleURL
        }

        throw MediaFileDownloaderError.missingBundledSampleMedia("\(name).\(fileExtension)")
    }

    private func validatePlayableSimulatedMediaIfNeeded(at fileURL: URL, mediaType: MediaType) async throws {
        guard mediaType == .audio || mediaType == .video else {
            return
        }

        let asset = AVURLAsset(url: fileURL)
        let isPlayable = try await asset.load(.isPlayable)

        guard isPlayable else {
            throw MediaFileDownloaderError.unplayableDownloadedMedia
        }
    }
}
