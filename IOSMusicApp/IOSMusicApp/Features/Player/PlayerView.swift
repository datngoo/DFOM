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
    private var lastPublishedElapsedTime: Double?

    private init() {}

    func attachRemoteCommands(
        owner: AnyObject,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onPreviousTrack: (() -> Void)? = nil,
        onNextTrack: (() -> Void)? = nil
    ) {
        activeOwnerID = ObjectIdentifier(owner)
        playHandler = onPlay
        pauseHandler = onPause
        previousTrackHandler = onPreviousTrack
        nextTrackHandler = onNextTrack

        if remoteCommandsRegistered {
            updateTrackNavigationCommands()
            return
        }

        remoteCommandsRegistered = true

        // Keep remote controls minimal for the current offline audio feature scope.
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = false
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
    }

    func detachRemoteCommands(owner: AnyObject) {
        guard activeOwnerID == ObjectIdentifier(owner) else {
            return
        }

        activeOwnerID = nil
        playHandler = nil
        pauseHandler = nil
        previousTrackHandler = nil
        nextTrackHandler = nil
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
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private let backgroundAudioCoordinator: BackgroundAudioCoordinator
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "AudioPlaybackController")

    private init(fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        self.fileStorage = fileStorage
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
        ensureRemoteCommandsAttached()
        syncRemoteTrackNavigationAvailability()

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
        syncRemoteTrackNavigationAvailability()
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
        syncRemoteTrackNavigationAvailability()
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
        syncRemoteTrackNavigationAvailability()
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
            onPreviousTrack: { [weak self] in self?.playPreviousTrack() },
            onNextTrack: { [weak self] in self?.playNextTrack() }
        )
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

struct AudioPlayerView: View {
    @EnvironmentObject private var playbackController: AudioPlaybackController

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
        VStack(alignment: .leading, spacing: 20) {
            Text(playbackController.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(playbackController.errorMessage ?? playbackController.playbackStateText)
                .font(.body)
                .foregroundStyle(playbackController.errorMessage == nil ? Color.secondary : Color.red)

            VStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { min(playbackController.currentTime, playbackController.displayedDuration) },
                        set: { playbackController.seek(to: $0) }
                    ),
                    in: 0...playbackController.displayedDuration
                )
                .disabled(!playbackController.canControlPlayback || playbackController.displayedDuration <= 0)

                HStack {
                    Text(playbackController.formattedTime(playbackController.currentTime))
                    Spacer()
                    Text(playbackController.formattedTime(playbackController.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                playbackController.cyclePlaybackMode()
            } label: {
                Label(playbackController.playbackMode.title, systemImage: playbackController.playbackMode.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!playbackController.canControlPlayback)

            VStack(spacing: 18) {
                Text("Playback Controls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 20) {
                    playerControlButton(
                        systemName: "backward.fill",
                        size: 52,
                        isPrimary: false,
                        isDisabled: !playbackController.canPlayPreviousTrack
                    ) {
                        playbackController.playPreviousTrack()
                    }

                    playerControlButton(
                        systemName: playbackController.isPlaying ? "pause.fill" : "play.fill",
                        size: 62,
                        isPrimary: true,
                        isDisabled: !playbackController.canControlPlayback
                    ) {
                        playbackController.togglePlayback()
                    }

                    playerControlButton(
                        systemName: "forward.fill",
                        size: 52,
                        isPrimary: false,
                        isDisabled: !playbackController.canPlayNextTrack
                    ) {
                        playbackController.playNextTrack()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )

            Spacer()
        }
        .padding()
        .navigationTitle("Audio Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let item {
                playbackController.configure(item: item, playlist: playlist, fileStorage: fileStorage)
            }
        }
    }

    private func playerControlButton(
        systemName: String,
        size: CGFloat,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(isPrimary ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .frame(width: size, height: size)
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .background(
                    Circle()
                        .fill(isPrimary ? Color.accentColor : Color(.systemBackground))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isPrimary ? Color.accentColor.opacity(0.2) : Color(.separator).opacity(0.18),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isPrimary ? Color.accentColor.opacity(0.22) : Color.black.opacity(0.06),
                    radius: isPrimary ? 12 : 6,
                    y: isPrimary ? 6 : 2
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct GlobalAudioMiniPlayer: View {
    private enum Layout {
        static let contentSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 14
        static let verticalPadding: CGFloat = 10
        static let buttonSize: CGFloat = 34
        static let cornerRadius: CGFloat = 18
        static let progressHeight: CGFloat = 3
    }

    @EnvironmentObject private var playbackController: AudioPlaybackController

    var body: some View {
        if let currentMediaItem = playbackController.currentMediaItem {
            Button {
                playbackController.presentFullPlayer()
            } label: {
                VStack(alignment: .leading, spacing: Layout.contentSpacing) {
                    HStack(spacing: 12) {
                        Text(currentMediaItem.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            playbackController.togglePlayback()
                        } label: {
                            Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))

                            Capsule()
                                .fill(Color.accentColor.opacity(0.9))
                                .frame(width: max(proxy.size.width * playbackController.progressFraction, 6))
                        }
                    }
                    .frame(height: Layout.progressHeight)
                }
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, Layout.verticalPadding)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .stroke(Color(.separator).opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        }
    }
}

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var playbackStateText = "Preparing"
    @Published var errorMessage: String?

    private let item: MediaItem
    private let fileStorage: LocalFileStorage
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private let backgroundAudioCoordinator: BackgroundAudioCoordinator
    private var didPreparePlayer = false
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
    let player = AVPlayer()

    init(item: MediaItem, fileStorage: LocalFileStorage) {
        self.item = item
        self.fileStorage = fileStorage
        self.audioSessionCoordinator = .shared
        self.backgroundAudioCoordinator = .shared
        self.title = item.title
        self.player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        backgroundAudioCoordinator.attachRemoteCommands(
            owner: self,
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() }
        )
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
            backgroundAudioCoordinator.detachRemoteCommands(owner: self)
        }
    }

    func prepareIfNeeded() {
        guard !didPreparePlayer else {
            return
        }

        didPreparePlayer = true
        Task {
            await preparePlayer()
        }
    }

    func play() {
        guard errorMessage == nil else {
            return
        }

        playWhenReady = true

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

    func handleDisappear(scenePhase: ScenePhase) {
        guard scenePhase == .active else {
            return
        }

        pause()
    }

    private func preparePlayer() async {
        guard item.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setError("Video file path is missing.")
            return
        }

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
            playWhenReady = false
            currentTime = 0
            duration = 0
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
            if errorMessage == nil {
                playbackStateText = isReadyToPlay ? "Ready" : "Loading"
            }
            publishNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            if errorMessage == nil {
                playbackStateText = "Buffering"
            }
            publishNowPlaying()
        case .playing:
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
        publishNowPlaying()
    }

    private func handlePlaybackEnded() {
        playWhenReady = false
        playbackStateText = "Finished"
        currentTime = duration
        publishNowPlaying()
    }

    private func setError(_ message: String) {
        removeObservers()
        playWhenReady = false
        isReadyToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentPlayerItem = nil
        errorMessage = message
        playbackStateText = "Unavailable"
        currentTime = 0
        duration = 0
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
        backgroundAudioCoordinator.publishNowPlaying(
            item: item,
            fileStorage: fileStorage,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: player.timeControlStatus == .playing
        )
    }
}

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(item: MediaItem, fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(item: item, fileStorage: fileStorage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.errorMessage ?? viewModel.playbackStateText)
                .font(.body)
                .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.red)

            VideoPlayer(player: viewModel.player)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Play") {
                    viewModel.play()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.errorMessage != nil)

                Button("Pause") {
                    viewModel.pause()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.errorMessage != nil)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Video Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: viewModel.prepareIfNeeded)
        .onDisappear {
            viewModel.handleDisappear(scenePhase: scenePhase)
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
