import Foundation
import OSLog

@MainActor
final class MediaDetailViewModel: ObservableObject {
    let item: ResolvedMediaItem

    @Published var isStartingDownload = false
    @Published var audioState: DownloadStateSnapshot?
    @Published var videoState: DownloadStateSnapshot?
    @Published var audioStatusMessage: String?
    @Published var videoStatusMessage: String?
    @Published var audioErrorMessage: String?
    @Published var videoErrorMessage: String?

    private var downloadOrchestrator: (any DownloadOrchestrating)?
    private var audioPollingTask: Task<Void, Never>?
    private var videoPollingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "MediaDetailViewModel")

    init(item: ResolvedMediaItem) {
        self.item = item
    }

    func startAudioDownload() async {
        await startDownload(for: .audio)
    }

    func startVideoDownload() async {
        await startDownload(for: .video)
    }

    func configureIfNeeded(downloadOrchestrator: any DownloadOrchestrating) {
        guard self.downloadOrchestrator == nil else {
            return
        }

        self.downloadOrchestrator = downloadOrchestrator
    }

    func refreshStates(updateMessages: Bool = false) async {
        guard let downloadOrchestrator else {
            return
        }

        let audioSnapshot = normalizedSnapshot(
            try? await downloadOrchestrator.currentState(for: item, mediaType: .audio)
        )
        let videoSnapshot = normalizedSnapshot(
            try? await downloadOrchestrator.currentState(for: item, mediaType: .video)
        )

        audioState = audioSnapshot
        videoState = videoSnapshot

        guard updateMessages else {
            return
        }

        applyStatusMessage(for: .audio, state: audioSnapshot, force: true)
        applyStatusMessage(for: .video, state: videoSnapshot, force: true)
    }

    private func startDownload(for mediaType: MediaType) async {
        guard let downloadOrchestrator else {
            setErrorMessage("Download orchestration is not available yet.", for: mediaType)
            return
        }

        logger.debug("Tap received for \(mediaType.rawValue, privacy: .public) download on \(self.item.providerItemId, privacy: .public)")
        clearMessages(for: mediaType)
        setLocalState(
            DownloadStateSnapshot(
                mediaType: mediaType,
                status: .queued,
                progress: 0,
                localFilePath: nil
            ),
            for: mediaType
        )
        applyStatusMessage(for: mediaType, state: state(for: mediaType), force: true)
        isStartingDownload = true
        defer { isStartingDownload = false }

        beginPolling(for: mediaType)

        do {
            try await downloadOrchestrator.startDownload(for: item, mediaType: mediaType)
            await refreshStates(updateMessages: true)
            applyStatusMessage(for: mediaType, state: state(for: mediaType), force: true)
        } catch let error as DownloadOrchestratorError {
            logger.error("Download orchestrator failed for \(mediaType.rawValue, privacy: .public) \(self.item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            setLocalState(
                DownloadStateSnapshot(
                    mediaType: mediaType,
                    status: .failed,
                    progress: nil,
                    localFilePath: nil
                ),
                for: mediaType
            )
            switch error {
            case .activeDownloadInProgress:
                setErrorMessage("Only one download can run at a time in this version.", for: mediaType)
            case .alreadyDownloaded:
                setErrorMessage("\(mediaType.rawValue.capitalized) is already downloaded.", for: mediaType)
            case .unsupportedMediaType:
                setErrorMessage("\(mediaType.rawValue.capitalized) is not available for this item.", for: mediaType)
            case .fileStorageFailed:
                setErrorMessage("The download finished but could not be stored locally.", for: mediaType)
            case .persistenceFailed:
                setErrorMessage("The download state could not be saved.", for: mediaType)
            case .downloadFailed:
                setErrorMessage("The \(mediaType.rawValue) download failed.", for: mediaType)
            }
        } catch let error as YouTubeExtractorBridgeClient.ClientError {
            logger.error("YouTube bridge error while starting \(mediaType.rawValue, privacy: .public) download for \(self.item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            setLocalState(
                DownloadStateSnapshot(
                    mediaType: mediaType,
                    status: .failed,
                    progress: nil,
                    localFilePath: nil
                ),
                for: mediaType
            )
            setErrorMessage(error.localizedDescription, for: mediaType)
        } catch let error as ProviderError {
            logger.error("Provider error while starting \(mediaType.rawValue, privacy: .public) download for \(self.item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            setLocalState(
                DownloadStateSnapshot(
                    mediaType: mediaType,
                    status: .failed,
                    progress: nil,
                    localFilePath: nil
                ),
                for: mediaType
            )
            setErrorMessage(error.localizedDescription, for: mediaType)
        } catch {
            logger.error("Unexpected error while starting \(mediaType.rawValue, privacy: .public) download for \(self.item.providerItemId, privacy: .public): \(String(describing: error), privacy: .public)")
            setLocalState(
                DownloadStateSnapshot(
                    mediaType: mediaType,
                    status: .failed,
                    progress: nil,
                    localFilePath: nil
                ),
                for: mediaType
            )
            setErrorMessage(
                "Could not start the \(mediaType.rawValue) download flow: \(error.localizedDescription)",
                for: mediaType
            )
        }

        stopPolling(for: mediaType)
    }

    private func beginPolling(for mediaType: MediaType) {
        stopPolling(for: mediaType)

        let pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.refreshState(for: mediaType)

                if let state = self.state(for: mediaType),
                   [.downloaded, .failed].contains(state.status) {
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        switch mediaType {
        case .audio:
            audioPollingTask = pollingTask
        case .video:
            videoPollingTask = pollingTask
        case .unknown:
            break
        }
    }

    private func stopPolling(for mediaType: MediaType) {
        switch mediaType {
        case .audio:
            audioPollingTask?.cancel()
            audioPollingTask = nil
        case .video:
            videoPollingTask?.cancel()
            videoPollingTask = nil
        case .unknown:
            break
        }
    }

    private func refreshState(for mediaType: MediaType) async {
        guard let downloadOrchestrator else {
            return
        }

        let snapshot = normalizedSnapshot(
            try? await downloadOrchestrator.currentState(for: item, mediaType: mediaType)
        )
        setLocalState(snapshot, for: mediaType)
        applyStatusMessage(for: mediaType, state: snapshot)
    }

    private func setLocalState(_ snapshot: DownloadStateSnapshot?, for mediaType: MediaType) {
        switch mediaType {
        case .audio:
            audioState = snapshot
        case .video:
            videoState = snapshot
        case .unknown:
            break
        }
    }

    private func applyStatusMessage(for mediaType: MediaType, state: DownloadStateSnapshot?, force: Bool = false) {
        guard let state else {
            return
        }

        if !force, message(for: mediaType) == statusMessageText(for: state, mediaType: mediaType) {
            return
        }

        setErrorMessage(nil, for: mediaType)

        setStatusMessage(statusMessageText(for: state, mediaType: mediaType), for: mediaType)
    }

    private func statusMessageText(for state: DownloadStateSnapshot, mediaType: MediaType) -> String {
        switch state.status {
        case .notDownloaded:
            return "\(mediaType.rawValue.capitalized) has not started yet."
        case .queued:
            return "\(mediaType.rawValue.capitalized) queued."
        case .downloading:
            let percentage = Int((state.progress ?? 0) * 100)
            return "\(mediaType.rawValue.capitalized) downloading \(percentage)%."
        case .downloaded:
            return "\(mediaType.rawValue.capitalized) downloaded."
        case .failed:
            return "\(mediaType.rawValue.capitalized) download failed."
        }
    }

    private func normalizedSnapshot(_ snapshot: DownloadStateSnapshot?) -> DownloadStateSnapshot? {
        guard let snapshot else {
            return nil
        }

        let normalizedProgress: Double?
        switch snapshot.status {
        case .queued:
            normalizedProgress = snapshot.progress ?? 0
        case .downloaded:
            normalizedProgress = 1
        default:
            normalizedProgress = snapshot.progress
        }

        return DownloadStateSnapshot(
            mediaType: snapshot.mediaType,
            status: snapshot.status,
            progress: normalizedProgress,
            localFilePath: snapshot.localFilePath
        )
    }

    private func clearMessages(for mediaType: MediaType) {
        setStatusMessage(nil, for: mediaType)
        setErrorMessage(nil, for: mediaType)
    }

    private func setStatusMessage(_ message: String?, for mediaType: MediaType) {
        switch mediaType {
        case .audio:
            audioStatusMessage = message
        case .video:
            videoStatusMessage = message
        case .unknown:
            break
        }
    }

    private func setErrorMessage(_ message: String?, for mediaType: MediaType) {
        switch mediaType {
        case .audio:
            audioErrorMessage = message
        case .video:
            videoErrorMessage = message
        case .unknown:
            break
        }
    }

    private func message(for mediaType: MediaType) -> String? {
        switch mediaType {
        case .audio:
            return audioStatusMessage
        case .video:
            return videoStatusMessage
        case .unknown:
            return nil
        }
    }

    private func state(for mediaType: MediaType) -> DownloadStateSnapshot? {
        switch mediaType {
        case .audio:
            return audioState
        case .video:
            return videoState
        case .unknown:
            return nil
        }
    }

    deinit {
        audioPollingTask?.cancel()
        videoPollingTask?.cancel()
    }
}
