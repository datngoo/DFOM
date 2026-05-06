import AVFoundation
import AVKit
import MediaPlayer
import OSLog
import SwiftUI
import UIKit

enum PlaybackKind: String {
    case audio
    case video
}

enum PlaybackMode: String, CaseIterable {
    case playOnce
    case repeatAll
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .playOnce:
            return "Play Once"
        case .repeatAll:
            return "Repeat All"
        case .repeatOne:
            return "Repeat One"
        case .shuffle:
            return "Shuffle"
        }
    }

    var symbolName: String {
        switch self {
        case .playOnce:
            return "play.circle"
        case .repeatAll:
            return "repeat"
        case .repeatOne:
            return "repeat.1"
        case .shuffle:
            return "shuffle"
        }
    }

    func next() -> PlaybackMode {
        switch self {
        case .playOnce:
            return .repeatAll
        case .repeatAll:
            return .repeatOne
        case .repeatOne:
            return .shuffle
        case .shuffle:
            return .playOnce
        }
    }
}

@MainActor
final class PlaybackCoordinator {
    static let shared = PlaybackCoordinator()

    private var activeOwnerID: ObjectIdentifier?
    private var activeKind: PlaybackKind?
    private var stopActivePlayback: (() -> Void)?

    private init() {}

    func claimPlayback(
        kind: PlaybackKind,
        owner: AnyObject,
        stopHandler: @escaping () -> Void
    ) {
        let ownerID = ObjectIdentifier(owner)

        guard activeOwnerID != ownerID else {
            activeKind = kind
            stopActivePlayback = stopHandler
            return
        }

        stopActivePlayback?()
        activeOwnerID = ownerID
        activeKind = kind
        stopActivePlayback = stopHandler
    }

    func releasePlayback(owner: AnyObject) {
        guard activeOwnerID == ObjectIdentifier(owner) else {
            return
        }

        activeOwnerID = nil
        activeKind = nil
        stopActivePlayback = nil
    }

    func isActive(owner: AnyObject) -> Bool {
        activeOwnerID == ObjectIdentifier(owner)
    }
}

@MainActor
final class PlaybackAudioSessionCoordinator {
    static let shared = PlaybackAudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "PlaybackAudioSession")
    private var lastKnownActiveState = false

    private init() {}

    func activateForPlayback(kind: PlaybackKind, fileURL: URL?) throws {
        let mode: AVAudioSession.Mode = kind == .video ? .moviePlayback : .default

        try session.setCategory(.playback, mode: mode)
        try session.setActive(true)
        lastKnownActiveState = true

        logSessionState(kind: kind, context: "activated", fileURL: fileURL)
    }

    func logSessionState(kind: PlaybackKind, context: String, fileURL: URL?) {
        logger.debug(
            """
            Audio session \(context, privacy: .public) kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL?.path ?? "nil", privacy: .public) \
            category=\(self.session.category.rawValue, privacy: .public) \
            mode=\(self.session.mode.rawValue, privacy: .public) \
            active=\(self.lastKnownActiveState, privacy: .public)
            """
        )
    }
}

@MainActor
final class BackgroundAudioCoordinator {
    static let shared = BackgroundAudioCoordinator()

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    private var remoteCommandsRegistered = false
    private var activeOwnerID: ObjectIdentifier?
    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var previousTrackHandler: (() -> Void)?
    private var nextTrackHandler: (() -> Void)?
    private var changePlaybackPositionHandler: ((Double) -> Void)?
    private var lastPublishedElapsedTime: Double?

    private init() {}

    func attachRemoteCommands(
        owner: AnyObject,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onChangePlaybackPosition: ((Double) -> Void)? = nil,
        onPreviousTrack: (() -> Void)? = nil,
        onNextTrack: (() -> Void)? = nil
    ) {
        activeOwnerID = ObjectIdentifier(owner)
        playHandler = onPlay
        pauseHandler = onPause
        changePlaybackPositionHandler = onChangePlaybackPosition
        previousTrackHandler = onPreviousTrack
        nextTrackHandler = onNextTrack

        if remoteCommandsRegistered {
            commandCenter.changePlaybackPositionCommand.isEnabled = changePlaybackPositionHandler != nil
            updateTrackNavigationCommands()
            return
        }

        remoteCommandsRegistered = true

        // Keep remote controls minimal for the current offline audio feature scope.
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = changePlaybackPositionHandler != nil
        updateTrackNavigationCommands()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playHandler?()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pauseHandler?()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.nowPlayingInfoCenter.playbackState == .playing {
                    self.pauseHandler?()
                } else {
                    self.playHandler?()
                }
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.previousTrackHandler?()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.nextTrackHandler?()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in
                self?.changePlaybackPositionHandler?(event.positionTime)
            }
            return .success
        }
    }

    func detachRemoteCommands(owner: AnyObject) {
        guard activeOwnerID == ObjectIdentifier(owner) else {
            return
        }

        activeOwnerID = nil
        playHandler = nil
        pauseHandler = nil
        changePlaybackPositionHandler = nil
        previousTrackHandler = nil
        nextTrackHandler = nil
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        updateTrackNavigationCommands()
        clearNowPlaying()
    }

    func updateTrackNavigationHandlers(
        owner: AnyObject,
        onPreviousTrack: (() -> Void)?,
        onNextTrack: (() -> Void)?
    ) {
        guard activeOwnerID == ObjectIdentifier(owner) else {
            return
        }

        previousTrackHandler = onPreviousTrack
        nextTrackHandler = onNextTrack
        updateTrackNavigationCommands()
    }

    func publishNowPlaying(
        item: MediaItem,
        fileStorage: LocalFileStorage,
        elapsedTime: Double,
        duration: Double,
        isPlaying: Bool
    ) {
        var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.title

        if let creatorName = item.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creatorName.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyArtist] = creatorName
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtist)
        }

        if duration.isFinite, duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
        }

        let sanitizedElapsedTime = max(elapsedTime, 0)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = sanitizedElapsedTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let artwork = artwork(for: item, fileStorage: fileStorage) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        } else {
            nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingInfoCenter.playbackState = isPlaying ? .playing : .paused
        lastPublishedElapsedTime = sanitizedElapsedTime
    }

    func publishElapsedTimeIfNeeded(
        item: MediaItem,
        fileStorage: LocalFileStorage,
        elapsedTime: Double,
        duration: Double,
        isPlaying: Bool
    ) {
        let sanitizedElapsedTime = max(elapsedTime, 0)

        // Avoid pushing lock-screen updates on every 250 ms player tick.
        guard lastPublishedElapsedTime == nil || abs((lastPublishedElapsedTime ?? 0) - sanitizedElapsedTime) >= 1 else {
            return
        }

        publishNowPlaying(
            item: item,
            fileStorage: fileStorage,
            elapsedTime: sanitizedElapsedTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    func clearNowPlaying() {
        nowPlayingInfoCenter.nowPlayingInfo = nil
        nowPlayingInfoCenter.playbackState = .stopped
        lastPublishedElapsedTime = nil
    }

    private func artwork(for item: MediaItem, fileStorage: LocalFileStorage) -> MPMediaItemArtwork? {
        guard let thumbnailLocalPath = item.thumbnailLocalPath,
              let thumbnailURL = try? fileStorage.resolveExistingManagedFileURL(from: thumbnailLocalPath),
              let image = UIImage(contentsOfFile: thumbnailURL.path) else {
            return nil
        }

        return MPMediaItemArtwork(boundsSize: image.size) { _ in
            image
        }
    }

    private func updateTrackNavigationCommands() {
        commandCenter.previousTrackCommand.isEnabled = previousTrackHandler != nil
        commandCenter.nextTrackCommand.isEnabled = nextTrackHandler != nil
    }
}

private func playerItemStatusLabel(_ status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown:
        return "unknown"
    case .readyToPlay:
        return "readyToPlay"
    case .failed:
        return "failed"
    @unknown default:
        return "unknown-future"
    }
}

private func playerTimeControlStatusLabel(_ status: AVPlayer.TimeControlStatus) -> String {
    switch status {
    case .paused:
        return "paused"
    case .waitingToPlayAtSpecifiedRate:
        return "waiting"
    case .playing:
        return "playing"
    @unknown default:
        return "unknown-future"
    }
}

private func logAssetDiagnostics(
    kind: PlaybackKind,
    fileURL: URL,
    asset: AVURLAsset,
    player: AVPlayer,
    logger: Logger
) async {
    do {
        let isPlayable = try await asset.load(.isPlayable)
        let audibleTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        let visualTracks = try await asset.loadTracks(withMediaCharacteristic: .visual)

        logger.debug(
            """
            Playback diagnostics kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL.path, privacy: .public) \
            playable=\(isPlayable, privacy: .public) \
            audibleTracks=\(audibleTracks.count, privacy: .public) \
            visualTracks=\(visualTracks.count, privacy: .public) \
            playerMuted=\(player.isMuted, privacy: .public)
            """
        )
    } catch {
        logger.error(
            """
            Playback diagnostics failed kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL.path, privacy: .public) \
            error=\(String(describing: error), privacy: .public)
            """
        )
    }
}

@MainActor
final class AudioPlaybackController: ObservableObject {
    static let shared = AudioPlaybackController()

    @Published var title = "Audio Player"
    @Published var playbackStateText = "No audio selected"
    @Published var errorMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published private(set) var playbackMode: PlaybackMode
    @Published private(set) var currentMediaItem: MediaItem?
    @Published private(set) var queueItems: [MediaItem] = []
    @Published private(set) var currentQueueIndex = 0
    @Published var isPlayerPresented = false

    private static let playbackModeDefaultsKey = "AudioPlaybackController.playbackMode"

    private var playlist: [MediaItem] = []
    private var fileStorage: LocalFileStorage
    private var player: AVPlayer?
    private var currentPlaylistIndex = 0
    private var currentPlayerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var isSeeking = false
    private var isReadyToPlay = false
    private var playWhenReady = false
    private var currentFileURL: URL?
    private let playbackCoordinator: PlaybackCoordinator
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private let backgroundAudioCoordinator: BackgroundAudioCoordinator
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "AudioPlaybackController")

    private init(fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        self.fileStorage = fileStorage
        self.playbackCoordinator = .shared
        self.audioSessionCoordinator = .shared
        self.backgroundAudioCoordinator = .shared
        self.playbackMode = Self.loadPersistedPlaybackMode()
        ensureRemoteCommandsAttached()
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
        }
    }

    func configure(
        item: MediaItem,
        playlist: [MediaItem] = [],
        fileStorage: LocalFileStorage? = nil
    ) {
        if let fileStorage {
            self.fileStorage = fileStorage
        }

        let normalizedPlaylist = Self.normalizedPlaylist(for: item, from: playlist)
        let targetIndex = Self.initialPlaylistIndex(for: item, in: normalizedPlaylist)
        let targetItem = normalizedPlaylist[targetIndex]

        self.playlist = normalizedPlaylist
        self.currentPlaylistIndex = targetIndex
        updatePublishedQueueState()

        if currentMediaItem?.id == targetItem.id, player != nil {
            currentMediaItem = targetItem
            title = targetItem.title
            errorMessage = nil
            return
        }

        currentMediaItem = targetItem
        prepareCurrentTrack()
    }

    func presentFullPlayer() {
        guard currentMediaItem != nil else {
            return
        }

        isPlayerPresented = true
    }

    func dismissFullPlayer() {
        isPlayerPresented = false
    }

    func play() {
        guard errorMessage == nil, let player else {
            return
        }

        claimPlaybackOwnership()
        ensureRemoteCommandsAttached()
        playWhenReady = true

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: currentFileURL)
        } catch {
            logger.error("Audio session reactivation failed for item \(self.currentMediaItem?.id.uuidString ?? "unknown", privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        if duration > 0, currentTime >= max(duration - 0.25, 0) {
            player.seek(to: .zero)
        }

        guard isReadyToPlay else {
            playbackStateText = "Loading"
            return
        }

        logger.debug(
            """
            Audio play requested fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player?.isMuted ?? false, privacy: .public)
            """
        )
        player.play()
        publishNowPlaying()
    }

    func pause() {
        ensureRemoteCommandsAttached()
        playWhenReady = false
        player?.pause()
        publishNowPlaying()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        guard let player else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        isSeeking = true
        currentTime = clampedTime

        player.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    func cyclePlaybackMode() {
        updatePlaybackMode(playbackMode.next())
    }

    func playPreviousTrack() {
        navigateToAdjacentTrack(offset: -1)
    }

    func playNextTrack() {
        navigateToAdjacentTrack(offset: 1)
    }

    func enqueueNext(
        item: MediaItem,
        from playlist: [MediaItem] = [],
        fileStorage: LocalFileStorage? = nil
    ) {
        if let fileStorage {
            self.fileStorage = fileStorage
        }

        let candidatePlaylist = Self.normalizedPlaylist(for: item, from: playlist)
        let targetItem = candidatePlaylist.first(where: { $0.id == item.id }) ?? item

        guard targetItem.mediaType == .audio else {
            return
        }

        if self.playlist.isEmpty || currentMediaItem == nil {
            configure(item: targetItem, playlist: candidatePlaylist, fileStorage: fileStorage)
            return
        }

        self.playlist.removeAll { $0.id == targetItem.id }
        let insertionIndex = min(currentPlaylistIndex + 1, self.playlist.count)
        self.playlist.insert(targetItem, at: insertionIndex)
        updatePublishedQueueState()
    }

    func startQueue(
        items: [MediaItem],
        startAt index: Int = 0,
        fileStorage: LocalFileStorage? = nil
    ) {
        guard !items.isEmpty else {
            return
        }

        let clampedIndex = min(max(index, 0), items.count - 1)
        configure(item: items[clampedIndex], playlist: items, fileStorage: fileStorage)
        play()
    }

    func moveQueueItem(id: UUID, direction: QueueMoveDirection) {
        guard let sourceIndex = playlist.firstIndex(where: { $0.id == id }) else {
            return
        }

        let destinationIndex = sourceIndex + direction.offset
        guard playlist.indices.contains(destinationIndex),
              sourceIndex != currentPlaylistIndex,
              destinationIndex != currentPlaylistIndex else {
            return
        }

        let item = playlist.remove(at: sourceIndex)
        playlist.insert(item, at: destinationIndex)

        if sourceIndex < currentPlaylistIndex {
            currentPlaylistIndex -= 1
        }

        if destinationIndex <= currentPlaylistIndex {
            currentPlaylistIndex += 1
        }

        updatePublishedQueueState()
    }

    func removeQueueItem(id: UUID) {
        guard let sourceIndex = playlist.firstIndex(where: { $0.id == id }),
              sourceIndex != currentPlaylistIndex else {
            return
        }

        playlist.remove(at: sourceIndex)

        if sourceIndex < currentPlaylistIndex {
            currentPlaylistIndex -= 1
        }

        updatePublishedQueueState()
    }

    func reorderQueue(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var nextPlaylist = playlist
        nextPlaylist.move(fromOffsets: offsets, toOffset: destination)

        guard let currentMediaItemID = currentMediaItem?.id,
              let nextCurrentIndex = nextPlaylist.firstIndex(where: { $0.id == currentMediaItemID }) else {
            return
        }

        playlist = nextPlaylist
        currentPlaylistIndex = nextCurrentIndex
        updatePublishedQueueState()
    }

    var canControlPlayback: Bool {
        currentMediaItem != nil && errorMessage == nil && player != nil && duration >= 0
    }

    var canPlayPreviousTrack: Bool {
        playlist.indices.contains(currentPlaylistIndex - 1)
    }

    var canPlayNextTrack: Bool {
        playlist.indices.contains(currentPlaylistIndex + 1)
    }

    var displayedDuration: Double {
        duration > 0 ? duration : max(currentTime, 1)
    }

    var progressFraction: Double {
        guard duration > 0 else {
            return 0
        }

        return min(max(currentTime / duration, 0), 1)
    }

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func prepareCurrentTrack(autoplay: Bool = false) {
        guard let item = currentMediaItem else {
            return
        }

        guard item.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setError("Audio file path is missing.")
            return
        }

        let fileURL: URL

        do {
            fileURL = try fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)
        } catch {
            logger.error("Audio playback open failed for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio file is missing at the saved local path.")
            return
        }

        currentFileURL = fileURL
        title = item.title
        logger.debug("Audio playback local file URL: \(fileURL.path, privacy: .public)")
        claimPlaybackOwnership()

        let asset = AVURLAsset(url: fileURL)
        let player = player ?? AVPlayer()
        let playerItem = AVPlayerItem(asset: asset)
        player.isMuted = false

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: fileURL)
        } catch {
            logger.error("Audio session activation failed for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        ensureRemoteCommandsAttached()
        removeObservers()
        self.player = player
        isReadyToPlay = false
        playWhenReady = autoplay
        player.pause()
        player.replaceCurrentItem(with: playerItem)
        currentPlayerItem = playerItem
        errorMessage = nil
        playbackStateText = "Loading"
        currentTime = 0
        duration = 0
        installObservers(for: player, item: playerItem)
        publishNowPlaying()
        Task {
            await logAssetDiagnostics(kind: .audio, fileURL: fileURL, asset: asset, player: player, logger: logger)
        }
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatusChange(item.status, error: item.error)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handlePeriodicTimeUpdate(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func handleItemStatusChange(_ status: AVPlayerItem.Status, error: Error?) {
        logger.debug(
            """
            Audio player item status=\(playerItemStatusLabel(status), privacy: .public) \
            fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player?.isMuted ?? false, privacy: .public)
            """
        )

        switch status {
        case .readyToPlay:
            isReadyToPlay = true
            errorMessage = nil
            duration = resolvedDuration(from: currentPlayerItem)
            playbackStateText = playWhenReady ? "Playing" : "Ready"
            publishNowPlaying()

            if playWhenReady {
                player?.play()
            }
        case .failed:
            logger.error("Audio player item failed for item \(self.currentMediaItem?.id.uuidString ?? "unknown", privacy: .public): \(String(describing: error ?? self.currentPlayerItem?.error), privacy: .public)")
            setError(error?.localizedDescription ?? self.currentPlayerItem?.error?.localizedDescription ?? "Audio player item failed to load.")
        case .unknown:
            isReadyToPlay = false
            playbackStateText = "Loading"
        @unknown default:
            isReadyToPlay = false
            playbackStateText = "Loading"
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logger.debug("Audio time control status=\(playerTimeControlStatusLabel(status), privacy: .public)")

        switch status {
        case .paused:
            isPlaying = false
            if errorMessage == nil {
                if currentTime >= max(duration - 0.25, 0), duration > 0, !playWhenReady {
                    playbackStateText = "Finished"
                } else {
                    playbackStateText = currentTime > 0 ? "Paused" : "Ready"
                }
            }
            publishNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = false
            if errorMessage == nil {
                playbackStateText = "Buffering"
            }
            publishNowPlaying()
        case .playing:
            isPlaying = true
            errorMessage = nil
            playbackStateText = "Playing"
            publishNowPlaying()
        @unknown default:
            isPlaying = false
        }
    }

    private func handlePeriodicTimeUpdate(_ time: CMTime) {
        guard !isSeeking, let currentMediaItem else {
            return
        }

        currentTime = max(time.seconds, 0)
        duration = max(duration, resolvedDuration(from: currentPlayerItem))
        backgroundAudioCoordinator.publishElapsedTimeIfNeeded(
            item: currentMediaItem,
            fileStorage: fileStorage,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func handlePlaybackEnded() {
        currentTime = duration

        switch playbackMode {
        case .playOnce:
            playWhenReady = false
            isPlaying = false
            playbackStateText = "Finished"
            publishNowPlaying()
        case .repeatOne:
            restartCurrentTrack()
        case .repeatAll:
            playAdjacentTrack()
        case .shuffle:
            playShuffledTrack()
        }
    }

    private func resolvedDuration(from item: AVPlayerItem?) -> Double {
        guard let item else {
            return 0
        }

        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return seconds
    }

    private func setError(_ message: String) {
        player?.pause()
        playWhenReady = false
        isReadyToPlay = false
        isPlaying = false
        playbackStateText = "Unavailable"
        errorMessage = message
        currentTime = 0
        duration = 0
        backgroundAudioCoordinator.clearNowPlaying()
    }

    private func removeObservers() {
        itemStatusObservation = nil
        timeControlStatusObservation = nil

        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func restartCurrentTrack() {
        guard let player else {
            return
        }

        playWhenReady = true

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: currentFileURL)
        } catch {
            logger.error("Audio session reactivation failed for repeated item \(self.currentMediaItem?.id.uuidString ?? "unknown", privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        player.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.currentTime = 0
                self.player?.play()
                self.publishNowPlaying()
            }
        }
    }

    private func navigateToAdjacentTrack(offset: Int) {
        let targetIndex = currentPlaylistIndex + offset
        guard playlist.indices.contains(targetIndex) else {
            return
        }

        currentPlaylistIndex = targetIndex
        currentMediaItem = playlist[targetIndex]
        updatePublishedQueueState()
        prepareCurrentTrack(autoplay: true)
    }

    private func playAdjacentTrack() {
        guard !playlist.isEmpty else {
            return
        }

        if playlist.count == 1 {
            restartCurrentTrack()
            return
        }

        let nextIndex = (currentPlaylistIndex + 1) % playlist.count
        currentPlaylistIndex = nextIndex
        currentMediaItem = playlist[nextIndex]
        updatePublishedQueueState()
        prepareCurrentTrack(autoplay: true)
    }

    private func playShuffledTrack() {
        guard !playlist.isEmpty else {
            return
        }

        if playlist.count == 1 {
            restartCurrentTrack()
            return
        }

        let availableIndexes = playlist.indices.filter { $0 != currentPlaylistIndex }
        guard let nextIndex = availableIndexes.randomElement() else {
            restartCurrentTrack()
            return
        }

        currentPlaylistIndex = nextIndex
        currentMediaItem = playlist[nextIndex]
        updatePublishedQueueState()
        prepareCurrentTrack(autoplay: true)
    }

    private static func normalizedPlaylist(for item: MediaItem, from playlist: [MediaItem]) -> [MediaItem] {
        let playableItems = playlist.filter {
            $0.mediaType == .audio &&
            $0.downloadStatus == .downloaded &&
            $0.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        if playableItems.contains(where: { $0.id == item.id }) {
            return playableItems
        }

        return [item] + playableItems.filter { $0.id != item.id }
    }

    private static func initialPlaylistIndex(for item: MediaItem, in playlist: [MediaItem]) -> Int {
        playlist.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func publishNowPlaying() {
        guard let currentMediaItem else {
            return
        }

        backgroundAudioCoordinator.publishNowPlaying(
            item: currentMediaItem,
            fileStorage: fileStorage,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func updatePublishedQueueState() {
        queueItems = playlist
        currentQueueIndex = currentPlaylistIndex
        syncRemoteTrackNavigationAvailability()
    }

    private func syncRemoteTrackNavigationAvailability() {
        backgroundAudioCoordinator.updateTrackNavigationHandlers(
            owner: self,
            onPreviousTrack: canPlayPreviousTrack ? { [weak self] in self?.playPreviousTrack() } : nil,
            onNextTrack: canPlayNextTrack ? { [weak self] in self?.playNextTrack() } : nil
        )
    }

    private func ensureRemoteCommandsAttached() {
        backgroundAudioCoordinator.attachRemoteCommands(
            owner: self,
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onChangePlaybackPosition: { [weak self] position in self?.seek(to: position) },
            onPreviousTrack: { [weak self] in self?.playPreviousTrack() },
            onNextTrack: { [weak self] in self?.playNextTrack() }
        )
    }

    private func claimPlaybackOwnership() {
        playbackCoordinator.claimPlayback(
            kind: .audio,
            owner: self,
            stopHandler: { [weak self] in
                self?.stopForExternalPlayback()
            }
        )
    }

    private func stopForExternalPlayback() {
        removeObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentPlayerItem = nil
        currentMediaItem = nil
        playlist = []
        queueItems = []
        currentPlaylistIndex = 0
        currentQueueIndex = 0
        currentFileURL = nil
        isReadyToPlay = false
        playWhenReady = false
        isSeeking = false
        isPlaying = false
        title = "Audio Player"
        playbackStateText = "No audio selected"
        errorMessage = nil
        currentTime = 0
        duration = 0
        isPlayerPresented = false
        backgroundAudioCoordinator.detachRemoteCommands(owner: self)
        playbackCoordinator.releasePlayback(owner: self)
    }

    private func updatePlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.playbackModeDefaultsKey)
    }

    private static func loadPersistedPlaybackMode() -> PlaybackMode {
        guard let rawValue = UserDefaults.standard.string(forKey: playbackModeDefaultsKey),
              let mode = PlaybackMode(rawValue: rawValue) else {
            return .playOnce
        }

        return mode
    }
}

enum QueueMoveDirection {
    case up
    case down

    var offset: Int {
        switch self {
        case .up:
            return -1
        case .down:
            return 1
        }
    }
}

struct AudioPlayerView: View {
    @EnvironmentObject private var playbackController: AudioPlaybackController
    @State private var isQueuePresented = false

    private let item: MediaItem?
    private let playlist: [MediaItem]
    private let fileStorage: LocalFileStorage

    init(
        item: MediaItem? = nil,
        playlist: [MediaItem] = [],
        fileStorage: LocalFileStorage = ApplicationSupportFileStorage()
    ) {
        self.item = item
        self.playlist = playlist
        self.fileStorage = fileStorage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artworkSection
                    .padding(.top, 28)
                    .padding(.bottom, 28)
                trackInfoSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                scrubberSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                controlsSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                secondarySection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let item {
                playbackController.configure(item: item, playlist: playlist, fileStorage: fileStorage)
            }
        }
        .sheet(isPresented: $isQueuePresented) {
            NavigationStack {
                QueueManagementView()
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Artwork

    private var artworkSection: some View {
        Group {
            if let currentItem = playbackController.currentMediaItem {
                artworkImage(for: currentItem)
            } else {
                artworkPlaceholder(icon: "music.note")
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .animation(.easeInOut(duration: 0.2), value: playbackController.currentMediaItem?.id)
    }

    @ViewBuilder
    private func artworkImage(for item: MediaItem) -> some View {
        if let localPath = item.thumbnailLocalPath,
           !localPath.isEmpty,
           let url = try? fileStorage.resolveExistingManagedFileURL(from: localPath),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let remoteURL = item.thumbnailRemoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: artworkPlaceholder(icon: "music.note")
                }
            }
        } else {
            artworkPlaceholder(icon: "music.note")
        }
    }

    private func artworkPlaceholder(icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(.secondarySystemFill), Color(.tertiarySystemFill)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: Track info

    private var trackInfoSection: some View {
        VStack(spacing: 6) {
            if let currentItem = playbackController.currentMediaItem {
                Text(currentItem.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                let artist = currentItem.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            let stateText = playbackController.errorMessage ?? playbackController.playbackStateText
            let isError = playbackController.errorMessage != nil
            Text(stateText)
                .font(.caption.weight(.medium))
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: Scrubber

    private var scrubberSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { min(playbackController.currentTime, playbackController.displayedDuration) },
                    set: { playbackController.seek(to: $0) }
                ),
                in: 0...playbackController.displayedDuration
            )
            .tint(Color.accentColor)
            .disabled(!playbackController.canControlPlayback || playbackController.displayedDuration <= 0)

            HStack {
                Text(playbackController.formattedTime(playbackController.currentTime))
                Spacer()
                Text(playbackController.formattedTime(playbackController.duration))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    // MARK: Controls

    private var controlsSection: some View {
        HStack(spacing: 0) {
            playerControlButton(
                systemName: "backward.fill", size: 50,
                iconFont: .title2.weight(.semibold),
                isPrimary: false, isDisabled: !playbackController.canPlayPreviousTrack
            ) { playbackController.playPreviousTrack() }

            Spacer()

            playerControlButton(
                systemName: playbackController.isPlaying ? "pause.fill" : "play.fill", size: 68,
                iconFont: .title.weight(.semibold),
                isPrimary: true, isDisabled: !playbackController.canControlPlayback
            ) { playbackController.togglePlayback() }

            Spacer()

            playerControlButton(
                systemName: "forward.fill", size: 50,
                iconFont: .title2.weight(.semibold),
                isPrimary: false, isDisabled: !playbackController.canPlayNextTrack
            ) { playbackController.playNextTrack() }
        }
        .padding(.horizontal, 8)
    }

    private func playerControlButton(
        systemName: String, size: CGFloat, iconFont: Font,
        isPrimary: Bool, isDisabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(iconFont)
                .frame(width: size, height: size)
                .foregroundStyle(isPrimary ? .white : .primary)
                .background(Circle().fill(isPrimary ? Color.accentColor : Color(.secondarySystemFill)))
                .shadow(
                    color: isPrimary ? Color.accentColor.opacity(0.30) : .black.opacity(0.06),
                    radius: isPrimary ? 16 : 4, y: isPrimary ? 6 : 2
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.12), value: isDisabled)
    }

    // MARK: Secondary

    private var secondarySection: some View {
        HStack(spacing: 10) {
            Button { playbackController.cyclePlaybackMode() } label: {
                Label(playbackController.playbackMode.title,
                      systemImage: playbackController.playbackMode.symbolName)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.bordered)
            .tint(Color.accentColor)
            .disabled(!playbackController.canControlPlayback)

            if !playbackController.queueItems.isEmpty {
                Button { isQueuePresented = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text("\(playbackController.queueItems.count)")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(height: 40)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct QueueManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playbackController: AudioPlaybackController

    var body: some View {
        List {
            Section {
                ForEach(Array(playbackController.queueItems.enumerated()), id: \.element.id) { index, item in
                    QueueListRow(
                        item: item,
                        artistLabel: artistLabel(for: item),
                        isCurrent: index == playbackController.currentQueueIndex,
                        onRemove: { playbackController.removeQueueItem(id: item.id) }
                    )
                    .moveDisabled(index == playbackController.currentQueueIndex)
                }
                .onMove(perform: playbackController.reorderQueue)
            } footer: {
                Text("Long press and drag a song to change its order. Removing a song only removes it from the queue.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func artistLabel(for item: MediaItem) -> String {
        let name = item.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Unknown artist" : name
    }
}

private struct QueueListRow: View {
    let item: MediaItem
    let artistLabel: String
    let isCurrent: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)

                Text(artistLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct GlobalAudioMiniPlayer: View {
    private enum Layout {
        static let artworkSize: CGFloat = 36
        static let artworkCornerRadius: CGFloat = 7
        static let buttonSize: CGFloat = 34
        static let cornerRadius: CGFloat = 20
        static let progressHeight: CGFloat = 2.5
    }

    @EnvironmentObject private var playbackController: AudioPlaybackController
    private let fileStorage: LocalFileStorage = ApplicationSupportFileStorage()

    var body: some View {
        if let currentMediaItem = playbackController.currentMediaItem {
            Button {
                playbackController.presentFullPlayer()
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        artworkView(for: currentMediaItem)
                            .frame(width: Layout.artworkSize, height: Layout.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: Layout.artworkCornerRadius, style: .continuous))

                        Text(currentMediaItem.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            playbackController.togglePlayback()
                        } label: {
                            Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.bold))
                                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                                .foregroundStyle(.primary)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: max(proxy.size.width * playbackController.progressFraction, 5))
                        }
                    }
                    .frame(height: Layout.progressHeight)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func artworkView(for item: MediaItem) -> some View {
        if let localPath = item.thumbnailLocalPath,
           !localPath.isEmpty,
           let url = try? fileStorage.resolveExistingManagedFileURL(from: localPath),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let remoteURL = item.thumbnailRemoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: miniArtworkPlaceholder
                }
            }
        } else {
            miniArtworkPlaceholder
        }
    }

    private var miniArtworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.secondarySystemFill), Color(.tertiarySystemFill)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var playbackStateText = "Preparing"
    @Published var errorMessage: String?
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var isPlaying = false

    private let item: MediaItem
    private let fileStorage: LocalFileStorage
    private let playbackCoordinator: PlaybackCoordinator
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private let backgroundAudioCoordinator: BackgroundAudioCoordinator
    private var didPreparePlayer = false
    private var remoteCommandsAttached = false
    private var preparationToken: UUID?
    private var currentPlayerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var currentFileURL: URL?
    private var isReadyToPlay = false
    private var playWhenReady = false
    private var currentTime: Double = 0
    private var duration: Double = 0
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "VideoPlayerViewModel")

    let title: String
    let creatorName: String?
    let player = AVPlayer()

    init(item: MediaItem, fileStorage: LocalFileStorage) {
        self.item = item
        self.fileStorage = fileStorage
        self.playbackCoordinator = .shared
        self.audioSessionCoordinator = .shared
        self.backgroundAudioCoordinator = .shared
        self.title = item.title
        self.creatorName = item.creatorName
        self.player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
            backgroundAudioCoordinator.detachRemoteCommands(owner: self)
            playbackCoordinator.releasePlayback(owner: self)
        }
    }

    func prepareIfNeeded() {
        guard !didPreparePlayer else {
            return
        }

        didPreparePlayer = true
        Task {
            await preparePlayer(autoplay: true)
        }
    }

    func play() {
        guard errorMessage == nil else {
            return
        }

        claimPlaybackOwnership()
        ensureRemoteCommandsAttached()
        playWhenReady = true

        guard currentPlayerItem != nil else {
            didPreparePlayer = true
            Task {
                await preparePlayer(autoplay: true)
            }
            return
        }

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .video, fileURL: currentFileURL)
        } catch {
            logger.error("Video session activation failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video audio session could not be activated: \(error.localizedDescription)")
            return
        }

        guard isReadyToPlay else {
            playbackStateText = "Loading"
            logger.debug("Video play deferred until ready fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public)")
            return
        }

        player.isMuted = false
        logger.debug(
            """
            Video play requested fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player.isMuted, privacy: .public)
            """
        )
        player.play()
    }

    func pause() {
        playWhenReady = false
        player.pause()
        publishNowPlaying()
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard currentPlayerItem != nil else {
            return
        }

        let upperBound = max(durationSeconds, duration, 0)
        let clampedSeconds = min(max(seconds, 0), upperBound)
        let targetTime = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedSeconds
        currentTimeSeconds = clampedSeconds
        publishNowPlaying()
    }

    func seekBy(_ offset: Double) {
        seek(to: currentTimeSeconds + offset)
    }

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else {
            return "0:00"
        }

        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let secondsComponent = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secondsComponent)
    }

    var remainingTimeText: String {
        "-\(formattedTime(max(durationSeconds - currentTimeSeconds, 0)))"
    }

    func handleDisappear(scenePhase: ScenePhase) {
        guard scenePhase == .active else {
            return
        }

        pause()
    }

    private func preparePlayer(autoplay: Bool) async {
        guard item.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setError("Video file path is missing.")
            return
        }

        let token = UUID()
        preparationToken = token
        claimPlaybackOwnership()
        ensureRemoteCommandsAttached()

        let fileURL: URL

        do {
            fileURL = try fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)
        } catch {
            logger.error("Video playback open failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video file is missing at the saved local path.")
            return
        }

        currentFileURL = fileURL
        logger.debug("Video playback local file URL: \(fileURL.path, privacy: .public)")

        let asset = AVURLAsset(url: fileURL)

        do {
            let isPlayable = try await asset.load(.isPlayable)
            let audibleTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
            guard preparationToken == token else {
                return
            }

            guard isPlayable else {
                logger.error("Video asset is not playable for item \(self.item.id.uuidString, privacy: .public)")
                setError("Video file is not playable.")
                return
            }

            logger.debug(
                """
                Video asset inspected fileURL=\(fileURL.path, privacy: .public) \
                audibleTracks=\(audibleTracks.count, privacy: .public)
                """
            )

            try audioSessionCoordinator.activateForPlayback(kind: .video, fileURL: fileURL)

            let playerItem = AVPlayerItem(asset: asset)
            removeObservers()
            currentPlayerItem = playerItem
            isReadyToPlay = false
            playWhenReady = autoplay
            currentTime = 0
            duration = 0
            currentTimeSeconds = 0
            durationSeconds = 0
            isPlaying = false
            player.isMuted = false
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            player.replaceCurrentItem(with: playerItem)
            installObservers(for: player, item: playerItem)
            errorMessage = nil
            playbackStateText = "Loading"
            publishNowPlaying()

            Task {
                await logAssetDiagnostics(kind: .video, fileURL: fileURL, asset: asset, player: player, logger: logger)
            }
        } catch {
            logger.error("Video playback preparation failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video file could not be prepared: \(error.localizedDescription)")
        }
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatusChange(item.status, error: item.error)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handlePeriodicTimeUpdate(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func removeObservers() {
        itemStatusObservation = nil
        timeControlStatusObservation = nil

        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func handleItemStatusChange(_ status: AVPlayerItem.Status, error: Error?) {
        logger.debug(
            """
            Video player item status=\(playerItemStatusLabel(status), privacy: .public) \
            fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player.isMuted, privacy: .public)
            """
        )

        switch status {
        case .readyToPlay:
            isReadyToPlay = true
            errorMessage = nil
            duration = resolvedDuration(from: currentPlayerItem)
            durationSeconds = duration
            playbackStateText = player.timeControlStatus == .playing ? "Playing" : "Ready"
            publishNowPlaying()

            if playWhenReady {
                play()
            }
        case .failed:
            logger.error("Video player item failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error ?? self.currentPlayerItem?.error), privacy: .public)")
            setError(error?.localizedDescription ?? self.currentPlayerItem?.error?.localizedDescription ?? "Video player item failed to load.")
        case .unknown:
            isReadyToPlay = false
            playbackStateText = "Loading"
        @unknown default:
            isReadyToPlay = false
            playbackStateText = "Loading"
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logger.debug("Video time control status=\(playerTimeControlStatusLabel(status), privacy: .public)")

        switch status {
        case .paused:
            isPlaying = false
            if errorMessage == nil {
                playbackStateText = isReadyToPlay ? "Ready" : "Loading"
            }
            publishNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = false
            if errorMessage == nil {
                playbackStateText = "Buffering"
            }
            publishNowPlaying()
        case .playing:
            isPlaying = true
            errorMessage = nil
            playbackStateText = "Playing"
            publishNowPlaying()
        @unknown default:
            break
        }
    }

    private func handlePeriodicTimeUpdate(_ time: CMTime) {
        currentTime = max(time.seconds, 0)
        duration = max(duration, resolvedDuration(from: currentPlayerItem))
        currentTimeSeconds = currentTime
        durationSeconds = duration
        publishNowPlaying()
    }

    private func handlePlaybackEnded() {
        playWhenReady = false
        isPlaying = false
        playbackStateText = "Finished"
        currentTime = duration
        currentTimeSeconds = currentTime
        publishNowPlaying()
    }

    private func setError(_ message: String) {
        removeObservers()
        preparationToken = nil
        playWhenReady = false
        isReadyToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentPlayerItem = nil
        errorMessage = message
        playbackStateText = "Unavailable"
        currentTime = 0
        duration = 0
        currentTimeSeconds = 0
        durationSeconds = 0
        isPlaying = false
        backgroundAudioCoordinator.clearNowPlaying()
    }

    private func resolvedDuration(from item: AVPlayerItem?) -> Double {
        guard let item else {
            return 0
        }

        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return seconds
    }

    private func publishNowPlaying() {
        guard playbackCoordinator.isActive(owner: self) else {
            return
        }

        backgroundAudioCoordinator.publishNowPlaying(
            item: item,
            fileStorage: fileStorage,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: player.timeControlStatus == .playing
        )
    }

    private func claimPlaybackOwnership() {
        playbackCoordinator.claimPlayback(
            kind: .video,
            owner: self,
            stopHandler: { [weak self] in
                self?.stopForExternalPlayback()
            }
        )
    }

    private func ensureRemoteCommandsAttached() {
        guard !remoteCommandsAttached else {
            return
        }

        remoteCommandsAttached = true
        backgroundAudioCoordinator.attachRemoteCommands(
            owner: self,
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() }
        )
    }

    private func stopForExternalPlayback() {
        removeObservers()
        preparationToken = nil
        playWhenReady = false
        isReadyToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentPlayerItem = nil
        currentFileURL = nil
        didPreparePlayer = false
        errorMessage = nil
        playbackStateText = "Stopped"
        currentTime = 0
        duration = 0
        currentTimeSeconds = 0
        durationSeconds = 0
        isPlaying = false
        backgroundAudioCoordinator.detachRemoteCommands(owner: self)
        remoteCommandsAttached = false
        playbackCoordinator.releasePlayback(owner: self)
    }
}

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestedLandscapeFullscreen = false
    @State private var areControlsVisible = true
    @State private var areLandscapeControlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var landscapeControlsHideToken = UUID()
    private let audioPlaybackController = AudioPlaybackController.shared

    init(item: MediaItem, fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(item: item, fileStorage: fileStorage))
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let portraitWidth = max(geometry.size.width - 40, 0)
            let videoWidth = min(portraitWidth, 760)
            let videoHeight = videoWidth * 9 / 16

            ZStack {
                cinematicBackground

                if isLandscape {
                    landscapeLayout(geometry: geometry)
                } else {
                    portraitLayout(
                        topSafeArea: geometry.safeAreaInsets.top,
                        bottomSafeArea: geometry.safeAreaInsets.bottom,
                        videoWidth: videoWidth,
                        videoHeight: videoHeight
                    )
                }
            }
            .onAppear {
                updateFullscreenControlsVisibility(isLandscape: isLandscape)
            }
            .onChange(of: isLandscape) { _, newValue in
                updateFullscreenControlsVisibility(isLandscape: newValue)
            }
            .onChange(of: viewModel.isPlaying) { _, isPlaying in
                handlePlaybackStateChange(isPlaying: isPlaying, isLandscape: isLandscape)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            audioPlaybackController.pause()
            viewModel.prepareIfNeeded()
        }
        .onDisappear {
            landscapeControlsHideToken = UUID()
            if requestedLandscapeFullscreen {
                VideoPlayerOrientationHelper.requestOrientation(.portrait)
            }
            viewModel.handleDisappear(scenePhase: scenePhase)
        }
    }

    private var cinematicBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [Color.white.opacity(0.03), Color.clear, Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.05), Color.clear, Color.black.opacity(0.72)],
                center: .center,
                startRadius: 40,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func portraitLayout(
        topSafeArea: CGFloat,
        bottomSafeArea: CGFloat,
        videoWidth: CGFloat,
        videoHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                chromeButton(systemName: "xmark") {
                    dismiss()
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, max(topSafeArea, 12) + 4)

            titleCard
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Spacer(minLength: 28)

            videoStage(
                width: videoWidth,
                height: videoHeight,
                cornerRadius: 24,
                controlsVisible: areControlsVisible
            ) {
                handlePortraitVideoTap()
            }

            Spacer(minLength: 28)

            bottomArea(bottomSafeArea: bottomSafeArea, showFullscreenButton: true)
        }
    }

    private func landscapeLayout(geometry: GeometryProxy) -> some View {
        ZStack {
            videoStage(
                width: geometry.size.width,
                height: geometry.size.height,
                cornerRadius: 0,
                controlsVisible: areLandscapeControlsVisible
            ) {
                handleLandscapeVideoTap()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if areLandscapeControlsVisible {
                    HStack {
                        subtleFullscreenButton(systemName: "arrow.down.right.and.arrow.up.left") {
                            requestedLandscapeFullscreen = false
                            landscapeControlsHideToken = UUID()
                            VideoPlayerOrientationHelper.requestOrientation(.portrait)
                        }
                        .accessibilityLabel("Exit fullscreen")

                        Spacer()
                    }
                    .padding(.leading, 18)
                    .padding(.top, max(geometry.safeAreaInsets.top, 8) + 4)
                    .transition(.opacity)
                }

                Spacer()

                if areLandscapeControlsVisible {
                    landscapeBottomArea(
                        bottomSafeArea: geometry.safeAreaInsets.bottom,
                        availableWidth: geometry.size.width
                    )
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }
        }
    }

    private var titleCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(viewModel.errorMessage ?? viewModel.playbackStateText)
                    .font(.caption)
                    .foregroundStyle(viewModel.errorMessage == nil ? Color.white.opacity(0.68) : Color.red.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func videoStage(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        controlsVisible: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        ZStack {
            NativeVideoPlayerController(player: viewModel.player)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if controlsVisible {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.14),
                        Color.black.opacity(0.22),
                        Color.black.opacity(0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                HStack(spacing: 28) {
                    transportButton(systemName: "gobackward.10", size: 50, iconScale: 0.34) {
                        viewModel.seekBy(-10)
                    }

                    transportButton(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill", size: 66, iconScale: 0.36) {
                        viewModel.togglePlayback()
                    }

                    transportButton(systemName: "goforward.10", size: 50, iconScale: 0.34) {
                        viewModel.seekBy(10)
                    }
                }
                .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(cornerRadius > 0 ? 0.04 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(cornerRadius > 0 ? 0.08 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
    }

    private func bottomArea(bottomSafeArea: CGFloat, showFullscreenButton: Bool) -> some View {
        VStack(spacing: 10) {
            progressBarArea(showMinimizeButton: false)

            if showFullscreenButton {
                HStack {
                    Spacer()
                    chromeButton(
                        systemName: requestedLandscapeFullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    ) {
                        requestedLandscapeFullscreen.toggle()
                        VideoPlayerOrientationHelper.requestOrientation(
                            requestedLandscapeFullscreen ? .landscapeRight : .portrait
                        )
                    }
                    .accessibilityLabel(requestedLandscapeFullscreen ? "Exit fullscreen rotation" : "Rotate fullscreen")
                }
            }
        }
        .padding(.horizontal, showFullscreenButton ? 16 : 0)
        .padding(.bottom, max(bottomSafeArea, 12) + (showFullscreenButton ? 4 : 8))
    }

    private func landscapeBottomArea(bottomSafeArea: CGFloat, availableWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(viewModel.formattedTime(isScrubbing ? scrubPosition : viewModel.currentTimeSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 52, alignment: .leading)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : viewModel.currentTimeSeconds },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(viewModel.durationSeconds, 1),
                onEditingChanged: handleScrubbingChanged
            )
            .tint(.white)
            .disabled(viewModel.durationSeconds <= 0)
            .labelsHidden()

            Text(viewModel.durationSeconds > 0 ? viewModel.remainingTimeText : viewModel.formattedTime(0))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: 52, alignment: .trailing)
        }
        .frame(maxWidth: min(max(availableWidth - 96, 280), 720))
        .padding(.bottom, max(bottomSafeArea, 12) + 18)
    }

    private func progressBarArea(showMinimizeButton: Bool) -> some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : viewModel.currentTimeSeconds },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(viewModel.durationSeconds, 1),
                onEditingChanged: handleScrubbingChanged
            )
            .tint(.white)
            .disabled(viewModel.durationSeconds <= 0)
            .labelsHidden()

            HStack {
                Text(viewModel.formattedTime(isScrubbing ? scrubPosition : viewModel.currentTimeSeconds))
                    .frame(minWidth: 44, alignment: .leading)

                Spacer(minLength: 12)

                Text(viewModel.durationSeconds > 0 ? viewModel.remainingTimeText : viewModel.formattedTime(0))
                    .frame(minWidth: 56, alignment: .trailing)

                if !showMinimizeButton {
                    Spacer(minLength: 0)
                }

                if showMinimizeButton {
                    chromeButton(systemName: "arrow.down.right.and.arrow.up.left") {
                        requestedLandscapeFullscreen = false
                        landscapeControlsHideToken = UUID()
                        VideoPlayerOrientationHelper.requestOrientation(.portrait)
                    }
                    .accessibilityLabel("Exit fullscreen")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(.horizontal, 2)
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func subtleFullscreenButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.28), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func transportButton(systemName: String, size: CGFloat, iconScale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func handleScrubbingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing

        if isEditing {
            scrubPosition = viewModel.currentTimeSeconds
            landscapeControlsHideToken = UUID()
        } else {
            viewModel.seek(to: scrubPosition)
            if viewModel.isPlaying {
                scheduleLandscapeControlsAutoHide()
            }
        }
    }

    private func handleLandscapeVideoTap() {
        let shouldShowControls = !areLandscapeControlsVisible

        withAnimation(.easeInOut(duration: 0.2)) {
            areLandscapeControlsVisible = shouldShowControls
        }

        landscapeControlsHideToken = UUID()

        if shouldShowControls, viewModel.isPlaying {
            scheduleLandscapeControlsAutoHide()
        }
    }

    private func handlePortraitVideoTap() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible.toggle()
        }
    }

    private func handlePlaybackStateChange(isPlaying: Bool, isLandscape: Bool) {
        guard isLandscape else {
            return
        }

        landscapeControlsHideToken = UUID()

        if isPlaying {
            if areLandscapeControlsVisible {
                scheduleLandscapeControlsAutoHide()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                areLandscapeControlsVisible = true
            }
        }
    }

    private func updateFullscreenControlsVisibility(isLandscape: Bool) {
        landscapeControlsHideToken = UUID()

        guard isLandscape else {
            areLandscapeControlsVisible = true
            return
        }

        let shouldShowControls = !viewModel.isPlaying
        areLandscapeControlsVisible = shouldShowControls

        if !shouldShowControls {
            scheduleLandscapeControlsAutoHide()
        }
    }

    private func scheduleLandscapeControlsAutoHide() {
        let token = UUID()
        landscapeControlsHideToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard self.landscapeControlsHideToken == token, self.viewModel.isPlaying, !self.isScrubbing else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                self.areLandscapeControlsVisible = false
            }
        }
    }
}

private enum VideoPlayerOrientationHelper {
    static func requestOrientation(_ orientation: UIInterfaceOrientation) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        let mask: UIInterfaceOrientationMask = orientation.isLandscape ? .landscape : .portrait

        // SwiftUI does not expose a guaranteed fullscreen AVPlayer rotation API,
        // so we request scene geometry changes and let iOS decide whether to honor them.
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))

        if let rootViewController = windowScene.keyWindow?.rootViewController {
            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

private struct NativeVideoPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

struct PlayerView: View {
    var body: some View {
        NavigationStack {
            Text("Player placeholder")
                .navigationTitle("Player")
        }
    }
}

#Preview {
    NavigationStack {
        AudioPlayerView(
            item: MediaItem(
                providerName: "preview",
                providerItemID: "preview-item",
                title: "Preview Audio",
                creatorName: "Preview Creator",
                mediaType: .audio,
                downloadStatus: .downloaded,
                localFilePath: "/tmp/audio.m4a"
            )
        )
    }
    .environmentObject(AudioPlaybackController.shared)
}
